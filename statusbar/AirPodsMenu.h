// AirPodsMenu.h -- the AirPods menu (MacStatusBar&Dock 1.8.8.1; plans/airpods-menu.md, design v2 and its check), included into StatusBar.x right
// after CC18Tiles.h. Settings > Status Bar > AirPods Menu (pref airpodsMenu, on unless switched off, updaters too: DMAirPodsApplyPref).
//  - An invisible button of ours sits over iPadOS's own AirPods item in the menu bar (its Bluetooth item, whenever it shows headphones: their
//    glyph alone, as iPadOS 17/18 show AirPods, or the glyph with their level; 1.8.8.1.1), found through the bar's own regions as the battery's
//    views are (DMAPItemViews). iPadOS keeps drawing the item. A pointer click or a finger tap on it opens a Mac-style menu under it instead of
//    the status icons' region action (StatusBar.x DMPointOverOurControl). A Bluetooth indicator that is not headphones' gets no button
//    (common/AirPodsMenu.h MSBDAirPodsItemIsHeadphones). The button never overlaps the battery's own (MSBDAirPodsButtonSpan).
//  - Where iPadOS draws no item for connected headphones (15.6.1 with real AirPods; 1.8.8.2), the bar draws a headphones icon of its own where
//    the status icons start, the same button over it (MSBDAirPodsOwnIcon, DMAirPodsLayoutOwnIcon): never two icons. On 15/16 only, a moment
//    after the headphones come (17/18 draw their own glyph for them).
//  - The menu, in macOS's order: the headphones' name; their battery as BatteryCenter gives it (Left and Right as one level when it merges them,
//    apart when it splits them, and the Case), or one level at the heading's right; Noise Control with only the modes they offer, while they are
//    the audio output; Disconnect; Bluetooth Settings…. Two sets: a block each. They drop while it is open: Not Connected and Connect.
//  - The data, three caches: the headphones (BluetoothManager, main thread: read at the menu's open, when VoiceOver asks for the button's value
//    and on Bluetooth's notifications while it is open); the battery records (BatteryCenter, pushed to an observer of ours on our own queue, as
//    SpringBoard's own accessory battery monitor gets them: never a power-source read on the main thread); the route (MediaRemote's system route,
//    Control Center's own path: read at the open, on its notification and after a mode change). No timer.
//  - Every private call is asked first through a table of the exact types (kDMAPNeeds, DMAPCheck) and again on the object's own class before it
//    is made; a part whose rows are not all there is never called and its rows are hidden; a throw turns its part off until the next respring.
//    Never called: BatteryCenter's shared instance and its notification name (neither exists from 15 on), BluetoothDevice's battery status
//    struct call (its size changed between 15 and 18), the leader device getter (a void pointer on 15), key-value reads.
//  - Its rules are plain C in common/AirPodsMenu.h (Mac-tested, tools/test-airpodsmenu.sh); the Objective-C side only reads, turns rows into
//    views and acts. Apple's private calls are made only from functions named DMAP..., so a crash there is blamed on the AirPods Menu.
// Logs never name a device: a short hash (DMWiFiTag), counts, parts bits, levels and mode strings.
#import "../common/AirPodsMenu.h"

static const void *kAPMenuLabelKey = &kAPMenuLabelKey, *kAPMenuPillKey = &kAPMenuPillKey;   // (DMPresentMenu: no title label or pill, as the battery menu)
static const void *kAPAXWasKey = &kAPAXWasKey, *kAPCoveredKey = &kAPCoveredKey, *kAPShownKey = &kAPShownKey;
static const CGFloat kAPStripRowH = 34.0, kAPSectionRowH = 24.0;   // (at Small: the battery menu's switch row's and the Wi-Fi menu's heading's)
#define DMAP_BM "/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager"
#define DMAP_BC "/System/Library/PrivateFrameworks/BatteryCenter.framework/BatteryCenter"
#define DMAP_MP "/System/Library/Frameworks/MediaPlayer.framework/MediaPlayer"
#define DMAP_MR "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"

// ---- the type table: what the menu asks, with the types read in the iPadOS 17.6.1 and 18.2 decompiles and on this Mac (BOOL is B on arm64);
// D0 reads them on all four iPads (podmenu_probe) ----
typedef struct { const char *cls, *sel, *enc; BOOL meta; int part; } DMAPNeedRow;
enum { kDMAPPartHeadset = 0, kDMAPPartParts, kDMAPPartNoise, kDMAPParts };
static const DMAPNeedRow kDMAPNeeds[] = {
    { "BluetoothManager", "sharedInstance", "@16@0:8", YES, kDMAPPartHeadset },
    { "BluetoothManager", "connectedDevices", "@16@0:8", NO, kDMAPPartHeadset },
    { "BluetoothDevice", "name", "@16@0:8", NO, kDMAPPartHeadset },
    { "BluetoothDevice", "address", "@16@0:8", NO, kDMAPPartHeadset },
    { "BluetoothDevice", "connected", "B16@0:8", NO, kDMAPPartHeadset },
    { "BluetoothDevice", "connect", "v16@0:8", NO, kDMAPPartHeadset },
    { "BluetoothDevice", "disconnect", "v16@0:8", NO, kDMAPPartHeadset },
    { "BluetoothDevice", "supportsBatteryLevel", "B16@0:8", NO, kDMAPPartHeadset },
    { "BluetoothDevice", "batteryLevel", "i16@0:8", NO, kDMAPPartHeadset },
    { "BluetoothDevice", "productId", "I16@0:8", NO, kDMAPPartHeadset },
    { "BluetoothDevice", "isAppleAudioDevice", "B16@0:8", NO, kDMAPPartHeadset },
    { "BCBatteryDeviceController", "init", "@16@0:8", NO, kDMAPPartParts },
    { "BCBatteryDeviceController", "addBatteryDeviceObserver:queue:", "v32@0:8@16@24", NO, kDMAPPartParts },
    { "BCBatteryDeviceController", "removeBatteryDeviceObserver:", "v24@0:8@16", NO, kDMAPPartParts },
    { "BCBatteryDevice", "parts", "Q16@0:8", NO, kDMAPPartParts },
    { "BCBatteryDevice", "percentCharge", "q16@0:8", NO, kDMAPPartParts },
    { "BCBatteryDevice", "isCharging", "B16@0:8", NO, kDMAPPartParts },
    { "BCBatteryDevice", "isInternal", "B16@0:8", NO, kDMAPPartParts },
    { "BCBatteryDevice", "groupName", "@16@0:8", NO, kDMAPPartParts },
    { "BCBatteryDevice", "matchIdentifier", "@16@0:8", NO, kDMAPPartParts },
    { "BCBatteryDevice", "productIdentifier", "q16@0:8", NO, kDMAPPartParts },
    { "MPAVRoutingController", "systemRoute", "@16@0:8", YES, kDMAPPartNoise },
    { "MPAVEndpointRoute", "endpointObject", "@16@0:8", NO, kDMAPPartNoise },
    { "MRAVEndpoint", "outputDevices", "@16@0:8", NO, kDMAPPartNoise },
    { "MRAVEndpoint", "setListeningMode:outputDeviceUID:queue:completion:", "v48@0:8@16@24@32@?40", NO, kDMAPPartNoise },
    { "MRAVOutputDevice", "uid", "@16@0:8", NO, kDMAPPartNoise },
    { "MRAVOutputDevice", "deviceType", "I16@0:8", NO, kDMAPPartNoise },
    { "MRAVOutputDevice", "currentBluetoothListeningMode", "@16@0:8", NO, kDMAPPartNoise },
    { "MRAVOutputDevice", "availableBluetoothListeningModes", "@16@0:8", NO, kDMAPPartNoise },
};
static BOOL gAPPart[kDMAPParts];
static BOOL gAPChecked = NO, gAPSourcesStarted = NO;
static NSString *gAPRouteNote = nil;   // (MediaPlayer's own route change notification name, from its constant; nil: not observed)
static BOOL DMAPRowOK(const DMAPNeedRow *r) {
    Class c = objc_getClass(r->cls);
    Method m = !c ? NULL : r->meta ? class_getClassMethod(c, sel_registerName(r->sel)) : class_getInstanceMethod(c, sel_registerName(r->sel));
    const char *t = m ? method_getTypeEncoding(m) : NULL;
    return t && !strcmp(t, r->enc);
}
static NSString *DMAPFrameworkString(const char *framework, const char *symbol) {   // (an exported NSString constant, nil where it is not)
    void *h = dlopen(framework, RTLD_LAZY | RTLD_NOLOAD) ?: dlopen(framework, RTLD_LAZY);
    void **p = h ? dlsym(h, symbol) : NULL;
    id s = p ? (__bridge id)*p : nil;
    return [s isKindOfClass:[NSString class]] ? s : nil;
}
// Once, on the main thread, the first time a button is placed (outside the layout pass) or the menu opens: a framework whose class is missing is
// opened then, never earlier and never from a constructor.
static void DMAPCheck(void) {
    if (gAPChecked) return;
    gAPChecked = YES;
    if (!objc_getClass("BluetoothManager")) dlopen(DMAP_BM, RTLD_LAZY);
    if (!objc_getClass("BCBatteryDeviceController")) dlopen(DMAP_BC, RTLD_LAZY);
    if (!objc_getClass("MPAVRoutingController")) dlopen(DMAP_MP, RTLD_LAZY);
    if (!objc_getClass("MRAVEndpoint")) dlopen(DMAP_MR, RTLD_LAZY);
    for (int p = 0; p < kDMAPParts; p++) gAPPart[p] = YES;
    NSMutableArray *missing = [NSMutableArray array];
    for (size_t i = 0; i < sizeof(kDMAPNeeds) / sizeof(kDMAPNeeds[0]); i++) {
        if (DMAPRowOK(&kDMAPNeeds[i])) continue;
        gAPPart[kDMAPNeeds[i].part] = NO;
        [missing addObject:[NSString stringWithFormat:@"%c[%s %s]", kDMAPNeeds[i].meta ? '+' : '-', kDMAPNeeds[i].cls, kDMAPNeeds[i].sel]];
    }
    gAPRouteNote = DMAPFrameworkString(DMAP_MP, "MPAVRouteDidChangeNotification");
    DMLog([NSString stringWithFormat:@"[podmenu] API: headphones %d, battery records %d, noise control %d (route notification %@)%@", gAPPart[kDMAPPartHeadset],
        gAPPart[kDMAPPartParts], gAPPart[kDMAPPartNoise], gAPRouteNote ? @"found" : @"none",
        missing.count ? [@"; missing: " stringByAppendingString:[missing componentsJoinedByString:@", "]] : @""]);
}
static void DMAPPartFailed(int part, NSException *e) {   // (a throw: that part off until the next respring, said once)
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gAPPart[part]) return;
        gAPPart[part] = NO;
        DMLog([NSString stringWithFormat:@"[podmenu] part %d threw (%@): off until the next respring", part, e.name]);
    });
}
// A method of exactly these types on this object's own class (the objects are subclasses: concrete and distant endpoints and devices).
static BOOL DMAPTypes(id obj, SEL sel, const char *types) {
    Method m = obj ? class_getInstanceMethod(object_getClass(obj), sel) : NULL;
    const char *t = m ? method_getTypeEncoding(m) : NULL;
    return t && !strcmp(t, types);
}
static id DMAPObj(id obj, SEL sel) { return DMAPTypes(obj, sel, "@16@0:8") ? ((id (*)(id, SEL))objc_msgSend)(obj, sel) : nil; }
static NSString *DMAPStr(id obj, SEL sel) { id s = DMAPObj(obj, sel); return [s isKindOfClass:[NSString class]] ? s : nil; }
static void DMAPCopyStr(char *dst, size_t n, NSString *s) {   // (cut, if it must be, before a whole UTF-8 character: a name always comes back as a string)
    const char *u = s.UTF8String ?: "";
    size_t l = strlen(u);
    if (!n) return;
    if (l >= n) { l = n - 1; while (l > 0 && ((unsigned char)u[l] & 0xC0) == 0x80) l--; }
    memcpy(dst, u, l); dst[l] = 0;
}

// ---- the headphones (BluetoothManager: SpringBoard's own shared instance, main thread only) ----
@interface DMAPHeadsetRec : NSObject
@property (nonatomic, copy) NSString *name, *address;
@property (nonatomic) long long productId;
@property (nonatomic) int level;
@property (nonatomic) BOOL apple, connected, fake;
@property (nonatomic) BOOL phones;   // (headphones: common/AirPodsMenu.h MSBDAirPodsCountsAsHeadphones -- our own icon's, 1.8.8.2)
@property (nonatomic, strong) id device;   // (the BluetoothDevice: Connect and Disconnect; nil for a test device)
@end
@implementation DMAPHeadsetRec
@end
// The route's output devices (main thread), as plain values.
@interface DMAPRouteRec : NSObject
@property (nonatomic, copy) NSString *uid;
@property (nonatomic) unsigned type, modes;
@property (nonatomic) int current;
@end
@implementation DMAPRouteRec
@end
#if DEBUG
static int gAPFake = 0;   // (tests: podfake_<kind> -- the three caches made up, iPadOS's item shown through sbfakebt_; 0: the real state)
static NSMutableArray<DMAPHeadsetRec *> *gAPFakeHeadsets;
static NSData *gAPFakeParts;
static NSMutableArray<DMAPRouteRec *> *gAPFakeRoute;
static BOOL gAPFakeErr = NO;   // (podfake_err: the next mode change fails)
static unsigned gAPFakePartsOff = 0;   // (podfake_part_<h|p|n>_<0|1>: a part shown as missing, for the rows of each part off)
static BOOL gAPFakeGlyphOnly = NO;   // (podfake_bar_<glyph|level>: iPadOS's item for the made-up headphones as the glyph alone, or with their level)
static BOOL gAPFakeNoItem = NO;   // (podfake_bar_none, 1.8.8.2: no item for them at all, as iPadOS 15.6.1 shows real AirPods: our own icon's case)
static void DMAPFakeShowItem(void);   // (below: iPadOS's item comes or goes with the made-up headphones, through sbfakebt_)
#endif
static unsigned gAPReadCount = 0;   // (what the probe shows: how many devices are listed, how many of them report a battery level, are headphones
static unsigned gAPBattDevices = 0, gAPAppleAudio = 0, gAPHeadphoneTypes = 0;   //  by iPadOS's type, are Apple's audio)
static NSArray<DMAPHeadsetRec *> *DMAPReadHeadsets(void) {
#if DEBUG
    if (gAPFake) { NSMutableArray *o = [NSMutableArray array]; for (DMAPHeadsetRec *h in gAPFakeHeadsets) if (h.connected) [o addObject:h]; return o; }
#endif
    if (!gAPPart[kDMAPPartHeadset]) return @[];
    NSMutableArray<DMAPHeadsetRec *> *out = [NSMutableArray array];
    @try {
        static SEL sShared, sConnected, sName, sAddr, sIsConn, sSupports, sLevel, sPid, sApple, sType;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            sShared = NSSelectorFromString(@"sharedInstance"); sConnected = NSSelectorFromString(@"connectedDevices"); sName = NSSelectorFromString(@"name");
            sAddr = NSSelectorFromString(@"address"); sIsConn = NSSelectorFromString(@"connected"); sSupports = NSSelectorFromString(@"supportsBatteryLevel");
            sLevel = NSSelectorFromString(@"batteryLevel"); sPid = NSSelectorFromString(@"productId"); sApple = NSSelectorFromString(@"isAppleAudioDevice");
            sType = NSSelectorFromString(@"type");
        });
        id bt = ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("BluetoothManager"), sShared);
        NSArray *list = DMAPObj(bt, sConnected);
        if (![list isKindOfClass:[NSArray class]]) return @[];
        Class dc = objc_getClass("BluetoothDevice");
        unsigned batt = 0, apple = 0, phones = 0;
        for (id d in list) {
            if (![d isKindOfClass:dc] || out.count >= MSBD_AP_MAX_HEADSETS) continue;
            if (!DMAPTypes(d, sSupports, "B16@0:8") || !DMAPTypes(d, sIsConn, "B16@0:8") || !DMAPTypes(d, sLevel, "i16@0:8") || !DMAPTypes(d, sPid, "I16@0:8") || !DMAPTypes(d, sApple, "B16@0:8")) continue;
            BOOL typeRead = DMAPTypes(d, sType, "i16@0:8") || DMAPTypes(d, sType, "I16@0:8");   // (iPadOS's headphones rule; not asked where it has another type)
            int type = typeRead ? ((int (*)(id, SEL))objc_msgSend)(d, sType) : 0;
            BOOL level = ((BOOL (*)(id, SEL))objc_msgSend)(d, sSupports);
            if (!MSBDAirPodsListsDevice(((BOOL (*)(id, SEL))objc_msgSend)(d, sIsConn), level, typeRead, type)) continue;   // (connected: headphones, or a level)
            DMAPHeadsetRec *h = [DMAPHeadsetRec new];
            h.name = DMAPStr(d, sName) ?: @""; h.address = DMAPStr(d, sAddr) ?: @"";
            h.level = level ? ((int (*)(id, SEL))objc_msgSend)(d, sLevel) : -1;   // (no level reported: BatteryCenter's records, else "--")
            h.productId = ((unsigned (*)(id, SEL))objc_msgSend)(d, sPid);
            h.apple = ((BOOL (*)(id, SEL))objc_msgSend)(d, sApple);
            h.phones = MSBDAirPodsCountsAsHeadphones(typeRead, type, h.apple);
            h.connected = YES; h.device = d;
            if (level) batt++;
            if (MSBDAirPodsIsHeadphonesType(typeRead, type)) phones++;
            if (h.apple) apple++;
            [out addObject:h];
        }
        gAPBattDevices = batt; gAPAppleAudio = apple; gAPHeadphoneTypes = phones; gAPReadCount++;
    } @catch (NSException *e) { DMAPPartFailed(kDMAPPartHeadset, e); return @[]; }
    return out;
}

// ---- the battery records (BatteryCenter: one controller and one observer of ours, both kept -- it holds observers weakly --, called on our own
// serial queue; the records copied there into plain values and handed to the main thread). Added the first time a button is placed; removed, and
// the records forgotten, when the switch goes off; added again on the next main-queue turn when it comes back on (BatteryCenter delivers the
// list at once). Never from a constructor. ----
@interface DMAPBatteryWatch : NSObject
@property (nonatomic) unsigned gen;
- (void)connectedDevicesDidChange:(NSArray *)devices;
@end
static id gAPBCController = nil;
static DMAPBatteryWatch *gAPBatteryWatch = nil;
static unsigned gAPPartsGen = 0, gAPPartsDeliveries = 0, gAPPartsInternal = 0;
static NSData *gAPParts = nil;   // (MSBDAPPart records, BatteryCenter's last list; nil: none yet)
static void DMAPMenuChanged(void);
static dispatch_queue_t DMAPQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("com.besiktasliseba.macstatusbar.airpods", DISPATCH_QUEUE_SERIAL); });
    return q;
}
static NSData *DMAPPartsCopy(NSArray *devices, unsigned *internal) {
    static SEL sParts, sPct, sChg, sInt, sGroup, sMatch, sPid;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sParts = NSSelectorFromString(@"parts"); sPct = NSSelectorFromString(@"percentCharge"); sChg = NSSelectorFromString(@"isCharging");
        sInt = NSSelectorFromString(@"isInternal"); sGroup = NSSelectorFromString(@"groupName"); sMatch = NSSelectorFromString(@"matchIdentifier");
        sPid = NSSelectorFromString(@"productIdentifier");
    });
    NSMutableData *d = [NSMutableData data];
    Class dc = objc_getClass("BCBatteryDevice");
    *internal = 0;
    if (![devices isKindOfClass:[NSArray class]]) return d;
    for (id x in devices) {
        if (![x isKindOfClass:dc] || d.length / sizeof(MSBDAPPart) >= MSBD_AP_MAX_PARTS) continue;
        if (!DMAPTypes(x, sParts, "Q16@0:8") || !DMAPTypes(x, sPct, "q16@0:8") || !DMAPTypes(x, sChg, "B16@0:8") || !DMAPTypes(x, sInt, "B16@0:8")
            || !DMAPTypes(x, sPid, "q16@0:8")) continue;
        if (((BOOL (*)(id, SEL))objc_msgSend)(x, sInt)) { (*internal)++; continue; }   // (the iPad's own battery)
        MSBDAPPart p; memset(&p, 0, sizeof p);
        p.parts = ((unsigned long long (*)(id, SEL))objc_msgSend)(x, sParts);
        long long pct = ((long long (*)(id, SEL))objc_msgSend)(x, sPct);
        p.percent = pct < -1 ? -1 : pct > 1000 ? 1000 : (int)pct;
        p.charging = ((BOOL (*)(id, SEL))objc_msgSend)(x, sChg);
        p.productId = ((long long (*)(id, SEL))objc_msgSend)(x, sPid);
        DMAPCopyStr(p.groupName, sizeof p.groupName, DMAPStr(x, sGroup));
        DMAPCopyStr(p.matchId, sizeof p.matchId, DMAPStr(x, sMatch));
        [d appendBytes:&p length:sizeof p];
    }
    return d;
}
@implementation DMAPBatteryWatch
- (void)connectedDevicesDidChange:(NSArray *)devices {   // (on our queue)
    unsigned gen = self.gen, internal = 0;
    NSData *d = nil;
    @try { d = DMAPPartsCopy(devices, &internal); } @catch (NSException *e) { DMAPPartFailed(kDMAPPartParts, e); return; }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gen != gAPPartsGen || !gAPBatteryWatch) return;   // (removed since, or added again: not this one's)
        gAPParts = d; gAPPartsDeliveries++; gAPPartsInternal = internal;
        DMAPMenuChanged();
    });
}
@end
static void DMAPPartsStart(void) {   // (main thread)
    if (!gAirPodsMenuOn || !gAPChecked || !gAPPart[kDMAPPartParts] || gAPBatteryWatch) return;
    @try {
        Class c = objc_getClass("BCBatteryDeviceController");
        id ctl = [[c alloc] init];
        SEL add = NSSelectorFromString(@"addBatteryDeviceObserver:queue:"), rem = NSSelectorFromString(@"removeBatteryDeviceObserver:");
        if (!DMAPTypes(ctl, add, "v32@0:8@16@24") || !DMAPTypes(ctl, rem, "v24@0:8@16")) { DMLog(@"[podmenu] BatteryCenter's controller has other types here: no battery records"); return; }
        DMAPBatteryWatch *w = [DMAPBatteryWatch new];
        w.gen = ++gAPPartsGen;
        gAPBCController = ctl; gAPBatteryWatch = w;
        ((void (*)(id, SEL, id, id))objc_msgSend)(ctl, add, w, DMAPQueue());
        DMLog(@"[podmenu] BatteryCenter's records observed");
    } @catch (NSException *e) { gAPBatteryWatch = nil; gAPBCController = nil; DMAPPartFailed(kDMAPPartParts, e); }
}
static void DMAPPartsStop(void) {   // (main thread)
    gAPPartsGen++;   // (a delivery on its way is dropped)
    gAPParts = nil;
    if (!gAPBatteryWatch) return;
    @try { ((void (*)(id, SEL, id))objc_msgSend)(gAPBCController, NSSelectorFromString(@"removeBatteryDeviceObserver:"), gAPBatteryWatch); }
    @catch (NSException *e) { DMAPPartFailed(kDMAPPartParts, e); }
    gAPBatteryWatch = nil; gAPBCController = nil;
    DMLog(@"[podmenu] BatteryCenter's records no longer observed");
}
static NSData *DMAPPartsNow(void) {
#if DEBUG
    if (gAPFake) return gAPFakeParts;
#endif
    return gAPParts;
}

// ---- the route (MediaRemote's system route, as Control Center reads it: on the main thread, at events only) ----
static id gAPSystemRoute = nil;   // (+[MPAVRoutingController systemRoute], made once and kept, as Control Center does)
static double gAPRouteReadMs = -1;
static id DMAPSystemRoute(void) {
    if (gAPSystemRoute || !gAPPart[kDMAPPartNoise]) return gAPSystemRoute;
    @try {
        id r = ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("MPAVRoutingController"), NSSelectorFromString(@"systemRoute"));
        if (DMAPTypes(r, NSSelectorFromString(@"endpointObject"), "@16@0:8")) gAPSystemRoute = r;
        else DMLog(@"[podmenu] the system route has other types here: no noise control");
    } @catch (NSException *e) { DMAPPartFailed(kDMAPPartNoise, e); }
    return gAPSystemRoute;
}
static id DMAPEndpoint(void) {
    id r = DMAPSystemRoute();
    return r ? DMAPObj(r, NSSelectorFromString(@"endpointObject")) : nil;
}
static NSArray<DMAPRouteRec *> *DMAPReadRoute(void) {
#if DEBUG
    if (gAPFake) {   // (copies: the tick a tap moves at once is the menu's, not the test device's)
        NSMutableArray *o = [NSMutableArray array];
        for (DMAPRouteRec *f in gAPFakeRoute) { DMAPRouteRec *r = [DMAPRouteRec new]; r.uid = f.uid; r.type = f.type; r.modes = f.modes; r.current = f.current; [o addObject:r]; }
        return o;
    }
#endif
    if (!gAPPart[kDMAPPartNoise]) return @[];
    NSMutableArray<DMAPRouteRec *> *out = [NSMutableArray array];
    CFTimeInterval t0 = CACurrentMediaTime();
    @try {
        static SEL sDevs, sUID, sType, sCur, sAvail;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            sDevs = NSSelectorFromString(@"outputDevices"); sUID = NSSelectorFromString(@"uid"); sType = NSSelectorFromString(@"deviceType");
            sCur = NSSelectorFromString(@"currentBluetoothListeningMode"); sAvail = NSSelectorFromString(@"availableBluetoothListeningModes");
        });
        NSArray *devs = DMAPObj(DMAPEndpoint(), sDevs);
        if (![devs isKindOfClass:[NSArray class]]) return @[];
        for (id dev in devs) {
            if (out.count >= MSBD_AP_MAX_ROUTE) break;
            if (!DMAPTypes(dev, sUID, "@16@0:8") || !DMAPTypes(dev, sType, "I16@0:8") || !DMAPTypes(dev, sCur, "@16@0:8") || !DMAPTypes(dev, sAvail, "@16@0:8")) continue;
            DMAPRouteRec *r = [DMAPRouteRec new];
            r.uid = DMAPStr(dev, sUID) ?: @"";
            r.type = ((unsigned (*)(id, SEL))objc_msgSend)(dev, sType);
            NSArray *avail = DMAPObj(dev, sAvail);
            unsigned mask = 0;
            if ([avail isKindOfClass:[NSArray class]]) for (id m in avail) if ([m isKindOfClass:[NSString class]]) { int i = MSBDAirPodsModeIndex([m UTF8String]); if (i >= 0) mask |= 1u << i; }
            r.modes = mask;
            NSString *cur = DMAPStr(dev, sCur);
            r.current = cur ? MSBDAirPodsModeIndex(cur.UTF8String) : -1;
            [out addObject:r];
        }
    } @catch (NSException *e) { DMAPPartFailed(kDMAPPartNoise, e); return @[]; }
    gAPRouteReadMs = (CACurrentMediaTime() - t0) * 1000.0;
    return out;
}

// ---- the open menu's state ----
static BOOL gAPMenuOpen = NO;
static __weak UIView *gAPPanel = nil;
static uint64_t gAPMenuSig = 0;
static NSMutableArray<DMAPHeadsetRec *> *gAPMenuHeadsets = nil;   // (the headphones the open menu lists: those it opened with -- kept, Not Connected, when they go -- and any that came since)
static NSArray<DMAPRouteRec *> *gAPRoute = nil;
static BOOL gAPNoiseError = NO;
static unsigned gAPModesPending = 0;
static void DMAPMergeHeadsets(NSArray<DMAPHeadsetRec *> *now) {
    if (!gAPMenuHeadsets) gAPMenuHeadsets = [NSMutableArray array];
    for (NSUInteger i = 0; i < gAPMenuHeadsets.count; i++) {
        DMAPHeadsetRec *was = gAPMenuHeadsets[i], *is = nil;
        for (DMAPHeadsetRec *h in now) if ([h.address isEqualToString:was.address]) { is = h; break; }
        if (is) gAPMenuHeadsets[i] = is;
        else was.connected = NO;
    }
    for (DMAPHeadsetRec *h in now) {
        BOOL known = NO;
        for (DMAPHeadsetRec *w in gAPMenuHeadsets) if ([w.address isEqualToString:h.address]) { known = YES; break; }
        if (!known && gAPMenuHeadsets.count < MSBD_AP_MAX_HEADSETS) [gAPMenuHeadsets addObject:h];
    }
}
static BOOL DMAPPartOn(int part) {
#if DEBUG
    if (gAPFake) return !(gAPFakePartsOff & (1u << part));
#endif
    return gAPChecked && gAPPart[part];
}
// The plain-C state from the caches (common/AirPodsMenu.h builds the blocks and the rows from it).
static void DMAPFillState(MSBDAPState *st, NSArray<DMAPHeadsetRec *> *heads, NSArray<DMAPRouteRec *> *route, BOOL err) {
    memset(st, 0, sizeof *st);
    st->headsetPart = DMAPPartOn(kDMAPPartHeadset); st->partsPart = DMAPPartOn(kDMAPPartParts); st->noisePart = DMAPPartOn(kDMAPPartNoise);
    for (DMAPHeadsetRec *h in heads) {
        if (st->nheadsets >= MSBD_AP_MAX_HEADSETS) break;
        MSBDAPHeadset *o = &st->headsets[st->nheadsets++];
        DMAPCopyStr(o->name, sizeof o->name, h.name);
        DMAPCopyStr(o->shown, sizeof o->shown, h.name.length ? MSBDShotBTName(h.name) : @"");
        DMAPCopyStr(o->address, sizeof o->address, h.address);
        o->productId = h.productId; o->level = h.level; o->connected = h.connected;
    }
    NSData *parts = DMAPPartsNow();
    st->nparts = (int)MIN((NSUInteger)MSBD_AP_MAX_PARTS, parts.length / sizeof(MSBDAPPart));
    if (st->nparts) memcpy(st->parts, parts.bytes, st->nparts * sizeof(MSBDAPPart));
    for (DMAPRouteRec *r in route) {
        if (st->nroute >= MSBD_AP_MAX_ROUTE) break;
        MSBDAPRouteDev *o = &st->route[st->nroute++];
        o->type = r.type; DMAPCopyStr(o->uid, sizeof o->uid, r.uid); o->modes = r.modes; o->current = r.current;
    }
    st->noiseError = err;
}

// ---- the menu's own rows ----
// The headphones' name, a Mac menu's heading (semibold, not a tap target); its level at the right when there is no strip.
@interface DMAPHeaderRow : DMRow
@end
@implementation DMAPHeaderRow
- (instancetype)initWithTitle:(NSString *)title level:(NSString *)level {
    self = [super initWithTitle:title enabled:NO handler:nil];
    if (!self) return nil;
    self.label.font = [UIFont systemFontOfSize:DMMenuTextPt() weight:UIFontWeightSemibold];
    if (level.length) self.hint = level;
    return self;
}
- (void)refresh { [super refresh]; self.label.textColor = [UIColor labelColor]; self.hintLabel.textColor = [UIColor secondaryLabelColor]; }
- (NSString *)accessibilityValue { return self.hint; }
- (UIAccessibilityTraits)accessibilityTraits { return UIAccessibilityTraitHeader; }
@end
// "Noise Control": a small grey section heading, as the Wi-Fi menu's.
@interface DMAPSectionRow : DMRow
@end
@implementation DMAPSectionRow
- (instancetype)initWithTitle:(NSString *)title {
    self = [super initWithTitle:title enabled:NO handler:nil];
    if (self) self.label.font = [UIFont systemFontOfSize:MSBDMenuTextScaled(DMMenuSize(), 12.0) weight:UIFontWeightSemibold];
    return self;
}
- (CGFloat)dmRowHeight { return MSBDMenuRowScaled(DMMenuSize(), kAPSectionRowH); }
- (void)refresh { [super refresh]; self.label.textColor = [UIColor secondaryLabelColor]; }
- (UIAccessibilityTraits)accessibilityTraits { return UIAccessibilityTraitHeader; }
@end
// A grey line that only says something ("Not Connected", "Couldn't Change Noise Control").
@interface DMAPInfoRow : DMRow
@end
@implementation DMAPInfoRow
- (instancetype)initWithText:(NSString *)text { return [super initWithTitle:text enabled:NO handler:nil]; }
- (void)refresh { [super refresh]; self.label.textColor = [UIColor secondaryLabelColor]; }
@end
// The battery strip: a cell per part BatteryCenter reports now (Left and Right merged, or apart, then the Case), each its glyph (or its word
// where this iPadOS has no such symbol), its level and a bolt while charging. One element for VoiceOver, with the levels as its value.
@interface DMAPStripRow : UIView
@property (nonatomic, copy) NSString *axText;
@end
@implementation DMAPStripRow
- (instancetype)initWithCells:(const MSBDAPCell *)cells count:(int)n {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    CGFloat pt = DMMenuTextPt();
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:pt weight:UIImageSymbolWeightRegular];
    for (int i = 0; i < n && i < 4; i++) {
        const char *word = "";
        const char *const *chain = MSBDAirPodsGlyphs(cells[i].kind, &word);
        UIImage *g = nil;
        for (int j = 0; chain && chain[j] && !g; j++) g = [UIImage systemImageNamed:@(chain[j]) withConfiguration:cfg];
        UIView *glyph;
        if (g) { UIImageView *iv = [[UIImageView alloc] initWithImage:[g imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]]; iv.tintColor = [UIColor labelColor]; glyph = iv; }
        else { UILabel *w = [UILabel new]; w.text = @(word); w.font = [UIFont systemFontOfSize:MSBDMenuTextScaled(DMMenuSize(), 12.0) weight:UIFontWeightSemibold]; w.textColor = [UIColor secondaryLabelColor]; glyph = w; }
        glyph.tag = 100 + i;
        [self addSubview:glyph];
        UILabel *lv = [UILabel new];
        char pc[8]; MSBDAirPodsPercentText(cells[i].percent, pc, sizeof pc);
        lv.text = @(pc); lv.font = [UIFont monospacedDigitSystemFontOfSize:pt weight:UIFontWeightRegular]; lv.textColor = [UIColor labelColor];
        lv.tag = 200 + i;
        [self addSubview:lv];
        if (cells[i].charging) {
            const char *bw = "";
            const char *const *bc = MSBDAirPodsGlyphs(MSBD_AP_GLYPH_CHARGING, &bw);
            UIImage *bolt = bc && bc[0] ? [UIImage systemImageNamed:@(bc[0]) withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:pt - 2.0 weight:UIImageSymbolWeightRegular]] : nil;
            UIView *b;
            if (bolt) { UIImageView *iv = [[UIImageView alloc] initWithImage:[bolt imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]]; iv.tintColor = [UIColor secondaryLabelColor]; b = iv; }
            else { UILabel *w = [UILabel new]; w.text = @(bw); w.font = [UIFont systemFontOfSize:MSBDMenuTextScaled(DMMenuSize(), 11.0)]; w.textColor = [UIColor secondaryLabelColor]; b = w; }
            b.tag = 300 + i;
            [self addSubview:b];
        }
    }
    char ax[256]; MSBDAirPodsCellsAXText(cells, n, ax, sizeof ax);
    _axText = @(ax);
    for (UIView *v in self.subviews) { v.isAccessibilityElement = NO; v.userInteractionEnabled = NO; }
    return self;
}
- (CGFloat)dmRowHeight { return MSBDMenuRowScaled(DMMenuSize(), kAPStripRowH); }
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat x = 16.0, h = self.bounds.size.height;
    for (int i = 0; i < 4; i++) {
        UIView *g = [self viewWithTag:100 + i], *l = [self viewWithTag:200 + i], *b = [self viewWithTag:300 + i];
        if (!g || !l) break;
        CGSize gs = [g sizeThatFits:CGSizeMake(60, h)], ls = [l sizeThatFits:CGSizeMake(80, h)];
        g.frame = CGRectMake(x, round((h - gs.height) / 2.0), ceil(gs.width), ceil(gs.height)); x += ceil(gs.width) + 5.0;
        l.frame = CGRectMake(x, 0, ceil(ls.width), h); x += ceil(ls.width);
        if (b) { CGSize bs = [b sizeThatFits:CGSizeMake(40, h)]; x += 2.0; b.frame = CGRectMake(x, round((h - bs.height) / 2.0), ceil(bs.width), ceil(bs.height)); x += ceil(bs.width); }
        x += 18.0;
    }
}
- (BOOL)isAccessibilityElement { return YES; }
- (NSString *)accessibilityLabel { return @"Battery"; }
- (NSString *)accessibilityValue { return self.axText; }
- (UIAccessibilityTraits)accessibilityTraits { return UIAccessibilityTraitStaticText; }
@end

// ---- the menu ----
static void DMAPTapMode(NSString *uid, int mode);
static void DMAPConnect(DMAPHeadsetRec *h, BOOL connect);
static NSString *DMAPRowsLog(const MSBDAPState *st, const MSBDAPRow *r, int n) {   // (what a menu shows, names hashed)
    NSMutableArray *o = [NSMutableArray array];
    for (int i = 0; i < n; i++) {
        switch (r[i].kind) {
            case kMSBDAPRowHeading: [o addObject:[NSString stringWithFormat:@"H %@%@%s", strcmp(r[i].text, MSBD_AP_HEADING) ? DMWiFiTag(@(r[i].text)) : @(r[i].text), r[i].value[0] ? @" = " : @"", r[i].value]]; break;
            case kMSBDAPRowStrip: {
                NSMutableString *s = [NSMutableString stringWithString:@"S"];
                for (int c = 0; c < r[i].ncells; c++) [s appendFormat:@" [%d %d%%%@]", r[i].cells[c].kind, r[i].cells[c].percent, r[i].cells[c].charging ? @" +" : @""];
                [o addObject:s]; break;
            }
            case kMSBDAPRowSeparator: [o addObject:@"--"]; break;
            case kMSBDAPRowMode: [o addObject:[NSString stringWithFormat:@"M%@ %s", r[i].checked ? @"*" : @"", r[i].text]]; break;
            default: [o addObject:[NSString stringWithFormat:@"%d %s", r[i].kind, r[i].text]]; break;
        }
    }
    (void)st;
    return [o componentsJoinedByString:@" | "];
}
// The rows from the open menu's caches (or, with no menu open, from a read now: the probe, VoiceOver).
static NSArray *DMAPMenuItems(uint64_t *sigOut, NSString **logOut) {
    MSBDAPState st; MSBDAPBlock blocks[MSBD_AP_MAX_HEADSETS]; MSBDAPRow rows[MSBD_AP_MAX_ROWS];
    NSArray<DMAPHeadsetRec *> *heads = [gAPMenuHeadsets copy] ?: @[];
    NSArray<DMAPRouteRec *> *route = gAPRoute ?: @[];
    DMAPFillState(&st, heads, route, gAPNoiseError);
    int nb = MSBDAirPodsBlocks(&st, blocks, MSBD_AP_MAX_HEADSETS), nr = MSBDAirPodsMenuRows(&st, blocks, nb, rows, MSBD_AP_MAX_ROWS);
    NSMutableArray *items = [NSMutableArray array];
    for (int i = 0; i < nr; i++) {
        const MSBDAPRow *r = &rows[i];
        const MSBDAPBlock *b = r->block >= 0 && r->block < nb ? &blocks[r->block] : NULL;
        DMAPHeadsetRec *head = b && b->headset >= 0 && b->headset < (int)heads.count ? heads[b->headset] : nil;   // (held by its rows: Disconnect acts after the menu is gone)
        NSString *uid = b && b->route >= 0 && b->route < (int)route.count ? route[b->route].uid : nil;
        switch (r->kind) {
            case kMSBDAPRowHeading: [items addObject:[[DMAPHeaderRow alloc] initWithTitle:@(r->text) level:@(r->value)]]; break;
            case kMSBDAPRowStrip: [items addObject:[[DMAPStripRow alloc] initWithCells:r->cells count:r->ncells]]; break;
            case kMSBDAPRowSection: [items addObject:[[DMAPSectionRow alloc] initWithTitle:@(r->text)]]; break;
            case kMSBDAPRowInfo: [items addObject:[[DMAPInfoRow alloc] initWithText:@(r->text)]]; break;
            case kMSBDAPRowMode: {   // (acts in place: the menu stays open, the tick moves at once)
                int mode = r->mode;
                DMRow *row = [[DMRow alloc] initWithTitle:@(r->text) enabled:uid != nil handler:^{ DMAPTapMode(uid, mode); }];
                row.checked = r->checked;
                [items addObject:row];
                break;
            }
            case kMSBDAPRowConnect: { [items addObject:[[DMRow alloc] initWithTitle:@(r->text) enabled:head != nil handler:^{ DMAPConnect(head, YES); }]]; break; }   // (in place)
            case kMSBDAPRowDisconnect: { [items addObject:[[DMRow alloc] initWithTitle:@(r->text) enabled:head != nil handler:DMCloseThen(^{ DMAPConnect(head, NO); })]]; break; }
            case kMSBDAPRowSettings: { [items addObject:[[DMRow alloc] initWithTitle:@(r->text) enabled:YES handler:DMCloseThen(^{ DMOpenURL(@"prefs:root=Bluetooth", @"bluetooth settings (airpods menu)"); })]]; break; }
            default: [items addObject:[NSNull null]]; break;
        }
    }
    if (sigOut) *sigOut = MSBDAirPodsSignature(rows, nr);
    if (logOut) *logOut = DMAPRowsLog(&st, rows, nr);
    return items;
}
// The open menu is rebuilt in place when what it shows changes (at most once per 0.3 s), at the same height limit, its right edge kept in a
// right-to-left language, still the "Headphones menu" group.
static void DMAPRebuildOpenMenu(void) {
    UIView *old = gAPPanel;
    if (!gAPMenuOpen || !old.window || !old.superview) return;
    uint64_t sig = 0; NSString *log = nil;
    NSArray *items = DMAPMenuItems(&sig, &log);
    if (sig == gAPMenuSig) return;
    gAPMenuSig = sig;
    UIView *panel = DMMakePanelLike(items, old);
    CGRect f = panel.frame; f.origin = old.frame.origin;
    if ([UIApplication sharedApplication].userInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft) f.origin.x = CGRectGetMaxX(old.frame) - f.size.width;
    panel.frame = f;
    panel.accessibilityLabel = old.accessibilityLabel; panel.accessibilityContainerType = old.accessibilityContainerType;
    [old.superview insertSubview:panel aboveSubview:old];
    [old removeFromSuperview];
    gAPPanel = panel;
#if DEBUG
    DMLog([NSString stringWithFormat:@"[podmenu] menu updated: %@", log]);
#endif
}
static BOOL gAPRebuildPending = NO;
static void DMAPMenuChanged(void) {
    if (!gAPMenuOpen || gAPRebuildPending) return;
    gAPRebuildPending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ gAPRebuildPending = NO; DMAPRebuildOpenMenu(); });
}
__attribute__((noinline)) static void DMAirPodsMenuGone(NSString *why) {   // (every way a menu closes: DMRemoveOverlayNow, DMCloseOverlay)
    if (!gAPMenuOpen) return;
    gAPMenuOpen = NO; gAPPanel = nil; gAPNoiseError = NO; gAPMenuHeadsets = nil; gAPRoute = nil;
    DMLog([NSString stringWithFormat:@"[podmenu] menu %@", why]);
}
__attribute__((noinline)) static void DMOpenAirPodsMenu(UIButton *btn) {
    if (DMTitleTapWithMenuOpen(btn)) return;
    DM_FEATURE_MARK("airpods-menu");
    DMAPCheck();
    gAPMenuHeadsets = nil; gAPNoiseError = NO;
    DMAPMergeHeadsets(DMAPReadHeadsets());
    gAPRoute = DMAPReadRoute();
    uint64_t sig = 0; NSString *log = nil;
    NSArray *items = DMAPMenuItems(&sig, &log);
    DMPresentMenu(btn, kAPMenuLabelKey, kAPMenuPillKey, items);
    UIView *panel = gOverlay.subviews.lastObject;
    if (!gOverlay || !panel) { gAPMenuHeadsets = nil; gAPRoute = nil; return; }   // (not opened: the Lock Screen, Guided Access)
    gAPMenuOpen = YES; gAPPanel = panel; gAPMenuSig = sig;
    DMLog([NSString stringWithFormat:@"[podmenu] menu opened (headphones %lu, route devices %lu)", (unsigned long)gAPMenuHeadsets.count, (unsigned long)gAPRoute.count]);
#if DEBUG
    DMLog([NSString stringWithFormat:@"[podmenu] menu opened: %@", log]);
#endif
}
// Our own headphones icon's data (1.8.8.2): how many connected headphones there are (MSBDAirPodsCountsAsHeadphones), read once when the bars
// first lay out with the AirPods Menu on and again at each of Bluetooth's events (and the made-up headphones' changes); the bars are laid out
// again when it changes. No timer, no read in a layout pass. When the count rises from none, our icon waits MSBD_AP_OWN_SETTLE seconds (common/
// AirPodsMenu.h MSBDAirPodsOwnIcon: iPadOS's own item first, where it draws one): one layout of the bars after it, no repeating timer.
static BOOL gAPWatchStarted = NO;
static int gAPHeadphonesOn = 0;
static CFTimeInterval gAPHeadphonesSince = 0;   // (when the count last rose from none)
static void DMAPOwnRefresh(void) {   // (main thread)
    if (!gAPWatchStarted) return;
    int n = 0;
    for (DMAPHeadsetRec *h in DMAPReadHeadsets()) if (h.connected && h.phones) n++;
    if (n == gAPHeadphonesOn) return;
    if (!gAPHeadphonesOn) {
        gAPHeadphonesSince = CACurrentMediaTime();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((MSBD_AP_OWN_SETTLE + 0.1) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ for (UIView *fg in gCopies.allObjects) [fg setNeedsLayout]; });
    }
    gAPHeadphonesOn = n;
    DMLog([NSString stringWithFormat:@"[podmenu] headphones connected: %d (our own icon where iPadOS shows no item for them)", n]);
    for (UIView *fg in gCopies.allObjects) [fg setNeedsLayout];
}
// What changed while it is open: Bluetooth's notifications (the headphones read again; a set gone stays listed as Not Connected), the route's
// (and the accessory settings', a mode changed elsewhere: the route read again), BatteryCenter's list (already stored).
static void DMAPSourceSaid(BOOL headsets, BOOL route) {
    if (headsets) DMAPOwnRefresh();   // (our own icon follows the headphones, menu open or not)
    if (!gAPMenuOpen) return;
    if (headsets) DMAPMergeHeadsets(DMAPReadHeadsets());
    if (route) gAPRoute = DMAPReadRoute();
    DMAPMenuChanged();
}

// ---- what the rows do ----
static void DMAPModeDone(NSError *err) {   // (main queue: any error is a failure -- the tick goes back to the real mode, the line shows)
    if (gAPModesPending) gAPModesPending--;
    if (err) { gAPNoiseError = YES; DMLog([NSString stringWithFormat:@"[podmenu] noise control not changed (%@ %ld)", err.domain, (long)err.code]); }
    if (!gAPMenuOpen) return;
    gAPRoute = DMAPReadRoute();
    DMAPMenuChanged();
}
static void DMAPTapMode(NSString *uid, int mode) {
    if (!uid || mode < 0 || mode >= kMSBDAPModes) return;
    gAPNoiseError = NO;   // (a new change: the line was the last one's)
    for (DMAPRouteRec *r in gAPRoute) if ([r.uid isEqualToString:uid]) r.current = mode;   // (the tick moves at once)
    dispatch_async(dispatch_get_main_queue(), ^{ DMAPRebuildOpenMenu(); });   // (after the row's own touch is done)
#if DEBUG
    if (gAPFake) {
        BOOL fail = gAPFakeErr; gAPFakeErr = NO;
        if (!fail) for (DMAPRouteRec *r in gAPFakeRoute) if ([r.uid isEqualToString:uid]) r.current = mode;
        DMLog([NSString stringWithFormat:@"[podmenu] test device: noise control %s%@: nothing sent", kMSBDAPModeStrings[mode], fail ? @" (made to fail)" : @""]);
        gAPModesPending++;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMAPModeDone(fail ? [NSError errorWithDomain:@"test" code:-11910 userInfo:nil] : nil); });
        return;
    }
#endif
    @try {
        SEL set = NSSelectorFromString(@"setListeningMode:outputDeviceUID:queue:completion:");
        id ep = DMAPEndpoint();
        if (!DMAPTypes(ep, set, "v48@0:8@16@24@32@?40")) { DMLog(@"[podmenu] the endpoint has other types here: noise control not changed"); DMAPModeDone([NSError errorWithDomain:@"airpods menu" code:1 userInfo:nil]); return; }
        gAPModesPending++;
        DMLog([NSString stringWithFormat:@"[podmenu] noise control: %s asked", kMSBDAPModeStrings[mode]]);
        ((void (*)(id, SEL, id, id, id, id))objc_msgSend)(ep, set, @(kMSBDAPModeStrings[mode]), uid, dispatch_get_main_queue(), ^(NSError *err) { DMAPModeDone(err); });
    } @catch (NSException *e) { DMAPPartFailed(kDMAPPartNoise, e); DMAPModeDone([NSError errorWithDomain:@"airpods menu" code:2 userInfo:nil]); }
}
static void DMAPConnect(DMAPHeadsetRec *h, BOOL connect) {
    if (!h) return;
#if DEBUG
    if (h.fake) {
        h.connected = connect;
        DMLog([NSString stringWithFormat:@"[podmenu] test device %@ %@: nothing sent", DMWiFiTag(h.name), connect ? @"connected" : @"disconnected"]);
        DMAPFakeShowItem();   // (iPadOS's item comes or goes with it, as for real headphones)
        DMAPSourceSaid(YES, YES);
        return;
    }
#endif
    SEL sel = NSSelectorFromString(connect ? @"connect" : @"disconnect");
    if (!h.device || !DMAPTypes(h.device, sel, "v16@0:8")) return;
    DMLog([NSString stringWithFormat:@"[podmenu] headphones %@: %@", DMWiFiTag(h.name), connect ? @"connect" : @"disconnect"]);
    @try { ((void (*)(id, SEL))objc_msgSend)(h.device, sel); } @catch (NSException *e) { DMAPPartFailed(kDMAPPartHeadset, e); }
}

// ---- Bluetooth's events (once: the first time the bars lay out with the AirPods Menu on, on the next main-queue turn, or with the other
// sources; 1.8.8.2: our own icon follows the headphones from the start, not only once a button was placed) ----
static void DMAPWatchStart(void) {
    if (gAPWatchStarted) return;
    gAPWatchStarted = YES;
    DMAPCheck();
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    if (gAPPart[kDMAPPartHeadset]) {
        // (and, for our own icon's count, BluetoothManager's own "the list may have changed" events: Bluetooth turned off or on, and the manager
        //  attached to Bluetooth, which can come after the first count at a respring -- the review of 1.8.8.2)
        for (NSString *n in @[@"BluetoothDeviceBatteryChangedNotification", @"BluetoothDeviceConnectSuccessNotification", @"BluetoothDeviceDisconnectSuccessNotification",
                              @"BluetoothConnectionStatusChangedNotification", @"BluetoothPowerChangedNotification", @"BluetoothAvailabilityChangedNotification"])
            [nc addObserverForName:n object:nil queue:nil usingBlock:^(NSNotification *note) { dispatch_async(dispatch_get_main_queue(), ^{ DMAPSourceSaid(YES, NO); }); }];
        [nc addObserverForName:@"BluetoothAccessorySettingsChanged" object:nil queue:nil usingBlock:^(NSNotification *note) { dispatch_async(dispatch_get_main_queue(), ^{ DMAPSourceSaid(YES, YES); }); }];
    }
    DMAPOwnRefresh();
}
// ---- the sources that keep an open menu current (once, the first time a button is placed; each returns at once unless the menu is open) ----
static void DMAPStartSources(void) {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    DMAPWatchStart();   // (Bluetooth's events, if the bars have not started them yet)
    id route = DMAPSystemRoute();
    if (gAPRouteNote && route) [nc addObserverForName:gAPRouteNote object:route queue:nil usingBlock:^(NSNotification *note) { dispatch_async(dispatch_get_main_queue(), ^{ DMAPSourceSaid(NO, YES); }); }];
    DMAPPartsStart();
    DMLog([NSString stringWithFormat:@"[podmenu] sources: Bluetooth %d, route %d, battery records %d; the button follows iPadOS's data updates: %@", gAPPart[kDMAPPartHeadset],
        gAPRouteNote && route, gAPBatteryWatch != nil, (gSBItemHooks & 1) ? @"yes" : @"no (only our own layouts)"]);
}

// ---- the button over iPadOS's AirPods item in a bar copy ----
// The Bluetooth item's shown views (its glyph and its headset battery: two display items, SystemStatusUI's on 17/18, UIKit's on 15/16, read on all
// four iPads), whether its battery display item shows (its -identifier is the item class's +batteryDisplayIdentifier), the other shown views of
// its region (its neighbours) and the battery item's views. NO: no such item, or the class does not answer (no button).
static Class DMAPItemClass(void) { return objc_getClass(DMSBUseSTUI() ? "STUIStatusBarBluetoothItem" : "_UIStatusBarBluetoothItem"); }
static BOOL DMAPItemViews(UIView *fg, NSMutableArray<UIView *> *views, NSMutableArray<UIView *> *others, NSMutableArray<UIView *> *battViews, BOOL *battShown) {
    static SEL sRegions, sItems, sItem, sView, sIdent, sBattID;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sRegions = NSSelectorFromString(@"regions"); sItems = NSSelectorFromString(@"displayItems"); sItem = NSSelectorFromString(@"item");
        sView = NSSelectorFromString(@"view"); sIdent = NSSelectorFromString(@"identifier"); sBattID = NSSelectorFromString(@"batteryDisplayIdentifier");
    });
    *battShown = NO;
    Class ic = DMAPItemClass(), bc = DMBattItemClass();
    if (!ic || !DMAPTypes((id)ic, sBattID, "@16@0:8")) return NO;
    id battID = ((id (*)(id, SEL))objc_msgSend)((id)ic, sBattID);
    UIView *bar = fg.superview;
    id regions = [bar respondsToSelector:sRegions] ? ((id (*)(id, SEL))objc_msgSend)(bar, sRegions) : nil;
    if (![regions isKindOfClass:[NSDictionary class]]) return NO;
    for (id r in [(NSDictionary *)regions allValues]) {
        id list = [r respondsToSelector:sItems] ? ((id (*)(id, SEL))objc_msgSend)(r, sItems) : nil;
        if (![list conformsToProtocol:@protocol(NSFastEnumeration)]) continue;
        BOOL mine = NO;
        NSMutableArray<UIView *> *rest = [NSMutableArray array];
        for (id di in list) {
            id it = [di respondsToSelector:sItem] ? ((id (*)(id, SEL))objc_msgSend)(di, sItem) : nil;
            id v = [di respondsToSelector:sView] ? ((id (*)(id, SEL))objc_msgSend)(di, sView) : nil;
            BOOL shown = [v isKindOfClass:[UIView class]] && DMBattViewShown(v, fg);
            if (bc && [it isKindOfClass:bc] && shown) [battViews addObject:v];
            if (ic && [it isKindOfClass:ic]) {
                mine = YES;
                if (!shown) continue;
                [views addObject:v];
                id ident = DMAPObj(di, sIdent);
                if (ident && battID && (ident == battID || [ident isEqual:battID])) *battShown = YES;
                continue;
            }
            if (shown) [rest addObject:v];
        }
        if (mine) [others addObjectsFromArray:rest];
    }
    return YES;
}
// The Bluetooth state in the bar's own data, as it draws the item (its merged data: -currentAggregatedData's -bluetoothEntry's -state; 2 is
// connected headphones), each call asked with its type first. *read NO: not readable here.
static long long DMAPBluetoothState(UIView *fg, BOOL *read) {
    static SEL sData, sEntry, sState;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ sData = NSSelectorFromString(@"currentAggregatedData"); sEntry = NSSelectorFromString(@"bluetoothEntry"); sState = NSSelectorFromString(@"state"); });
    id e = DMAPObj(DMAPObj(fg.superview, sData), sEntry);
    *read = DMAPTypes(e, sState, "q16@0:8") || DMAPTypes(e, sState, "Q16@0:8");
    return *read ? ((long long (*)(id, SEL))objc_msgSend)(e, sState) : -1;
}
// iPadOS's views under our button are not read a second time by VoiceOver: their own setting kept and given back when the button goes -- in a
// set of its own, never the battery's (BatteryMenu.h DMBattCoverAX gives back every view not in the list it is called with).
static void DMAPCoverAX(UIView *fg, NSArray<UIView *> *views, BOOL cover) {
    NSHashTable<UIView *> *was = objc_getAssociatedObject(fg, kAPCoveredKey);
    for (UIView *v in was.allObjects) {
        if (cover && [views containsObject:v]) continue;
        NSNumber *own = objc_getAssociatedObject(v, kAPAXWasKey);
        if (own) v.isAccessibilityElement = own.boolValue;
        objc_setAssociatedObject(v, kAPAXWasKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [was removeObject:v];
    }
    if (!cover) return;
    if (!was) { was = [NSHashTable weakObjectsHashTable]; objc_setAssociatedObject(fg, kAPCoveredKey, was, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    for (UIView *v in views) {
        if ([was containsObject:v]) continue;
        objc_setAssociatedObject(v, kAPAXWasKey, @(v.isAccessibilityElement), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        v.isAccessibilityElement = NO;
        [was addObject:v];
    }
}
static CGRect DMAPUnion(UIView *fg, NSArray<UIView *> *views) {   // (the views' union in the copy: the status icons' shift included)
    CGRect u = CGRectNull;
    for (UIView *v in views) u = CGRectUnion(u, [v convertRect:v.bounds toView:fg]);
    return u;
}
static NSString *DMAPAXValue(void) {   // (the button's value, read when VoiceOver asks: the headphones now)
    DMAPCheck();
    MSBDAPState st; MSBDAPBlock blocks[MSBD_AP_MAX_HEADSETS];
    DMAPFillState(&st, gAPMenuOpen ? [gAPMenuHeadsets copy] : DMAPReadHeadsets(), @[], NO);
    st.noisePart = 0;
    int nb = MSBDAirPodsBlocks(&st, blocks, MSBD_AP_MAX_HEADSETS);
    char ax[512]; MSBDAirPodsAXText(&st, blocks, nb, ax, sizeof ax);
    return @(ax);
}
static void DMAPHideButton(UIView *fg) {
    UIButton *btn = objc_getAssociatedObject(fg, kAirPodsButtonKey);
    btn.hidden = YES;
    DMAPCoverAX(fg, @[], NO);
    if ([objc_getAssociatedObject(fg, kAPShownKey) boolValue]) { objc_setAssociatedObject(fg, kAPShownKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); DMLog(@"[podmenu] button hidden"); }
}
// The AirPods button of a copy, made the first time: over iPadOS's item, or over our own icon (1.8.8.2).
static UIButton *DMAPButton(UIView *fg) {
    UIButton *btn = objc_getAssociatedObject(fg, kAirPodsButtonKey);
    if (btn) return btn;
    DMAXButton *bb = [DMAXButton buttonWithType:UIButtonTypeCustom];
    bb.pointerInteractionEnabled = DMButtonPointerEffects();   // (iPadOS's highlight and pull only with its own pointer, StatusBar.x)
    bb.accessibilityLabel = @"Headphones";
    bb.axValue = ^NSString *{ return DMAPAXValue(); };
    bb.accessibilityHint = @"Opens the headphones menu.";
    btn = bb;
    __weak UIButton *weakBtn = btn;
    [btn addAction:[UIAction actionWithHandler:^(__kindof UIAction *x) { if (weakBtn) DMOpenAirPodsMenu(weakBtn); }] forControlEvents:UIControlEventTouchUpInside];
    [fg addSubview:btn];
    objc_setAssociatedObject(fg, kAirPodsButtonKey, btn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return btn;
}
// ---- our own headphones icon where iPadOS shows no item (1.8.8.2; common/AirPodsMenu.h MSBDAirPodsOwnIcon) ----
// Per copy: what iPadOS's Bluetooth item showed at this layout (the number of its shown views; nil: not readable, or the switch off), and
// whether our own icon holds the AirPods button now.
static const void *kAPItemSeenKey = &kAPItemSeenKey, *kAPOwnKey = &kAPOwnKey;
static void DMAPItemSeen(UIView *fg, NSNumber *shown) { objc_setAssociatedObject(fg, kAPItemSeenKey, shown, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static BOOL DMAPOwnHolds(UIView *fg) { return [objc_getAssociatedObject(fg, kAPOwnKey) boolValue]; }
// Our icon goes; the button with it unless iPadOS's item has it now (hideButton NO: DMAirPodsLayoutButton places it over that item).
static void DMAPOwnLetGo(UIView *fg, BOOL hideButton) {
    UIView *icon = objc_getAssociatedObject(fg, kAirPodsIconKey);
    if (icon && !icon.hidden) icon.hidden = YES;
    if (!DMAPOwnHolds(fg)) return;
    objc_setAssociatedObject(fg, kAPOwnKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (hideButton) DMAPHideButton(fg);
    DMLog([NSString stringWithFormat:@"[podmenu] our own headphones icon hidden (%@)", hideButton ? @"no headphones, or iPadOS's item shows, or the switch is off" : @"iPadOS's item for them shows now: the button goes over it"]);
}
static CGRect DMImageInkRect(UIImage *img);   // (StatusBar.x: the drawn part of a picture, in points)
// The headphones symbol at the Wi-Fi fan's height on that bar, its ink as tall as the fan's, as the mute icon's picture is made (StatusBar.x
// DMMuteGlyph): one picture per height. nil: no such symbol here (then no icon).
static UIImage *DMAPOwnGlyph(CGFloat iconH) {
    static NSMutableDictionary<NSNumber *, UIImage *> *glyphs;
    if (!glyphs) glyphs = [NSMutableDictionary dictionary];
    UIImage *glyph = glyphs[@(iconH)];
    if (glyph) return glyph;
    UIImage *(^symbol)(CGFloat) = ^UIImage *(CGFloat pt) {
        return [UIImage systemImageNamed:@"headphones" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:pt weight:UIImageSymbolWeightSemibold]];
    };
    const CGFloat probe = 40.0, inkH = iconH - 1.0;
    CGRect big = DMImageInkRect(symbol(probe));
    if (CGRectIsNull(big) || big.size.height < 1.0 || inkH < 1.0) return nil;
    UIImage *g = symbol(probe * inkH / big.size.height);
    CGRect ink = DMImageInkRect(g);   // (again at the size drawn: small sizes round)
    if (!g || CGRectIsNull(ink)) return nil;
    CGSize size = CGSizeMake(ceil(ink.size.width) + 2.0, iconH);
    UIImage *out = [[[UIGraphicsImageRenderer alloc] initWithSize:size] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [g drawAtPoint:CGPointMake((size.width - ink.size.width) / 2.0 - ink.origin.x, (size.height - ink.size.height) / 2.0 - ink.origin.y)];
    }];
    glyph = [out imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    glyphs[@(iconH)] = glyph;
    return glyph;
}
// Places the AirPods button over iPadOS's item in a status bar copy (AirPods Menu on and the item showing headphones, with or without their
// level: MSBDAirPodsItemIsHeadphones; hidden otherwise, iPadOS's item then as before). `left`: where the status icons start (leading
// coordinates); the full bar's height, as our other buttons; 4 pt (x k) past the item at each side, cut at the middle of the gaps to its
// neighbours and where the battery's own button starts.
__attribute__((noinline)) static void DMAirPodsLayoutButton(UIView *fg, CGFloat left, CGFloat k) {
    NSMutableArray<UIView *> *views = [NSMutableArray array], *others = [NSMutableArray array], *battViews = [NSMutableArray array];
    BOOL battShown = NO, stateRead = NO;
    if (!gAirPodsMenuOn || !(left < CGFLOAT_MAX) || !DMAPItemViews(fg, views, others, battViews, &battShown)) { DMAPItemSeen(fg, nil); DMAPHideButton(fg); return; }
    DMAPItemSeen(fg, @(views.count));   // (for our own icon, DMAirPodsLayoutOwnIcon: iPadOS's item read here, and how many of its views show)
    long long state = views.count && !battShown ? DMAPBluetoothState(fg, &stateRead) : MSBD_AP_BT_HEADPHONES;   // (the data only for the glyph alone)
    if (!MSBDAirPodsItemIsHeadphones((int)views.count, battShown, stateRead, state)) { if (!views.count && DMAPOwnHolds(fg)) return; DMAPHideButton(fg); return; }
    BOOL rtl = DMBarRTL(fg);
    CGRect u = DMAPUnion(fg, views);
    double lead = DMBarLead(fg, rtl, u), trail = DMBarTrail(fg, rtl, u), mid = (lead + trail) / 2.0;
    MSBDAPSide prev = { 0, 0, 0 }, next = { 0, 0, 0 }, batt = { 0, 0, 0 };
    for (UIView *v in others) {
        CGRect r = [v convertRect:v.bounds toView:fg];
        double a = DMBarLead(fg, rtl, r), b = DMBarTrail(fg, rtl, r);
        if ((a + b) / 2.0 < mid) { if (!prev.has || b > prev.trail) { prev.has = 1; prev.lead = a; prev.trail = b; } }
        else if (!next.has || a < next.lead) { next.has = 1; next.lead = a; next.trail = b; }
    }
    if (gBattMenuOn && battViews.count) {   // (the battery's button, as DMBattLayoutButton places it: its views, 4 pt x k, the same floor)
        CGRect br = DMAPUnion(fg, battViews);
        double ba = 0, bb = 0;
        if (MSBDBattButtonSpan(DMBarLead(fg, rtl, br), DMBarTrail(fg, rtl, br), 4.0 * k, left - 2.0 * k, &ba, &bb)) { batt.has = 1; batt.lead = ba; batt.trail = bb; }
    }
    double a = 0, b = 0;
    if (!MSBDAirPodsButtonSpan(lead, trail, 4.0 * k, left - 2.0 * k, prev, next, batt, &a, &b)) { DMAPHideButton(fg); return; }
    if (DMAPOwnHolds(fg)) DMAPOwnLetGo(fg, NO);   // (iPadOS's item shows now: never two icons)
    UIButton *btn = DMAPButton(fg);
    btn.frame = DMBarRect(fg, rtl, CGRectMake(a, 0, b - a, DMBarCopyHeight(fg)));
    btn.hidden = NO;
    [fg bringSubviewToFront:btn];
    DMAPCoverAX(fg, views, YES);
    if (![objc_getAssociatedObject(fg, kAPShownKey) boolValue]) {
        objc_setAssociatedObject(fg, kAPShownKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        DMLog([NSString stringWithFormat:@"[podmenu] button over iPadOS's AirPods item: %.1f..%.1f (item %.1f..%.1f, %@, battery button %@)", a, b, lead, trail,
            battShown ? @"the glyph and their level" : stateRead ? @"the glyph alone" : @"the glyph alone, the state not readable",
            batt.has ? [NSString stringWithFormat:@"%.1f..%.1f", batt.lead, batt.trail] : @"none"]);
    }
    if (!gAPSourcesStarted) {   // (the first placement: the type check, the sources and BatteryCenter's observer, outside the layout pass)
        gAPSourcesStarted = YES;
        dispatch_async(dispatch_get_main_queue(), ^{ DMAPCheck(); DMAPStartSources(); });
    }
}
// Our own headphones icon (1.8.8.2): where the status icons start (`left`, leading coordinates), when the AirPods Menu is on, this copy's
// layout just read iPadOS's Bluetooth item and found none of its views shown, and headphones are connected (MSBDAirPodsOwnIcon): the
// headphones symbol at the Wi-Fi fan's height, 8 pt (x k) before the status icons, the AirPods button over it as wide as our other icons'
// (6 pt x k each side), the full bar's height. Returns the new left edge (our Wi-Fi, VPN, mute and SSH icons follow it), unchanged without it.
// Called right after DMAirPodsLayoutButton and the battery's button, in the same layout pass; Bluetooth's events are first watched from here
// (on the next main-queue turn, never in the layout pass). Never on SystemStatusUI's bar (17/18: iPadOS's own glyph there), where nothing of it
// starts: Bluetooth's events are watched there, as in 1.8.8.1.1, only once a button is placed over iPadOS's item (DMAPStartSources).
__attribute__((noinline)) static CGFloat DMAirPodsLayoutOwnIcon(UIView *fg, CGFloat left, CGFloat midY, CGFloat k) {
    BOOL drawsOwn = DMSBUseSTUI();
    if (gAirPodsMenuOn && !drawsOwn && !gAPWatchStarted) {
        static BOOL asked = NO;
        if (!asked) { asked = YES; dispatch_async(dispatch_get_main_queue(), ^{ DMAPWatchStart(); }); }
    }
    NSNumber *seen = objc_getAssociatedObject(fg, kAPItemSeenKey);
    UIImage *g = left < CGFLOAT_MAX && MSBDAirPodsOwnIcon(gAirPodsMenuOn, drawsOwn, seen != nil, seen.intValue, gAPHeadphonesOn, CACurrentMediaTime() - gAPHeadphonesSince)
        ? DMAPOwnGlyph(DMWiFiIconHeight(k)) : nil;
    if (!g) { DMAPOwnLetGo(fg, YES); return left; }
    UIImageView *icon = objc_getAssociatedObject(fg, kAirPodsIconKey);
    if (!icon) {
        icon = [UIImageView new];
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.userInteractionEnabled = NO;
        icon.isAccessibilityElement = NO;   // (the button over it is read: Headphones, their battery, Opens the headphones menu.)
        icon.hidden = YES;
        [fg addSubview:icon];
        objc_setAssociatedObject(fg, kAirPodsIconKey, icon, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (icon.image != g) icon.image = g;
    CGFloat w = ceil(g.size.width), h = ceil(g.size.height);
    left -= 8.0 * k + w;
    BOOL rtl = DMBarRTL(fg);
    icon.frame = DMBarRect(fg, rtl, CGRectMake(left, round(midY - h / 2.0), w, h));
    UIButton *btn = DMAPButton(fg);
    btn.frame = DMBarRect(fg, rtl, CGRectMake(left - 6.0 * k, 0, w + 12.0 * k, DMBarCopyHeight(fg)));
    icon.hidden = btn.hidden = NO;
    [fg bringSubviewToFront:icon]; [fg bringSubviewToFront:btn];
    if (!DMAPOwnHolds(fg)) {
        objc_setAssociatedObject(fg, kAPOwnKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        DMLog([NSString stringWithFormat:@"[podmenu] our own headphones icon: iPadOS shows no item for the connected headphones (%d): icon %.1f..%.1f, button %.1f..%.1f",
            gAPHeadphonesOn, left, left + w, left - 6.0 * k, left + w + 6.0 * k]);
    }
    if (!gAPSourcesStarted) {   // (the first placement: the type check, the sources and BatteryCenter's observer, outside the layout pass)
        gAPSourcesStarted = YES;
        dispatch_async(dispatch_get_main_queue(), ^{ DMAPStartSources(); });
    }
    return left;
}
// The Lock Screen's layout of a copy (StatusBar.x DMLayoutWithoutClock) and copies with no clock: no button, iPadOS's item as it is.
__attribute__((noinline)) static void DMAirPodsLockLayout(UIView *fg) { DMAPHideButton(fg); DMAPItemSeen(fg, nil); DMAPOwnLetGo(fg, YES); }

// ---- the switch (StatusBar.x DMLoadPrefs, a constructor too: everything that touches UIKit or BatteryCenter waits for the next main-queue turn) ----
__attribute__((noinline)) static void DMAirPodsApplyPref(BOOL on) {
    if (on == gAirPodsMenuOn) return;
    gAirPodsMenuOn = on;
    DMLog([NSString stringWithFormat:@"[podmenu] AirPods Menu %@", on ? @"on: iPadOS's AirPods item opens its menu" : @"off: iPadOS's AirPods item as it is"]);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gAirPodsMenuOn) { if (gAPMenuOpen) DMCloseOverlay(); DMAPPartsStop(); }
        else if (gAPSourcesStarted) DMAPPartsStart();   // (back on: BatteryCenter's list again, at once)
        for (UIView *fg in gCopies.allObjects) [fg setNeedsLayout];
    });
}

#if DEBUG
// ---- iPadOS's own Bluetooth item in our bars with no Bluetooth device (sbfakebt_<state>_<percent>, sbfakebt_off; the made-up headphones show
// it through DMAPFakeShowItem). Each bar of ours gets overlay data that holds a Bluetooth entry alone (-setOverlayData:): the bar merges it over
// iPadOS's own data in its own data update, so what shows is iPadOS's Bluetooth item, drawn and placed by iPadOS's code as for real headphones
// (the bar's own overlay is kept and given back by _off). <state> 2 is connected headphones (the headphones glyph); a <percent> of 0 to 100 adds
// their level (the item's battery display item), below 0 leaves it off: the glyph alone, as iPadOS 17/18 show AirPods. The data and entries are
// of the bar's own classes: UIKit's on 15/16, with setters; SystemStatus's on 17/18, which are immutable: the overlay is the data's mutable class
// (STMutableStatusBarData) and each entry gets its values through its setter where it has one, else through its own instance variable, by name
// and exact type. Nothing else is guessed: a value that fits neither changes nothing and is logged. No Bluetooth call, no setting; gone after a
// respring. ----
static NSString *DMAPFakeSet(id o, NSString *key, id obj, long long num, char kind) {   // ('@' an object, 'q' an integer, 'B' a boolean; "set", "ivar" or nil)
    if (!o || !key.length) return nil;
    SEL s = NSSelectorFromString([NSString stringWithFormat:@"set%@%@:", [[key substringToIndex:1] uppercaseString], [key substringFromIndex:1]]);
    Method m = class_getInstanceMethod(object_getClass(o), s);
    char a[32] = "";
    if (m && method_getNumberOfArguments(m) == 3) method_getArgumentType(m, 2, a, sizeof a);
    BOOL wide = !strcmp(a, "q") || !strcmp(a, "Q"), narrow = !strcmp(a, "i") || !strcmp(a, "I") || !strcmp(a, "l") || !strcmp(a, "L");   // (an integer of 64 or 32 bits)
    if (kind == '@' && a[0] == '@') { ((void (*)(id, SEL, id))objc_msgSend)(o, s, obj); return @"set"; }
    if (kind == 'q' && wide) { ((void (*)(id, SEL, long long))objc_msgSend)(o, s, num); return @"set"; }
    if (kind == 'q' && narrow) { ((void (*)(id, SEL, int))objc_msgSend)(o, s, (int)num); return @"set"; }
    if (kind == 'B' && (!strcmp(a, "B") || !strcmp(a, "c"))) { ((void (*)(id, SEL, BOOL))objc_msgSend)(o, s, (BOOL)num); return @"set"; }
    if (m) return nil;   // (a setter of another type: not guessed)
    Ivar iv = class_getInstanceVariable(object_getClass(o), [@"_" stringByAppendingString:key].UTF8String);
    const char *t = iv ? ivar_getTypeEncoding(iv) : NULL;
    if (!t) return nil;
    uint8_t *p = (uint8_t *)(__bridge void *)o + ivar_getOffset(iv);
    if (kind == '@' && t[0] == '@') { object_setIvarWithStrongDefault(o, iv, obj); return @"ivar"; }
    if (kind == 'q' && (!strcmp(t, "q") || !strcmp(t, "Q"))) { *(long long *)p = num; return @"ivar"; }
    if (kind == 'q' && (!strcmp(t, "i") || !strcmp(t, "I") || !strcmp(t, "l") || !strcmp(t, "L"))) { *(int *)p = (int)num; return @"ivar"; }
    if (kind == 'B' && (!strcmp(t, "B") || !strcmp(t, "c"))) { *(BOOL *)p = (BOOL)num; return @"ivar"; }
    return nil;
}
static NSString *DMAPFakeFlag(id o, NSString *key, BOOL want) {   // (a boolean: set as above, or already so by its own getter -is<Key>; nil: neither)
    NSString *how = DMAPFakeSet(o, key, nil, want, 'B');
    SEL g = NSSelectorFromString([NSString stringWithFormat:@"is%@%@", [[key substringToIndex:1] uppercaseString], [key substringFromIndex:1]]);
    if (!how && (DMAPTypes(o, g, "B16@0:8") || DMAPTypes(o, g, "c16@0:8")) && ((BOOL (*)(id, SEL))objc_msgSend)(o, g) == want) how = @"already";
    return how;
}
static Class DMAPFakeClass(Class c, SEL needs) {   // (the class itself when it has that setter, else its mutable sibling STMutable... with it, else itself)
    if (!c || [c instancesRespondToSelector:needs]) return c;
    NSString *n = NSStringFromClass(c);
    Class m = [n hasPrefix:@"ST"] && ![n hasPrefix:@"STMutable"] ? NSClassFromString([@"STMutable" stringByAppendingString:[n substringFromIndex:2]]) : Nil;
    return m && [m isSubclassOfClass:c] && [m instancesRespondToSelector:needs] ? m : c;
}
static const void *kAPFakeBTKey = &kAPFakeBTKey;   // (per bar: @[iPadOS's own overlay, or NSNull; ours, as the bar holds it])
static NSString *gAPFakeBarArgs = nil;   // (the made-up item while it is on: "<state>_<percent>"; nil: off)
static BOOL DMAPFakeMerged(id bar, long long *state, BOOL *battOn) {   // (the bar's merged data: the Bluetooth entry's state, its battery entry on; NO: not readable)
    id d = DMAPObj(bar, NSSelectorFromString(@"currentAggregatedData")), e = DMAPObj(d, NSSelectorFromString(@"bluetoothEntry")), b = DMAPObj(e, NSSelectorFromString(@"batteryEntry"));
    SEL en = NSSelectorFromString(@"isEnabled"), st = NSSelectorFromString(@"state");
    if (!DMAPTypes(e, st, "q16@0:8")) return NO;
    *state = ((long long (*)(id, SEL))objc_msgSend)(e, st);
    *battOn = b && (DMAPTypes(b, en, "B16@0:8") || DMAPTypes(b, en, "c16@0:8")) && ((BOOL (*)(id, SEL))objc_msgSend)(b, en);
    return YES;
}
static NSString *DMAPFakeReadBack(id bar) {   // (what the bar's merged data says now: the Bluetooth entry's enabled, state, battery enabled and capacity)
    id d = DMAPObj(bar, NSSelectorFromString(@"currentAggregatedData")), e = DMAPObj(d, NSSelectorFromString(@"bluetoothEntry")), b = DMAPObj(e, NSSelectorFromString(@"batteryEntry"));
    SEL en = NSSelectorFromString(@"isEnabled"), st = NSSelectorFromString(@"state"), cap = NSSelectorFromString(@"capacity");
    int ee = DMAPTypes(e, en, "B16@0:8") ? ((BOOL (*)(id, SEL))objc_msgSend)(e, en) : -1, be = DMAPTypes(b, en, "B16@0:8") ? ((BOOL (*)(id, SEL))objc_msgSend)(b, en) : -1;
    long long s = DMAPTypes(e, st, "q16@0:8") ? ((long long (*)(id, SEL))objc_msgSend)(e, st) : -9, c = DMAPTypes(b, cap, "q16@0:8") ? ((long long (*)(id, SEL))objc_msgSend)(b, cap) : -9;
    return [NSString stringWithFormat:@"merged data %@: bluetooth entry %@ enabled %d state %lld, battery %@ enabled %d capacity %lld", d ? NSStringFromClass([d class]) : @"-",
        e ? NSStringFromClass([e class]) : @"-", ee, s, b ? NSStringFromClass([b class]) : @"-", be, c];
}
// One bar: overlay data with the made-up Bluetooth entry, over iPadOS's own overlay where the bar has one (a mutable copy of it, so what iPadOS
// overlays there stays; _off gives its own back). NO: not such a bar, or nothing changed (*how says why).
static BOOL DMAPFakeApply(UIView *bar, long long state, long long pct, NSString **how) {
    SEL setOv = NSSelectorFromString(@"setOverlayData:"), sBT = NSSelectorFromString(@"setBluetoothEntry:");
    if (![bar respondsToSelector:setOv] || ![bar respondsToSelector:NSSelectorFromString(@"overlayData")] || ![bar respondsToSelector:NSSelectorFromString(@"currentData")]) return NO;
    NSArray *kept = objc_getAssociatedObject(bar, kAPFakeBTKey);
    id now = DMCall(bar, @"overlayData");
    id own = kept.count > 1 && now == kept[1] ? kept[0] : (now ?: [NSNull null]);   // (iPadOS's own: the one found at the first change, or the one it set since)
    id cur = DMCall(bar, @"currentData");
    NSString *dn = NSStringFromClass([cur class]);
    id curBT = [cur respondsToSelector:NSSelectorFromString(@"bluetoothEntry")] ? DMCall(cur, @"bluetoothEntry") : nil;
    id curBatt = [cur respondsToSelector:NSSelectorFromString(@"mainBatteryEntry")] ? DMCall(cur, @"mainBatteryEntry") : nil;
    Class D = cur ? DMAPFakeClass([cur class], sBT) : Nil;
    Class E = DMAPFakeClass(curBT ? [curBT class] : NSClassFromString([dn stringByAppendingString:@"BluetoothEntry"]), NSSelectorFromString(@"setState:"));
    Class B = DMAPFakeClass(curBatt ? [curBatt class] : NSClassFromString([dn stringByAppendingString:@"BatteryEntry"]), NSSelectorFromString(@"setCapacity:"));
    id base = own != [NSNull null] && [own conformsToProtocol:@protocol(NSMutableCopying)] ? [own mutableCopy] : nil;
    id data = [base respondsToSelector:sBT] ? base : [D new], e = [E new], b = [B new];
    BOOL level = pct >= 0;   // (below 0: no level, the glyph alone: a battery entry that is off, or none where it cannot be made off)
    NSString *h1 = DMAPFakeFlag(e, @"enabled", YES), *h2 = DMAPFakeSet(e, @"state", nil, state, 'q');
    NSString *h3 = DMAPFakeFlag(b, @"enabled", level), *h4 = level ? DMAPFakeSet(b, @"capacity", nil, MIN(100LL, pct), 'q') : @"-";
    if (!level && !h3) { b = nil; h3 = @"no entry"; }
    NSString *h5 = b ? DMAPFakeSet(e, @"batteryEntry", b, 0, '@') : @"-", *h6 = DMAPFakeSet(data, @"bluetoothEntry", e, 0, '@');
    *how = [NSString stringWithFormat:@"data %@%@, entries %@ / %@: enabled %@, state %@, battery enabled %@, capacity %@, its battery %@, the data's entry %@", [data class],
        data == base && base ? @" (over iPadOS's own overlay)" : @"", E, B, h1 ?: @"NO", h2 ?: @"NO", h3 ?: @"NO", h4 ?: @"NO", h5 ?: @"NO", h6 ?: @"NO"];
    if (!data || !e || (level && !b) || !h1 || !h2 || !h3 || !h4 || !h5 || !h6) { *how = [*how stringByAppendingFormat:@" (the bar's data %@): not as expected, nothing changed", dn]; return NO; }
    ((void (*)(id, SEL, id))objc_msgSend)(bar, setOv, data);
    objc_setAssociatedObject(bar, kAPFakeBTKey, @[own, DMCall(bar, @"overlayData") ?: data], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    *how = [*how stringByAppendingFormat:@"; %@", DMAPFakeReadBack(bar)];
    return YES;
}
static void DMAPFakeBarItem(NSString *args) {   // (<state>_<percent> or off)
    NSArray *q = [args componentsSeparatedByString:@"_"];
    BOOL off = [q.firstObject isEqualToString:@"off"];
    if (!off && q.count < 2) { DMLog(@"[sbfakebt] sbfakebt_<state>_<percent> or sbfakebt_off"); return; }
    long long state = off ? 0 : [q[0] longLongValue], pct = off ? -1 : [q[1] longLongValue];
    gAPFakeBarArgs = off ? nil : [NSString stringWithFormat:@"%lld_%lld", state, pct];
    int done = 0;
    for (UIView *fg in gCopies.allObjects) {
        UIView *bar = fg.superview;
        if (!objc_getAssociatedObject(fg, kLogoKey)) continue;
        NSArray *kept = objc_getAssociatedObject(bar, kAPFakeBTKey);   // (@[iPadOS's own overlay or NSNull, ours])
        if (off) {
            if (!kept || ![bar respondsToSelector:NSSelectorFromString(@"setOverlayData:")]) continue;
            ((void (*)(id, SEL, id))objc_msgSend)(bar, NSSelectorFromString(@"setOverlayData:"), kept.firstObject == [NSNull null] ? nil : kept.firstObject);
            objc_setAssociatedObject(bar, kAPFakeBTKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            done++; continue;
        }
        NSString *how = nil;
        if (DMAPFakeApply(bar, state, pct, &how)) done++;
        if (how) DMLog([NSString stringWithFormat:@"[sbfakebt] %@: %@", NSStringFromClass([bar class]), how]);
    }
    DMLog([NSString stringWithFormat:@"[sbfakebt] %@ on %d bar(s) of ours", off ? @"own overlay back" : [NSString stringWithFormat:@"Bluetooth entry state %lld, %@", state,
        pct >= 0 ? [NSString stringWithFormat:@"their level %lld %%", MIN(100LL, pct)] : @"no level (the glyph alone)"], done]);
}
// While the made-up item is on, a bar whose merged data no longer says it gets it again: iPadOS sets a bar's overlay itself (the Cover Sheet
// coming and going) and makes new bars (a change of the Control Center style), and either dropped it on the A12Z (18.5). Asked after each data
// update of a bar (StatusBar.x DMStatusIconsUpdated), only for bars of ours, once per 0.5 s per bar, done at the next main-queue turn, over
// whatever overlay iPadOS set (which _off then gives back).
static void DMAPFakeBarRecheck(UIView *bar) {
    static const void *kAtKey = &kAtKey;
    if (!gAPFakeBarArgs || ![bar isKindOfClass:[UIView class]]) return;
    id fg = [bar respondsToSelector:NSSelectorFromString(@"foregroundView")] ? DMCall(bar, @"foregroundView") : nil;
    if (![fg isKindOfClass:[UIView class]] || !objc_getAssociatedObject(fg, kLogoKey)) return;
    NSArray *q = [gAPFakeBarArgs componentsSeparatedByString:@"_"];
    long long want = [q.firstObject longLongValue], pct = q.count > 1 ? [q[1] longLongValue] : -1, st = 0;
    BOOL batt = NO;
    if (DMAPFakeMerged(bar, &st, &batt) && st == want && batt == (pct >= 0)) return;   // (as asked: nothing to do)
    NSNumber *at = objc_getAssociatedObject(bar, kAtKey);
    if (at && CACurrentMediaTime() - at.doubleValue < 0.5) return;
    objc_setAssociatedObject(bar, kAtKey, @(CACurrentMediaTime()), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView *weakBar = bar;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *b = weakBar;
        if (!b || !gAPFakeBarArgs) return;
        NSArray *q2 = [gAPFakeBarArgs componentsSeparatedByString:@"_"];
        NSString *how = nil;
        BOOL ok = q2.count > 1 && DMAPFakeApply(b, [q2[0] longLongValue], [q2[1] longLongValue], &how);
        DMLog([NSString stringWithFormat:@"[sbfakebt] %@: %@ (iPadOS replaced its overlay, or a new bar): %@", NSStringFromClass([b class]), ok ? @"put back" : @"not put back", how ?: @"-"]);
    });
}
static void DMAPFakeShowItem(void) {   // (iPadOS's item for the made-up headphones: shown while one of them is connected, in the shape podfake_bar_ asked)
    DMAPHeadsetRec *on = nil;
    for (DMAPHeadsetRec *f in gAPFakeHeadsets) if (f.connected) { on = f; break; }
    if (!on || !gAPFake || gAPFakeNoItem) { DMAPFakeBarItem(@"off"); return; }   // (none: iPadOS's own data again, which shows no item for them)
    DMAPFakeBarItem(gAPFakeGlyphOnly ? @"2_-1" : [NSString stringWithFormat:@"2_%d", on.level >= 0 && on.level <= 100 ? on.level : 50]);
}

// ---- debug triggers: podfake_<pro|pro2|ap2|caseonly|max|other|unknown|two|err|drop|off>, podfake_bar_<glyph|level|none>, podfake_part_<h|p|n>_<0|1>,
// podmenu, podmenu_rows, podmenu_probe, podmenu_pref_<on|off|delete>, podmenu_ax ----
static DMAPHeadsetRec *DMAPFakeHeadset(NSString *name, NSString *address, long long pid, int level) {
    DMAPHeadsetRec *h = [DMAPHeadsetRec new];
    h.name = name; h.address = address; h.productId = pid; h.level = level; h.apple = pid != 0; h.connected = YES; h.fake = YES; h.phones = YES;
    return h;
}
static DMAPRouteRec *DMAPFakeRoute(NSString *uid, unsigned modes, int current) {
    DMAPRouteRec *r = [DMAPRouteRec new]; r.type = 2; r.uid = uid; r.modes = modes; r.current = current; return r;
}
static void DMAPFakePart(NSMutableData *d, unsigned long long parts, int pct, int chg, NSString *group, NSString *match, long long pid) {
    MSBDAPPart p; memset(&p, 0, sizeof p);
    p.parts = parts; p.percent = pct; p.charging = chg; p.productId = pid;
    DMAPCopyStr(p.groupName, sizeof p.groupName, group); DMAPCopyStr(p.matchId, sizeof p.matchId, match);
    [d appendBytes:&p length:sizeof p];
}
static BOOL DMAPFakeKind(NSString *kind) {   // (the made-up headphones; NO: not a kind)
    unsigned m3 = (1u << kMSBDAPModeOff) | (1u << kMSBDAPModeTransparency) | (1u << kMSBDAPModeNoiseCancellation), m4 = m3 | (1u << kMSBDAPModeAdaptive);
    NSMutableArray *hs = [NSMutableArray array], *route = [NSMutableArray array];
    NSMutableData *parts = [NSMutableData data];
    BOOL pro = [kind isEqualToString:@"pro"] || [kind isEqualToString:@"two"];
    if (pro) {
        [hs addObject:DMAPFakeHeadset(@"Test AirPods Pro", @"00:00:00:00:00:a1", 0x200e, 75)];
        DMAPFakePart(parts, 3, 75, 0, @"Test AirPods Pro", @"test-group-1", 0x200e); DMAPFakePart(parts, 4, 40, 1, @"Test Case", @"test-group-1", 0x200e);
        [route addObject:DMAPFakeRoute(@"00:00:00:00:00:A1-tacl", m3, kMSBDAPModeNoiseCancellation)];
    }
    if ([kind isEqualToString:@"pro2"]) {
        [hs addObject:DMAPFakeHeadset(@"Test AirPods Pro", @"00:00:00:00:00:a2", 0x2014, 62)];
        DMAPFakePart(parts, 1, 80, 0, @"Test AirPods Pro", @"test-group-2", 0x2014); DMAPFakePart(parts, 2, 62, 1, @"Test AirPods Pro", @"test-group-2", 0x2014);
        DMAPFakePart(parts, 4, 15, 0, @"Test Case", @"test-group-2", 0x2014);
        [route addObject:DMAPFakeRoute(@"00:00:00:00:00:A2-tacl", m4, kMSBDAPModeAdaptive)];
    }
    if ([kind isEqualToString:@"ap2"]) {
        [hs addObject:DMAPFakeHeadset(@"Test AirPods", @"00:00:00:00:00:a3", 0x200f, 90)];
        DMAPFakePart(parts, 3, 90, 0, @"Test AirPods", @"test-group-3", 0x200f); DMAPFakePart(parts, 4, 55, 0, @"Test Case", @"test-group-3", 0x200f);
    }
    if ([kind isEqualToString:@"caseonly"]) {
        [hs addObject:DMAPFakeHeadset(@"Test AirPods", @"00:00:00:00:00:a4", 0x200f, 70)];
        DMAPFakePart(parts, 4, 40, 0, @"Test Case", @"test-group-4", 0x200f);
    }
    if ([kind isEqualToString:@"max"]) {
        [hs addObject:DMAPFakeHeadset(@"Test AirPods Max", @"00:00:00:00:00:a5", 0x200a, 58)];
        DMAPFakePart(parts, 0, 60, 0, @"Test AirPods Max", @"test-group-5", 0x200a);
        [route addObject:DMAPFakeRoute(@"00:00:00:00:00:A5-tacl", m3, kMSBDAPModeOff)];
    }
    if ([kind isEqualToString:@"other"] || [kind isEqualToString:@"two"]) [hs addObject:DMAPFakeHeadset(@"Test Headphones", @"00:00:00:00:00:b1", 0, 55)];
    if ([kind isEqualToString:@"unknown"]) [hs addObject:DMAPFakeHeadset(@"Test Headset", @"00:00:00:00:00:b2", 0, -1)];
    if (!hs.count) return NO;
    gAPFakeHeadsets = hs; gAPFakeParts = parts; gAPFakeRoute = route; gAPFakeErr = NO;
    return YES;
}
static UIButton *DMAPVisibleButton(void) {
    for (UIView *fg in gCopies.allObjects) {
        UIButton *b = objc_getAssociatedObject(fg, kAirPodsButtonKey);
        if (b && !b.hidden && fg.window && !fg.window.hidden && DMEffectiveAlpha(fg) > 0.5) return b;
    }
    return nil;
}
static NSString *DMAPUIDShape(NSString *uid, NSString *address) {   // (a uid's shape only: its length, whether its first 17 characters are the address, the text after them)
    BOOL p17 = MSBDAirPodsUIDMatches(uid.UTF8String, address.UTF8String);
    NSString *tail = p17 && uid.length > 17 ? [uid substringFromIndex:17] : @"";
    if (tail.length > 12) tail = [[tail substringToIndex:12] stringByAppendingString:@"..."];
    return [NSString stringWithFormat:@"uidLen %lu prefix17IsAddress %d looksLikeAddress %d uidTail '%@'", (unsigned long)uid.length, p17, MSBDAirPodsLooksLikeAddress(uid.UTF8String), p17 ? tail : @""];
}
static void DMAPProbe(void) {   // (read only: D0 and the real-headphones check -- counts, types, parts bits, levels, mode strings and shapes; never a name, an address or a whole uid)
    DMAPCheck();
    NSMutableString *o = [NSMutableString stringWithString:@"[podprobe]"];
    // (D0.4: the table's rows here)
    for (size_t i = 0; i < sizeof(kDMAPNeeds) / sizeof(kDMAPNeeds[0]); i++) {
        const DMAPNeedRow *r = &kDMAPNeeds[i];
        Class c = objc_getClass(r->cls);
        Method m = !c ? NULL : r->meta ? class_getClassMethod(c, sel_registerName(r->sel)) : class_getInstanceMethod(c, sel_registerName(r->sel));
        [o appendFormat:@"\n  %c[%s %s] %s%s", r->meta ? '+' : '-', r->cls, r->sel, m ? method_getTypeEncoding(m) : (c ? "none" : "no class"), DMAPRowOK(r) ? "" : " (NOT as the table)"];
    }
    [o appendFormat:@"\n  parts: headphones %d, battery records %d, noise control %d; route note %d; icons-updated %u, layouts asked %u; StockVPNItem %d",
        gAPPart[kDMAPPartHeadset], gAPPart[kDMAPPartParts], gAPPart[kDMAPPartNoise], gAPRouteNote != nil, gDMIconsUpdatedCalls, gDMIconsUpdatedLayouts, (gSBItemHooks & 1) != 0];
    // (D0.1: the item and its display items, the battery's views, the spans)
    Class ic = DMAPItemClass();
    SEL sBattID = NSSelectorFromString(@"batteryDisplayIdentifier");
    Method bm = ic ? class_getClassMethod(ic, sBattID) : NULL;
    id battID = bm && DMAPTypes((id)ic, sBattID, "@16@0:8") ? ((id (*)(id, SEL))objc_msgSend)((id)ic, sBattID) : nil;
    [o appendFormat:@"\n  item %s batteryDisplayIdentifier %s", ic ? class_getName(ic) : "MISSING", bm ? method_getTypeEncoding(bm) : "none"];
    for (UIView *fg in gCopies.allObjects) {
        if (!fg.window || fg.window.hidden || fg.bounds.size.width < 300.0 || DMEffectiveAlpha(fg) < 0.5) continue;
        id regions = DMCall(fg.superview, @"regions");
        if ([regions isKindOfClass:[NSDictionary class]]) for (id rid in regions) {
            id list = DMCall(regions[rid], @"displayItems");
            BOOL mine = NO;
            if ([list conformsToProtocol:@protocol(NSFastEnumeration)]) for (id di in list) if (ic && [DMCall(di, @"item") isKindOfClass:ic]) mine = YES;
            if (!mine) continue;
            [o appendFormat:@"\n  region %@ items %lu:", rid, (unsigned long)[(NSArray *)list count]];
            for (id di in list) {
                id it = DMCall(di, @"item"), v = DMCall(di, @"view"), ident = DMAPObj(di, NSSelectorFromString(@"identifier"));
                if (!(ic && [it isKindOfClass:ic])) continue;
                NSString *img = [v isKindOfClass:[UIImageView class]] ? [((UIImageView *)v).image description] : nil;   // (iPadOS's glyph: its symbol's or image's name)
                NSRange nm = img ? [img rangeOfString:@"named("] : NSMakeRange(NSNotFound, 0);
                NSString *glyph = nm.location != NSNotFound ? [img substringFromIndex:nm.location] : img ?: @"-";
                [o appendFormat:@" %@ %@ %@ shown=%d battery=%d samePointer=%d image %@;", ident, v ? NSStringFromClass([v class]) : @"-",
                    [v isKindOfClass:[UIView class]] ? NSStringFromCGRect([(UIView *)v convertRect:((UIView *)v).bounds toView:fg]) : @"-",
                    [v isKindOfClass:[UIView class]] && DMBattViewShown(v, fg), ident && battID && [ident isEqual:battID], ident && ident == battID,
                    [[glyph componentsSeparatedByString:@")"].firstObject stringByAppendingString:@")"]];
            }
        }
        NSMutableArray *views = [NSMutableArray array], *others = [NSMutableArray array], *battViews = [NSMutableArray array];
        BOOL battShown = NO, found = DMAPItemViews(fg, views, others, battViews, &battShown), stateRead = NO;
        long long btState = DMAPBluetoothState(fg, &stateRead);
        SEL reg = NSSelectorFromString(@"alwaysShowRegulatoryBluetoothIndicator");
        int regulatory = ic && [(id)ic respondsToSelector:reg] && DMAPTypes((id)ic, reg, "B16@0:8") ? ((BOOL (*)(id, SEL))objc_msgSend)((id)ic, reg) : -1;
        CGRect u = DMAPUnion(fg, views), br = DMAPUnion(fg, battViews);
        UIButton *btn = objc_getAssociatedObject(fg, kAirPodsButtonKey), *bbtn = objc_getAssociatedObject(fg, kBattButtonKey);
        BOOL rtl = DMBarRTL(fg);
        double gap = CGRectIsNull(u) || CGRectIsNull(br) ? -1 : (DMBarLead(fg, rtl, br) > DMBarLead(fg, rtl, u) ? DMBarLead(fg, rtl, br) - DMBarTrail(fg, rtl, u) : DMBarLead(fg, rtl, u) - DMBarTrail(fg, rtl, br));
        CGRect ov = btn && bbtn && !btn.hidden && !bbtn.hidden ? CGRectIntersection(btn.frame, bbtn.frame) : CGRectNull;
        CGRect onScreen = btn && !btn.hidden ? [fg convertRect:btn.frame toCoordinateSpace:(fg.window.screen ?: [UIScreen mainScreen]).coordinateSpace] : CGRectNull;
        [o appendFormat:@"\n  copy %p: walk %d, views %lu (shown battery display %d), bluetooth state %lld (read %d, regulatory indicator %d), headphones item %d (1.8.8.1's rule %d), neighbours %lu, battery views %@ gap %.1f; spans airpods %@ battery %@ overlap %.1f; button on screen %@ hidden %d",
            fg, found, (unsigned long)views.count, battShown, btState, stateRead, regulatory, MSBDAirPodsItemIsHeadphones((int)views.count, battShown, stateRead, btState),
            battShown && views.count > 0, (unsigned long)others.count, NSStringFromCGRect(br), gap, btn ? NSStringFromCGRect(btn.frame) : @"-",
            bbtn ? NSStringFromCGRect(bbtn.frame) : @"-", CGRectIsNull(ov) ? 0.0 : ov.size.width, NSStringFromCGRect(onScreen), btn ? btn.hidden : 1];
        break;
    }
    // (fix 8, D0.5-D0.6, K1, K2: the data, counts and shapes only)
    NSArray<DMAPHeadsetRec *> *heads = DMAPReadHeadsets();
    [o appendFormat:@"\n  headphones: %lu listed (with a battery level %u, headphones by iPadOS's type %u, Apple audio %u); reads %u", (unsigned long)heads.count, gAPBattDevices,
        gAPHeadphoneTypes, gAPAppleAudio, gAPReadCount];
    for (DMAPHeadsetRec *h in heads) [o appendFormat:@" [%@ level %d pid 0x%llx]", DMWiFiTag(h.name), h.level, h.productId];
    NSData *pd = DMAPPartsNow();
    int np = (int)(pd.length / sizeof(MSBDAPPart));
    const MSBDAPPart *pp = pd.bytes;
    [o appendFormat:@"\n  batterycenter observer %d delivered %u records %d internal %u parts", gAPBatteryWatch != nil, gAPPartsDeliveries, np, gAPPartsInternal];
    for (int i = 0; i < np; i++) [o appendFormat:@" %llu:%d%%%@", pp[i].parts, pp[i].percent, pp[i].charging ? @"+" : @""];
    for (DMAPHeadsetRec *h in heads) {
        int caseI = -1, budI = -1;
        for (int i = 0; i < np; i++) { if ((pp[i].parts & 7) == 4 && caseI < 0) caseI = i; if ((pp[i].parts & 3) && budI < 0) budI = i; }
        MSBDAPHeadset ch; memset(&ch, 0, sizeof ch); DMAPCopyStr(ch.name, sizeof ch.name, h.name); ch.productId = h.productId;
        int idx[MSBD_AP_MAX_PARTS], g = MSBDAirPodsGroupFor(&ch, pp, np, idx, MSBD_AP_MAX_PARTS);
        [o appendFormat:@"\n  K1 %@: group %d case %d caseMatchIdEqual %d budsGroupNameIsBTName %d caseGroupNameIsBTName %d productIdEqual %d", DMWiFiTag(h.name), g, caseI >= 0,
            caseI >= 0 && budI >= 0 && !strcmp(pp[caseI].matchId, pp[budI].matchId), budI >= 0 && !strcmp(pp[budI].groupName, ch.name),
            caseI >= 0 && !strcmp(pp[caseI].groupName, ch.name), budI >= 0 && pp[budI].productId == h.productId];
    }
    id route = DMAPSystemRoute(), ep = DMAPEndpoint();
    id ep2 = route ? DMAPObj(route, NSSelectorFromString(@"endpoint")) : nil;
    NSArray<DMAPRouteRec *> *rt = DMAPReadRoute();
    NSMutableString *types = [NSMutableString string]; unsigned type2 = 0;
    for (DMAPRouteRec *r in rt) { [types appendFormat:@"%s%u", types.length ? "," : "", r.type]; if (r.type == 2) type2++; }
    [o appendFormat:@"\n  route made %d endpoint %@ devices %lu types %@ endpointIsObject %d read %.2f ms", route != nil, ep ? NSStringFromClass([ep class]) : @"-", (unsigned long)rt.count,
        types, ep && ep == ep2, gAPRouteReadMs];
    for (DMAPRouteRec *r in rt) {
        if (r.type != 2) continue;
        NSMutableString *ms = [NSMutableString string];
        for (int m = 0; m < kMSBDAPModes; m++) if (r.modes & (1u << m)) [ms appendFormat:@"%s%s", ms.length ? "," : "", kMSBDAPModeTitles[m]];
        [o appendFormat:@"\n  K2 type2 %u %@ modes %@ current %s", type2, DMAPUIDShape(r.uid, heads.firstObject.address ?: @""), ms, r.current >= 0 ? kMSBDAPModeTitles[r.current] : "none"];
    }
    // (D0.7: the glyphs here)
    [o appendString:@"\n  glyphs:"];
    for (int k = kMSBDAPCellBoth; k <= MSBD_AP_GLYPH_CHARGING; k++) {
        const char *word = ""; const char *const *chain = MSBDAirPodsGlyphs(k, &word);
        for (int j = 0; chain && chain[j]; j++) [o appendFormat:@" %s %d;", chain[j], [UIImage systemImageNamed:@(chain[j])] != nil];
    }
    DMLog(o);
}
static BOOL DMAPTrigger(NSString *cmd) {
    if ([cmd hasPrefix:@"podfake_part_"]) {   // podfake_part_<h|p|n>_<0|1>: with a test device, that part shown as missing (0) or there (1)
        NSArray *q = [[cmd substringFromIndex:13] componentsSeparatedByString:@"_"];
        int part = [q.firstObject isEqualToString:@"h"] ? kDMAPPartHeadset : [q.firstObject isEqualToString:@"p"] ? kDMAPPartParts : kDMAPPartNoise;
        if (q.count > 1 && [q[1] boolValue]) gAPFakePartsOff &= ~(1u << part); else gAPFakePartsOff |= 1u << part;
        DMLog([NSString stringWithFormat:@"[podmenu] test parts off: %u", gAPFakePartsOff]);
        DMAPSourceSaid(YES, YES);
        return YES;
    }
    if ([cmd hasPrefix:@"podfake_bar_"]) {   // podfake_bar_glyph / _level: iPadOS's item for the made-up headphones as the glyph alone (AirPods on 17/18),
        gAPFakeGlyphOnly = [[cmd substringFromIndex:12] isEqualToString:@"glyph"];   // or with their level (the default); at once if they are on
        gAPFakeNoItem = [[cmd substringFromIndex:12] isEqualToString:@"none"];   // (_none, 1.8.8.2: no item for them at all, iPadOS 15.6.1's real case)
        DMLog([NSString stringWithFormat:@"[podmenu] test: iPadOS's item %@", gAPFakeNoItem ? @"not shown (our own icon's case)" : gAPFakeGlyphOnly ? @"the glyph alone" : @"the glyph and their level"]);
        if (gAPFake) DMAPFakeShowItem();
        return YES;
    }
    if ([cmd hasPrefix:@"podfake_"]) {   // podfake_<kind> / _err / _drop / _off: made-up headphones in the three caches, iPadOS's item shown
        NSString *k = [cmd substringFromIndex:8];
        if ([k isEqualToString:@"off"]) {
            gAPFake = 0; gAPFakeHeadsets = nil; gAPFakeParts = nil; gAPFakeRoute = nil; gAPFakeErr = NO; gAPFakePartsOff = 0;
            DMAPFakeBarItem(@"off");
            DMLog(@"[podmenu] test device off: the real state");
            DMAPSourceSaid(YES, YES);
            return YES;
        }
        if ([k isEqualToString:@"err"]) { gAPFakeErr = YES; DMLog(@"[podmenu] test: the next noise change fails"); return YES; }
        if ([k isEqualToString:@"drop"]) {
            for (DMAPHeadsetRec *h in gAPFakeHeadsets) h.connected = NO;
            DMAPFakeBarItem(@"off");
            DMLog(@"[podmenu] test: the headphones dropped");
            DMAPSourceSaid(YES, YES);
            return YES;
        }
        if (!DMAPFakeKind(k)) { DMLog([NSString stringWithFormat:@"[podmenu] podfake_%@: no such kind", k]); return YES; }
        gAPFake = 1;
        DMAPFakeShowItem();
        DMLog([NSString stringWithFormat:@"[podmenu] test device: %@ (iPadOS's item: %@)", k, gAPFakeNoItem ? @"none" : gAPFakeGlyphOnly ? @"the glyph alone" : @"the glyph and their level"]);
        DMAPSourceSaid(YES, YES);
        return YES;
    }
    if ([cmd isEqualToString:@"podmenu"]) {   // open the AirPods menu from the visible status bar
        UIButton *b = DMAPVisibleButton();
        if (b) DMOpenAirPodsMenu(b); else DMLog(@"[podmenu] podmenu: no AirPods button on the screen (switch off, or no headphones)");
        return YES;
    }
    if ([cmd isEqualToString:@"podmenu_rows"]) {   // what the menu would show now
        BOOL open = gAPMenuOpen;
        if (!open) { DMAPCheck(); gAPMenuHeadsets = nil; DMAPMergeHeadsets(DMAPReadHeadsets()); gAPRoute = DMAPReadRoute(); }
        NSString *log = nil; DMAPMenuItems(NULL, &log);
        if (!open) { gAPMenuHeadsets = nil; gAPRoute = nil; }
        DMLog([NSString stringWithFormat:@"[podmenu] menu now: %@", log]);
        return YES;
    }
    if ([cmd isEqualToString:@"podmenu_probe"]) { DMAPProbe(); return YES; }
    if ([cmd hasPrefix:@"podmenu_pref_"]) {   // podmenu_pref_on / _off / _delete: the Settings switch, as Settings writes it (delete: never set)
        NSString *w = [cmd substringFromIndex:13];
        CFPreferencesSetValue(CFSTR(MSBD_AIRPODS_MENU_KEY), [w isEqualToString:@"delete"] ? NULL : ([w isEqualToString:@"on"] ? kCFBooleanTrue : kCFBooleanFalse), MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesSynchronize(MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        notify_post("com.besiktasliseba.macstatusbar/prefsChanged");
        DMLog([NSString stringWithFormat:@"[podmenu] pref %@", w]);
        return YES;
    }
    if ([cmd isEqualToString:@"podmenu_ax"]) {   // the AirPods button as VoiceOver gets it, and how many of the bar's elements say Headphones or Battery
        UIButton *b = DMAPVisibleButton();
        UIView *fg = b.superview;
        NSHashTable *covered = fg ? objc_getAssociatedObject(fg, kAPCoveredKey) : nil;
        int heads = 0, batts = 0;
        NSMutableArray *todo = [NSMutableArray arrayWithObject:fg.superview ?: (fg ?: [UIView new])];
        for (NSUInteger i = 0; i < todo.count && i < 200; i++) {
            id e = todo[i];
            if ([e isAccessibilityElement]) { NSString *l = [e accessibilityLabel]; if ([l isEqualToString:@"Headphones"]) heads++; if ([l isEqualToString:@"Battery"]) batts++; }
            NSArray *kids = [e accessibilityElements];
            if (kids.count) [todo addObjectsFromArray:kids];
            else if ([e isKindOfClass:[UIView class]] && ![e isAccessibilityElement]) [todo addObjectsFromArray:((UIView *)e).subviews];
        }
        DMLog([NSString stringWithFormat:@"[podmenu] accessibility: button %@ (label %@, hint %@, value length %lu); iPadOS views covered %lu; elements Headphones %d, Battery %d",
            b ? @"shown" : @"none", b.accessibilityLabel, b.accessibilityHint, (unsigned long)b.accessibilityValue.length, (unsigned long)covered.allObjects.count, heads, batts]);
        return YES;
    }
    return NO;
}
#endif
