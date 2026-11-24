// RecentStrip.h: the Recent Windows Strip (1.8.8.2 F29, reworked in 1.8.8.4), included by StatusBar.x after WindowCards.h. KT, 20 Nov: "We can
// make it a 1.8.8.2 feature, and it can be like on macos"; 24 Nov: "lets fix the side strip on os15", "Make it fully integrated with all parts of
// the os system". The windows of the desktop that are off it (minimized, sent to the strip, swapped out) wait at its side as small pictures, most
// recent first, as with Stage Manager on a Mac: a minimize flies into its slot; a tap or click on a card brings that window back out of its card
// and the window in front flies into the slot the card leaves (a swap); the Dock icon, Command-Tab, the App Switcher, Spotlight or a notification
// bring a waiting window back with no swap, out of its card too. Aerial, Zetsu and MilkyWay4 (their windows are our engine code's stages,
// DMAerialStages, one per app), on iPadOS 15 (common/RecentStripRule.h MSBDRecentStripOS: the pictures without SpringBoard waiting are read there
// only). Settings > Windows & Multitasking > Recent Windows Strip (recentStrip, off unless switched on since 1.8.8.2.1). The rules are
// common/RecentStripRule.h (Mac test tools/test-recentstrip.sh).
//  - The list is not kept by hand: it is this desktop's windows our minimize hid (kStageHiddenKey; MilkyWay4's kMinimizedKey), each with the time it
//    went in on the window itself (and in the windows' state file, so a respring keeps the order), plus a kept card for a waiting window whose app
//    iPadOS ended. A window found minimized with no time is seeded: older than any real one, in the stage order.
//  - The flights are our minimize's and our restore's own (StatusBar.x DMMinimizeAnimate, DMRestoreAnimate): DMMinimizedTransform asks the strip
//    first (DMRStripFlightRect), so every minimize and every way back, on every engine, goes through it.
//  - No timer and no poll of its own: DMRStripTick rides the 0.2 s window watcher (DMSyncWindowsForLibraryBody) and returns after a signature of
//    what it reads while nothing changed (nothing at rest); a minimize, a way back, a pick and a window drag lay the strip out at once (a window
//    dragged over the cards puts it aside in the same frame; dragged to its edge, it comes out with a slot open; let go there, the window goes in). The pointer comes from one hover recognizer on SpringBoard's system gestures window of the iPad (PointerRegion.h's
//    DMPtrHoverRecognizer: it only watches), there only while the strip has stepped aside with a trackpad or mouse attached.
//  - Still pictures, never a portal (a portal has the render server draw the window again in every frame): the render server's picture of the
//    window's layer at the card's size, from a background queue (MacSwitcher.h's lookups, queue and slot holder), taken right before a window goes
//    in, and 0.6 s after a window left the front (the windows behind in a burst keep that one). One layer per picture, its corners on that layer.
//  - Our window (the Mac Switcher's window class) just above the windows' level; only the cards take touches.
//  - A crash in this file or its rules turns the switch off (tools/crashmap-rules.txt, recentStrip).
#include "../common/RecentStripRule.h"
#import <UIKit/UIGestureRecognizerSubclass.h>

static BOOL gRStripPref = NO;   // Settings > Windows & Multitasking > Recent Windows Strip (recentStrip): off unless switched on (DMLoadPrefs; 1.8.8.2.1)
static BOOL gDMPointerAttached;  // (a trackpad or mouse attached: StatusBar.x, DMPointerDeviceCheck)
static void DMMinimizeActiveApp(void);   // (StatusBar.x: Command-M's minimize of the window in front, which Window > Move to Strip is)
@class DMRStripCard;
static void DMRStripPick(DMRStripCard *card, BOOL shift, NSString *how);
static void DMRStripKeysTake(BOOL take);
static BOOL DMRStripHandleWanted(void);
static UIWindow *gRStripWindow;                                  // our window, made the first time the strip shows; hidden while it is
static UIView *gRStripRoot;                                      // its content, turned with the screen (DMRStripTurnIn only)
static UIView *gRStripSlide;                                     // the cards, the whole of gRStripRoot (each card slides in and out by itself: DMRStripShowAs)
static unsigned gRStripLayouts, gRStripTicks, gRStripWorkTicks, gRStripPicsTaken;   // (the debug trigger rstrip says them)
static NSArray<NSString *> *gRStripList;                         // the windows off this desktop, most recent first (an engine window's key: its app)
static NSArray<NSString *> *gRStripItems;                        // the cards shown now, in order: the first of the list, as many as fit
static NSDictionary<NSString *, UIView *> *gRStripStageOf;       // (the last look: key -> its window)
static BOOL gRStripAnyShown, gRStripCalmNow, gRStripFrontNow;    // (the last look: a window on screen; nothing over the windows; the windows in front)
static int gRStripFit;                                           // (the last layout: how many cards fit the desktop's height)
static BOOL gRStripHomeBand = NO;                                // the Home Screen keeps the strip's band free (DMRStripHomeBandStep): with every window minimized it shows there
static double gRStripHomeRoom = 0;                               // ... the band's width the Home Screen keeps now (0 none), on gRStripHomeRight's side
static BOOL gRStripHomeRight = NO;
static NSMutableDictionary<NSString *, UIView *> *gRStripPics;   // key -> its window's picture (a view of a render server slot), card size
static NSMutableDictionary<NSString *, NSNumber *> *gRStripPicAt;    // key -> when it was taken
static NSMutableDictionary<NSString *, NSNumber *> *gRStripPicDue;   // key -> when its picture after leaving the front is due
static NSMutableSet<NSString *> *gRStripPicAsking;               // asked, the answer not here yet
static NSMutableDictionary<NSString *, DMRStripCard *> *gRStripCards;   // key -> its card
static NSMutableDictionary<NSString *, NSDictionary *> *gRStripGhosts;  // key -> {at, why, place}: a waiting window whose app iPadOS ended
static NSMutableDictionary<NSString *, NSDictionary *> *gRStripGone;    // key -> {at, why, place, since}: a waiting window that just went, decided soon
static NSDictionary<NSString *, NSDictionary *> *gRStripLastSeen;      // (the last look: the list's windows, {at, why, place})
static NSMutableDictionary<NSString *, NSValue *> *gRStripLeaving;      // key -> its card's place on the screen: a picked window on its way out of it
static NSMutableDictionary<NSString *, NSNumber *> *gRStripLeavingAt;
static NSMutableDictionary<NSString *, NSDictionary *> *gRStripRelaunch;   // key -> {due, place}: its app opens again at its place (MilkyWay4's grey window closed first)
static MSBDRStripShow gRStripShown = MSBDRStripHidden;
static int gRStripReveal = 0;                                    // MSBDRStripReveal: none, the pointer at the edge, the Window menu, the handle, a flight
static CFTimeInterval gRStripTouchedAt = 0, gRStripPointerOutAt = 0, gRStripLastPickAt = -100;
static BOOL gRStripMayRevealNow = NO;                            // (the last look: the strip stepped aside with something to show)
static MSBDRRect gRStripBand, gRStripSpan;
static BOOL gRStripRight = NO;
static NSString *gRStripLayoutSig;
static NSString *gRStripFront = @"";                             // the app whose window was in front at the last look ("" none)
static NSString *gRStripBurstFront;                              // a burst (Minimize All, Home) under way: the window in front at its start
static BOOL gRStripBursting = NO;                                // ... between DMRStripBurstBegin and DMRStripBurstEnd
static UIHoverGestureRecognizer *gRStripSysHover;
static __weak UIWindow *gRStripSysHoverWindow;
static UIView *gRStripHighlight;                                 // the band's soft highlight while a window drag is over the drop zone
static __weak UIView *gRStripDragWin;                            // the window being dragged by hand now (its title bar: every engine's, our own windows')
static CGRect gRStripDragFrom;                                   // ... its engine frame as the drag began: a window dropped into the strip comes back there
static MSBDRRect gRStripDragBand; static BOOL gRStripDragRight;  // ... the drop zone's band as the drag began
static CGSize gRStripDragScreen;                                 // ... for this shape of the screen (a turn during the drag: the new shape's band)
static BOOL gRStripDragCovers = NO;                              // ... it lay over the cards at its last move
static CFTimeInterval gRStripDragAt;                             // ... when it last moved (a drag with no end call, its window closed meanwhile, is let go)
static BOOL gRStripDropTarget = NO;                              // a window drag is over the drop zone: out over the windows, a slot open at the top
static int gRStripGapAt = -1;                                    // the slot open among the cards (-1 none)
static __weak UIView *gRStripDropTakenWin; static CFTimeInterval gRStripDropTakenAt;   // (the last drop taken: the same drag's second end call skips its snap too)
@class DMRStripDrag;
static DMRStripDrag *gRStripCardDrag;                            // a card dragged out now (its proxy follows the touch)
static NSString *gRStripDraggingKey;                             // ... its window's key: out of the list's layout while it is dragged (the gap closes);
                                                                 //     its card stays (DMRStripCardGoes) and the strip counts it (DMRStripDragHolds)
static id gRStripFocusLock;                                      // the keyboard's focus held while Window > Show Recent Windows brought the strip out
static NSDictionary<NSString *, NSArray<DMNativeWindow *> *> *gRStripGroups;   // our own windows in it: their app's card -> its windows, most recent first
static UIView *gRStripHandle, *gRStripHandleTouch;               // the finger's handle at the edge while the strip has stepped aside (no trackpad or mouse)
static int gRStripKeySel = -1;                                   // ... the card the keys selected (-1 none)
// On a window (an engine's stage, Zetsu's window, MilkyWay4's window):
static const void *kRStripAtKey = &kRStripAtKey;           // NSNumber: when it went into the strip (seconds since 2001, so a respring keeps it)
static const void *kRStripWhyKey = &kRStripWhyKey;         // NSNumber: why (MSBDRStripWhy)
static const void *kRStripPendingKey = &kRStripPendingKey; // @[at, why]: a swap, a burst or a respring's restore sets it before the minimize, which takes it
static const void *kRStripDelayKey = &kRStripDelayKey;     // NSNumber: a burst's flight starts this much later (Minimize All, Home)
static const void *kRStripPlaceKey = &kRStripPlaceKey;     // NSValue: its engine frame as it went in (where a kept card's app opens again)
static const void *kRStripReturnKey = &kRStripReturnKey;   // NSValue: a window dropped into the strip goes back to this engine frame once hidden
static const void *kRStripGoingKey = &kRStripGoingKey;     // (one of our own windows on its way into the strip: its flight under way, it is hidden at the end)

static BOOL DMRStripOn(void) {
    if (!gRStripPref || gStockBar) return NO;
    DMEngine e = DMActiveEngine();
    if (e != DMEngineAerial && e != DMEngineZetsu && e != DMEngineMilkyWay) return NO;   // (Stage Manager and windowing off: DMEngineNone)
    static int os = -1;
    if (os < 0) os = MSBDRecentStripOS([NSProcessInfo processInfo].operatingSystemVersion.majorVersion) ? 1 : 0;
    return os && DMMSWAsyncPicturesOK();
}
static double DMRStripClock(void) { return CFAbsoluteTimeGetCurrent(); }
// The app of the window in front now ("" none): the engine's top window on screen, as the tick's own look has it.
static NSString *DMRStripFrontNow(void) {
    BOOL stageEngine = DMActiveEngine() == DMEngineAerial || DMActiveEngine() == DMEngineZetsu;
    UIView *top = stageEngine ? DMTopStage() : DMTopWindow();
    NSString *b = top ? (stageEngine ? DMStageBundle(top) : [(AXWindowView *)top bundleIdentifier]) : nil;
    return [b isKindOfClass:[NSString class]] && b.length ? b : @"";
}
static BOOL DMRStripStageOnScreen(UIView *st) {
    return st && !st.hidden && st.alpha > 0.05 && !DMStageMinimized(st) && ![objc_getAssociatedObject(st, kStageClosingKey) boolValue];
}
static MSBDRRect DMRStripRectOf(CGRect r) { return (MSBDRRect){ r.origin.x, r.origin.y, r.size.width, r.size.height }; }
static CGRect DMRStripCGRect(MSBDRRect r) { return CGRectMake(r.x, r.y, r.w, r.h); }

// ---- which windows wait in it, and since when ----
// Our own windows (Finder, TextEdit, Activity Monitor, Display Settings: DMNativeWindow) wait in it too, one card per app (its key "native:<app>"),
// up to 3 pictures stacked and a count over 3 (KT's choice: a pick brings them all, the most recent in front). Their pictures by window ("nw:<window>").
static NSString *DMRStripNativeKey(DMNativeWindow *w) { return [@"native:" stringByAppendingString:w.appName.length ? w.appName : @"Window"]; }
static BOOL DMRStripIsNativeKey(NSString *k) { return [k hasPrefix:@"native:"]; }
static NSString *DMRStripNativePicKey(DMNativeWindow *w) { return w ? [NSString stringWithFormat:@"nw:%p", w] : @""; }
// One of our own windows minimized on another of the Mac Switcher's desktops: the Mac Switcher keeps a minimized one in Finder's list wherever it is
// (MacSwitcher.h, kMSWNativeDeskKey: the desktop it was on), so it waits in that desktop's strip only (a pick here showed it, and the Mac Switcher
// then took it away to its own desktop at once; review of 1.8.8.4). No desk noted, or one desktop: this one's.
static BOOL DMRStripNativeAway(DMNativeWindow *w) {
    if (!w || !DMMSWForMain() || !DMMSWMulti()) return NO;
    NSNumber *d = objc_getAssociatedObject(w, kMSWNativeDeskKey);
    return [d isKindOfClass:[NSNumber class]] && d.integerValue != DMMSWCurId();
}
static BOOL DMRStripHiddenByUs(UIView *st) {   // (our minimize hid it: Aerial's and Zetsu's kStageHiddenKey, MilkyWay4's kMinimizedKey, our own windows' minimize)
    if (!st) return NO;
    if ([st isKindOfClass:[DMNativeWindow class]]) return st.hidden && ((DMNativeWindow *)st).dm_wasMinimized;
    Class mw = objc_getClass("AXWindowView");
    if (mw && [st isKindOfClass:mw]) return DMWindowMinimized(st);
    return [objc_getAssociatedObject(st, kStageHiddenKey) boolValue];
}
static BOOL DMRStripBurstPending(UIView *st) { return objc_getAssociatedObject(st, kRStripDelayKey) && objc_getAssociatedObject(st, kRStripPendingKey); }
static BOOL DMRStripOffDesktop(UIView *st) {   // (in the strip: hid by us -- or a burst's window whose flight is still to come --, not on its way out, of this desktop)
    return st && MSBDRStripIsOff(DMRStripHiddenByUs(st) || DMRStripBurstPending(st), [objc_getAssociatedObject(st, kStageClosingKey) boolValue],
                                 [objc_getAssociatedObject(st, kStageGoingFullKey) boolValue], [objc_getAssociatedObject(st, kMSWAwayKey) boolValue]);
}
static BOOL DMRStripEntryOf(UIView *st, double *at, int *why) {
    NSNumber *t = st ? objc_getAssociatedObject(st, kRStripAtKey) : nil;
    if (![t isKindOfClass:[NSNumber class]]) return NO;
    if (at) *at = t.doubleValue;
    if (why) *why = [objc_getAssociatedObject(st, kRStripWhyKey) intValue];
    return YES;
}
static void DMRStripSetEntry(UIView *st, double at, int why) {
    if (!st) return;
    objc_setAssociatedObject(st, kRStripAtKey, @(at), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(st, kRStripWhyKey, @(why), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void DMRStripClearEntry(UIView *st) {
    if (!st) return;
    objc_setAssociatedObject(st, kRStripAtKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(st, kRStripWhyKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(st, kRStripPendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(st, kRStripDelayKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(st, kRStripPlaceKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static CGRect DMRStripPlaceNow(UIView *st) {   // (its engine frame: where it comes back -- the place kept for a minimized one, else where it is)
    NSValue *intent = st ? objc_getAssociatedObject(st, kStageIntentKey) : nil;
    CGRect f = intent ? intent.CGRectValue : (st ? st.frame : CGRectNull);
    return CGRectIsNull(f) || f.size.width < 150.0 || f.size.height < 150.0 ? (st ? st.frame : CGRectNull) : f;
}
static NSValue *DMRStripPlaceOf(UIView *st) {
    NSValue *p = st ? objc_getAssociatedObject(st, kRStripPlaceKey) : nil;
    return p ?: [NSValue valueWithCGRect:DMRStripPlaceNow(st)];
}

// ---- the pictures ----
// v's picture at k of its size (its points times the screen's scale times k), handed to done on the main thread: a view of that size showing it,
// or nil. MacSwitcher.h DMMSWPictureAsync's request (read on 15.6.1) with the scale in its transform, so the server draws a card's size, not the
// window's. NO: nothing was asked.
static BOOL DMRStripPictureAsync(UIView *v, double k, void (^done)(UIView *pic, double ms)) {
    if (!v || !done || k <= 0.0 || !DMMSWAsyncPicturesOK()) return NO;
    CALayer *l = v.layer;
    id ctx = DMCall(l, @"context");
    if (!ctx) return NO;
    if ([l respondsToSelector:NSSelectorFromString(@"hasBeenCommitted")] && !((BOOL (*)(id, SEL))objc_msgSend)(l, NSSelectorFromString(@"hasBeenCommitted"))) return NO;
    uint32_t cid = ((uint32_t (*)(id, SEL))objc_msgSend)(ctx, NSSelectorFromString(@"contextId"));
    CGRect b = v.bounds;
    if (!cid || b.size.width < 1 || b.size.height < 1) return NO;
    double s = [UIScreen mainScreen].scale * k;
    CGSize px = CGSizeMake(ceil(b.size.width * s), ceil(b.size.height * s)), pt = CGSizeMake(b.size.width * k, b.size.height * k);
    CATransform3D t = CATransform3DConcat(CATransform3DMakeTranslation(-b.origin.x, -b.origin.y, 0), CATransform3DMakeScale(s, s, 1));
    id name = DMCall([UIScreen mainScreen], @"_name");
    NSMutableDictionary *opts = [NSMutableDictionary dictionary];
    opts[gMSWSnapKeyMode] = gMSWSnapModeLayer;
    if ([name isKindOfClass:[NSString class]]) opts[gMSWSnapKeyName] = name;
    opts[gMSWSnapKeyCtx] = @(cid);
    opts[gMSWSnapKeyLayer] = @((unsigned long long)(uintptr_t)(__bridge void *)l);
    opts[gMSWSnapKeyTransform] = [NSValue valueWithCATransform3D:t];
    if (gMSWSnapKeyReuse) opts[gMSWSnapKeyReuse] = @YES;
    if (gMSWSnapKeyIgnoreAX) opts[gMSWSnapKeyIgnoreAX] = @YES;
    CFTimeInterval t0 = CACurrentMediaTime();
    UIView *keep = v;   // (the layer stays alive until the server has drawn it)
    dispatch_async(DMMSWPicQueue(), ^{
        uint32_t slot = 0; BOOL ok = NO;
        @try { slot = ((uint32_t (*)(id, SEL, CGSize, BOOL))objc_msgSend)(ctx, NSSelectorFromString(@"createImageSlot:hasAlpha:"), px, YES); } @catch (id e) { slot = 0; }
        if (slot) { opts[gMSWSnapKeyDest] = @(slot); ok = gMSWSnapFn(MACH_PORT_NULL, opts); }
        dispatch_async(dispatch_get_main_queue(), ^{
            (void)keep;
            double ms = (CACurrentMediaTime() - t0) * 1000.0;
            DMMSWSlotHolder *h = nil;
            if (slot) { h = [DMMSWSlotHolder new]; h.context = ctx; h.slot = slot; }
            id contents = ok ? ((id (*)(id, SEL, unsigned int))objc_msgSend)(objc_getClass("CAContext"), NSSelectorFromString(@"objectForSlot:"), slot) : nil;
            if (!contents) { done(nil, ms); return; }   // (h goes: its slot is deleted)
            UIView *pic = [[UIView alloc] initWithFrame:CGRectMake(0, 0, pt.width, pt.height)];
            pic.userInteractionEnabled = NO;
            pic.layer.contents = contents;
            objc_setAssociatedObject(pic, kMSWSlotKey, h, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            done(pic, ms);
        });
    });
    return YES;
}
static void DMRStripCardRefresh(NSString *k);   // (below, with the cards)
static void DMRStripPicture(UIView *stage, NSString *k, NSString *why) {
    if (!stage || !k.length || [gRStripPicAsking containsObject:k] || DMTestFlag("/tmp/msb-rstrip-nopics")) return;
    CGSize sc = [UIScreen mainScreen].bounds.size;
    CGRect bb = stage.bounds;
    double scale = MSBDRStripPicScale(bb.size.width, bb.size.height, MSBDRStripCardW(sc.width, sc.height), MSBDRStripCardH(sc.width, sc.height));
    if (scale <= 0.0) return;
    if (!gRStripPicAsking) gRStripPicAsking = [NSMutableSet set];
    [gRStripPicAsking addObject:k];
    NSString *k2 = [k copy], *why2 = [why copy];
    BOOL asked = DMRStripPictureAsync(stage, scale, ^(UIView *pic, double ms) {
        [gRStripPicAsking removeObject:k2];
        if (!pic) { static int told = 0; if (told++ < 3) DMLog([NSString stringWithFormat:@"[recentstrip] %@: no picture of its window (%@, %.1f ms)", k2, why2, ms]); return; }
        if (!DMRStripOn()) return;
        if (!gRStripPics) gRStripPics = [NSMutableDictionary dictionary];
        if (!gRStripPicAt) gRStripPicAt = [NSMutableDictionary dictionary];
        UIView *old = gRStripPics[k2];
        gRStripPics[k2] = pic; gRStripPicAt[k2] = @(CACurrentMediaTime());
        gRStripPicsTaken++;
        DM_FEATURE_MARK("recent-strip-picture");
        if (ms > 30.0 || DMTestFlag("/tmp/macstatusbar-debug")) DMLog([NSString stringWithFormat:@"[recentstrip] %@: its window pictured (%@): %.1f ms, %.0f x %.0f pt", k2, why2, ms, pic.bounds.size.width, pic.bounds.size.height]);
        DMRStripCardRefresh(k2);   // (the card shows the new one before the old one's slot goes with it)
        (void)old;
    });
    if (!asked) [gRStripPicAsking removeObject:k];
}
// A card with no picture yet: its app's icon on a card tinted from the icon's own colour (one 1 x 1 render of the icon, kept per app), not grey.
// Our own apps' card icon: a symbol on a tile in its app's colour (they have no home screen icon to read here), one image per app.
static UIImage *DMRStripNativeIcon(NSString *app) {
    static NSMutableDictionary<NSString *, UIImage *> *icons;
    if (!icons) icons = [NSMutableDictionary dictionary];
    if (icons[app ?: @""]) return icons[app ?: @""];
    NSDictionary *look = @{ @"Finder": @[@"face.smiling.fill", [UIColor colorWithRed:0.16 green:0.52 blue:0.96 alpha:1]], @"TextEdit": @[@"doc.text.fill", [UIColor colorWithWhite:0.55 alpha:1]],
                            @"Activity Monitor": @[@"waveform.path.ecg", [UIColor colorWithWhite:0.18 alpha:1]], @"Display Settings": @[@"display", [UIColor colorWithRed:0.20 green:0.42 blue:0.90 alpha:1]] };
    NSArray *l = look[app ?: @""] ?: @[@"macwindow", [UIColor colorWithWhite:0.45 alpha:1]];
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat preferredFormat];
    UIImage *img = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(52, 52) format:f] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [(UIColor *)l[1] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(2, 2, 48, 48) cornerRadius:11] fill];
        UIImage *sym = [[UIImage systemImageNamed:l[0] withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightSemibold]] imageWithTintColor:[UIColor whiteColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
        if (sym) [sym drawInRect:CGRectMake(26 - sym.size.width / 2.0, 26 - sym.size.height / 2.0, sym.size.width, sym.size.height)];
    }];
    if (img) icons[app ?: @""] = img;
    return img;
}
static UIColor *DMRStripIconTint(NSString *b, UIImage *icon) {
    static NSMutableDictionary<NSString *, UIColor *> *tints;
    if (!tints) tints = [NSMutableDictionary dictionary];
    UIColor *c = b.length ? tints[b] : nil;
    if (c) return c;
    c = [UIColor colorWithWhite:0.86 alpha:1.0];
    CGImageRef img = icon.CGImage;
    if (img) {
        unsigned char px[4] = { 0, 0, 0, 0 };
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx = cs ? CGBitmapContextCreate(px, 1, 1, 8, 4, cs, (CGBitmapInfo)kCGImageAlphaPremultipliedLast) : NULL;
        if (cs) CGColorSpaceRelease(cs);
        if (ctx) {
            CGContextSetInterpolationQuality(ctx, kCGInterpolationMedium);
            CGContextDrawImage(ctx, CGRectMake(0, 0, 1, 1), img);
            CGContextRelease(ctx);
            double a = px[3] / 255.0;
            if (a > 0.05) {   // (the icon's mean colour, lightened as an empty window's card would look)
                double r = MIN(1.0, px[0] / 255.0 / a), g = MIN(1.0, px[1] / 255.0 / a), bl = MIN(1.0, px[2] / 255.0 / a);
                c = [UIColor colorWithRed:0.55 + 0.45 * r green:0.55 + 0.45 * g blue:0.55 + 0.45 * bl alpha:1.0];
            }
        }
    }
    if (b.length) tints[b] = c;
    return c;
}

// ---- the cards ----
@interface DMRStripCard : UIView
@property (nonatomic, copy) NSString *key;          // the window it stands for (an engine window: its app)
@property (nonatomic, copy) NSString *bundle;       // its app
@property (nonatomic, strong) UIView *lift;         // what the hover, the press and the settle scale (the card's own transform is its slide in and out)
@property (nonatomic, strong) UIView *shadow;       // the picture's shadow, by a path (no offscreen pass)
@property (nonatomic, strong) UIView *pic;          // the picture: its own layer's contents, its corners on that layer (no sublayer under the mask)
@property (nonatomic, strong) UIImageView *icon;    // the app's icon over the picture's lower left corner
@property (nonatomic) CGRect picRect;               // the picture's place in the card
@property (nonatomic) MSBDRRect screenRect;         // ... and on the screen, as laid out (a flight's end, a restore's start)
@property (nonatomic) CFTimeInterval settledAt;     // no pick before this: a card that came in takes none until it has landed and settled
@property (nonatomic) BOOL landing;                 // a window flies into it: hidden until the flight lands
@property (nonatomic) BOOL going;                   // on its way out (its window back on the desktop)
@property (nonatomic) BOOL hovering, pressed;       // the pointer over it; a finger or a click down on it
@property (nonatomic) BOOL fingerDown;              // ... a finger's (it rises a little at the hold's time: its menu on release, a drag if it moves on)
@property (nonatomic, strong) NSArray<UIView *> *stack;   // a group's pictures behind the front one (our own windows, up to 2 more)
@property (nonatomic, strong) UILabel *badge;       // ... and its count over 3
@end
static void DMRStripLiftTo(DMRStripCard *c);
static void DMRStripCardMenu(DMRStripCard *c, NSString *how);
@implementation DMRStripCard
- (BOOL)accessibilityActivate { DMRStripPick(self, NO, @"VoiceOver's activate"); return YES; }   // (as a tap: a swap)
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    self.pressed = YES; self.fingerDown = touches.anyObject.type != UITouchTypeIndirectPointer && (event.buttonMask & UIEventButtonMaskSecondary) == 0;
    DMRStripLiftTo(self);
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [super touchesEnded:touches withEvent:event]; self.pressed = NO; self.fingerDown = NO; DMRStripLiftTo(self); }
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [super touchesCancelled:touches withEvent:event]; self.pressed = NO; self.fingerDown = NO; DMRStripLiftTo(self); }
@end
// The card's lift (the rules' motion numbers, a spring, from where it is): pressed, 0.96; the pointer over it, 1.05 and 2 pt up with a 5 degree
// tilt toward the desktop and a larger shadow (as on a Mac); else flat. Reduce Motion: no tilt, no rise (the scale's fade). A finger down: 0.96 at
// once, then at the hold's time a small rise (ready: its menu on release, a drag if it moves on) -- one animation of the lift, from where it is,
// so the press and the rise never replace each other (review of 1.8.8.4: the press recogniser's delayed rise and the card's own press were two
// animations of the same transform, the later one taking the other's place, and the release jumped to the end of whichever was left).
static void DMRStripLiftTo(DMRStripCard *c) {
    if (!c || c.going || c.landing) return;
    BOOL up = c.hovering && !c.pressed, rm = MSBReduceMotion();
    CATransform3D t = CATransform3DIdentity;
    if (c.pressed) t = CATransform3DMakeScale(kMSBDRStripPressScale, kMSBDRStripPressScale, 1);
    else if (up) {
        t.m34 = -1.0 / 500.0;
        if (!rm) t = CATransform3DTranslate(t, 0, -kMSBDRStripHoverLift, 0);
        if (!rm) t = CATransform3DRotate(t, (gRStripRight ? 1.0 : -1.0) * kMSBDRStripHoverTilt * M_PI / 180.0, 0, 1, 0);   // (its inner edge back: it turns toward the desktop)
        t = CATransform3DScale(t, kMSBDRStripHoverScale, kMSBDRStripHoverScale, 1);
    }
    if (c.pressed && c.fingerDown && !rm) {
        CATransform3D ready = CATransform3DMakeScale(kMSBDRStripHoldScale, kMSBDRStripHoldScale, 1);
        double total = kMSBDRStripHold + kMSBDRStripHoldRise;
        [UIView animateKeyframesWithDuration:total delay:0 options:UIViewKeyframeAnimationOptionBeginFromCurrentState | UIViewKeyframeAnimationOptionAllowUserInteraction animations:^{
            [UIView addKeyframeWithRelativeStartTime:0.0 relativeDuration:kMSBDRStripPressIn / total animations:^{ c.lift.transform3D = t; }];
            [UIView addKeyframeWithRelativeStartTime:kMSBDRStripHold / total relativeDuration:kMSBDRStripHoldRise / total animations:^{ c.lift.transform3D = ready; }];
        } completion:nil];
    } else MSBAnimate(kMSBDRStripHoverTime, 0, kMSBDRStripHoverDamp, UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction, ^{ c.lift.transform3D = t; }, nil);
    CALayer *sl = c.shadow.layer;
    CGFloat want = up ? kMSBDRStripHoverShadow : kMSBDRStripShadow;
    if (fabs(sl.shadowRadius - want) > 0.01) {   // (a layer property: its own animation, from where it is drawn now)
        CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"shadowRadius"];
        a.fromValue = @(sl.presentationLayer ? sl.presentationLayer.shadowRadius : sl.shadowRadius); a.toValue = @(want);
        a.duration = rm ? kMSBRMDuration : kMSBDRStripHoverTime; a.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        sl.shadowRadius = want;
        [sl addAnimation:a forKey:@"shadowRadius"];
    }
}
static void DMRStripPick(DMRStripCard *card, BOOL shift, NSString *how);
static void DMRStripTouched(void) { gRStripTouchedAt = CACurrentMediaTime(); gRStripPointerOutAt = 0; }
// A card's press: one recognizer for a finger and a pointer, from the touch going down (the rules' MSBDRStripPressFor decides: a tap, the menu on a
// held finger's release, a drag after any hold), with the pointer's secondary click (two fingers on a trackpad) and the keyboard's Shift and
// Control read at the press.
@interface DMRStripPress : UIGestureRecognizer
@property (nonatomic) CGPoint down, last, prev;            // in the strip's content (the screen as it is turned)
@property (nonatomic) CFTimeInterval downAt, lastAt, prevAt;
@property (nonatomic) BOOL pointer, secondary;
@property (nonatomic) UIKeyModifierFlags mods;
@end
@implementation DMRStripPress
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    if (self.state != UIGestureRecognizerStatePossible || touches.count != 1) { if (self.state == UIGestureRecognizerStatePossible) self.state = UIGestureRecognizerStateFailed; return; }
    UITouch *t = touches.anyObject;
    self.pointer = t.type == UITouchTypeIndirectPointer;
    self.secondary = (event.buttonMask & UIEventButtonMaskSecondary) != 0;
    self.mods = self.modifierFlags;
    CGPoint p = [t locationInView:gRStripRoot];
    self.down = self.last = self.prev = p; self.downAt = self.lastAt = self.prevAt = t.timestamp;
    self.state = UIGestureRecognizerStateBegan;
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesMoved:touches withEvent:event];
    UITouch *t = touches.anyObject;
    if (!t || self.state == UIGestureRecognizerStatePossible) return;
    self.prev = self.last; self.prevAt = self.lastAt;
    self.last = [t locationInView:gRStripRoot]; self.lastAt = t.timestamp;
    self.state = UIGestureRecognizerStateChanged;
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    UITouch *t = touches.anyObject;
    if (t) { self.prev = self.last; self.prevAt = self.lastAt; self.last = [t locationInView:gRStripRoot]; self.lastAt = t.timestamp; }
    self.state = self.state == UIGestureRecognizerStatePossible ? UIGestureRecognizerStateFailed : UIGestureRecognizerStateEnded;
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    self.state = self.state == UIGestureRecognizerStatePossible ? UIGestureRecognizerStateFailed : UIGestureRecognizerStateCancelled;
}
@end
// A card dragged out: its proxy (the card's picture, lifted) follows the touch, the grab point kept under it.
@interface DMRStripDrag : NSObject
@property (nonatomic, copy) NSString *key;
@property (nonatomic, strong) UIView *holder, *pic;        // the proxy: its shadow by a path, its picture rounded on its own layer
@property (nonatomic) double gx, gy, cw, ch, ww, wh;       // the grab point's share of the card; the card's picture's size; its window's
@end
@implementation DMRStripDrag
@end
@interface DMRStripTarget : NSObject
+ (instancetype)shared;
- (void)press:(DMRStripPress *)g;
- (void)handleTap:(UITapGestureRecognizer *)g;
- (void)handlePan:(UIPanGestureRecognizer *)g;
- (void)hover:(UIHoverGestureRecognizer *)g;
- (void)sysHover:(UIHoverGestureRecognizer *)g;
- (void)memoryWarning:(NSNotification *)n;
@end
static void DMRStripSysHoverSeen(UIHoverGestureRecognizer *g);
static void DMRStripMemoryWarning(void);
static void DMRStripPressed(DMRStripPress *g);
static void DMRStripHandleReveal(NSString *why);
@implementation DMRStripTarget
+ (instancetype)shared { static DMRStripTarget *t; static dispatch_once_t once; dispatch_once(&once, ^{ t = [DMRStripTarget new]; }); return t; }
- (void)press:(DMRStripPress *)g { DMRStripPressed(g); }
- (void)handleTap:(UITapGestureRecognizer *)g { if (g.state == UIGestureRecognizerStateEnded) DMRStripHandleReveal(@"a tap on the handle"); }
- (void)handlePan:(UIPanGestureRecognizer *)g {   // (a swipe from the edge toward the desktop)
    if (g.state != UIGestureRecognizerStateChanged && g.state != UIGestureRecognizerStateEnded) return;
    CGFloat dx = [g translationInView:g.view.superview].x;
    if (gRStripRight ? dx < -12.0 : dx > 12.0) DMRStripHandleReveal(@"a swipe from the handle");
}
- (void)hover:(UIHoverGestureRecognizer *)g {   // (the card under the pointer lifts and turns a little toward the desktop, as on a Mac)
    BOOL inside = g.state == UIGestureRecognizerStateBegan || g.state == UIGestureRecognizerStateChanged;
    DMRStripCard *c = [g.view isKindOfClass:[DMRStripCard class]] ? (DMRStripCard *)g.view : nil;
    if (inside) DMRStripTouched();
    if (!c || c.hovering == inside) return;
    c.hovering = inside;
    DMRStripLiftTo(c);
}
- (void)sysHover:(UIHoverGestureRecognizer *)g { DMRStripSysHoverSeen(g); }
- (void)memoryWarning:(NSNotification *)n { DMRStripMemoryWarning(); }
@end
static void DMRStripTick(void);
static void DMRStripRevealEnd(NSString *why);
// A touch going down outside the cards and the handle while the Window menu or the handle brought the strip out: the reveal ends (as a click on the
// desktop on a Mac), on the next turn of the main queue -- never inside the hit test. The touch itself goes on to what is under. (The design's "a tap
// outside" end, missing until the review of 1.8.8.4: under VoiceOver or Switch Control, which never end a reveal by time, it stayed out over the
// windows until a pick or Escape.)
static void DMRStripTapOutside(void) {
    static BOOL queued = NO;
    if (queued || (gRStripReveal != MSBDRStripRevealMenu && gRStripReveal != MSBDRStripRevealHandle)) return;
    queued = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        queued = NO;
        if (gRStripReveal != MSBDRStripRevealMenu && gRStripReveal != MSBDRStripRevealHandle) return;
        DMRStripRevealEnd(@"a tap outside");
        DMRStripTick();
    });
}
static UIView *DMRStripWindowHit(id self, SEL _cmd, CGPoint p, UIEvent *e) {   // (only a card takes a touch: between them it goes on to what is under)
    if (gRStripHandleTouch && !gRStripHandleTouch.hidden && gRStripHandleTouch.superview) {   // (stepped aside: the handle's small touch area alone)
        CGPoint q = [(UIView *)self convertPoint:p toView:gRStripHandleTouch];
        if ([gRStripHandleTouch pointInside:q withEvent:e]) return gRStripHandleTouch;
    }
    if (gRStripShown == MSBDRStripHidden || !gRStripRoot) return nil;
    for (DMRStripCard *c in gRStripCards.allValues) {
        if (c.hidden || c.alpha < 0.05 || !c.superview || c.going || c.landing) continue;
        CGPoint q = [(UIView *)self convertPoint:p toView:c];
        if ([c pointInside:q withEvent:e]) return c;
    }
    if (e && e.type == UIEventTypeTouches && gRStripReveal) DMRStripTapOutside();   // (a touch, not the pointer's hover or a scroll)
    return nil;
}
static UIWindow *DMRStripEnsureWindow(void) {
    if (gRStripWindow) return gRStripWindow;
    @try {
        Class base = objc_getClass("SBMainScreenActiveInterfaceOrientationWindow");
        SEL initRole = NSSelectorFromString(@"initWithRole:debugName:");
        if (!base || ![base instancesRespondToSelector:initRole]) return nil;
        Class sub = objc_getClass("MSBRecentStripWindow");
        if (!sub) {
            sub = objc_allocateClassPair(base, "MSBRecentStripWindow", 0);
            if (!sub) return nil;
            class_addMethod(sub, @selector(hitTest:withEvent:), (IMP)DMRStripWindowHit, "@@:{CGPoint=dd}@");
            objc_registerClassPair(sub);
        }
        UIWindow *w = ((id (*)(id, SEL, id, id))objc_msgSend)([sub alloc], initRole, @"SBFTraitsParticipantRoleRecordingIndicator", @"MacStatusBarRecentStrip");
        DMSnapInvalidate();
        w.backgroundColor = [UIColor clearColor];
        w.hidden = YES;
        UIView *root = [[UIView alloc] initWithFrame:w.bounds];
        root.backgroundColor = [UIColor clearColor];
        [w addSubview:root];
        UIView *slide = [[UIView alloc] initWithFrame:root.bounds];
        slide.backgroundColor = [UIColor clearColor];
        [root addSubview:slide];
        UIView *hl = [[UIView alloc] initWithFrame:CGRectZero];   // (the band's highlight for a window drag over the drop zone, behind the cards)
        hl.userInteractionEnabled = NO; hl.alpha = 0.0; hl.layer.cornerRadius = 12.0;
        if (@available(iOS 13.0, *)) hl.layer.cornerCurve = kCACornerCurveContinuous;
        [slide addSubview:hl];
        UIView *handle = [[UIView alloc] initWithFrame:CGRectZero];   // (the finger's handle: a slim tab at the edge, its touch area a little larger)
        handle.userInteractionEnabled = NO; handle.hidden = YES; handle.alpha = 0.0;
        handle.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.55]; handle.layer.cornerRadius = kMSBDRStripHandleW / 2.0;
        handle.layer.shadowColor = [UIColor blackColor].CGColor; handle.layer.shadowOpacity = 0.25; handle.layer.shadowRadius = 2.0; handle.layer.shadowOffset = CGSizeZero;
        [root addSubview:handle];
        UIView *touch = [[UIView alloc] initWithFrame:CGRectZero];
        touch.backgroundColor = [UIColor clearColor]; touch.hidden = YES;
        touch.isAccessibilityElement = YES; touch.accessibilityLabel = @"Recent Windows Strip"; touch.accessibilityHint = @"Shows the recent windows"; touch.accessibilityTraits = UIAccessibilityTraitButton;
        [touch addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:[DMRStripTarget shared] action:@selector(handleTap:)]];
        [touch addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:[DMRStripTarget shared] action:@selector(handlePan:)]];
        [root addSubview:touch];
        gRStripWindow = w; gRStripRoot = root; gRStripSlide = slide; gRStripHighlight = hl; gRStripHandle = handle; gRStripHandleTouch = touch;
        DMLog([NSString stringWithFormat:@"[recentstrip] window made: %@ frame %@", NSStringFromClass([w class]), NSStringFromCGRect(w.frame)]);
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[recentstrip] window failed: %@", e]); gRStripWindow = nil; gRStripRoot = nil; gRStripSlide = nil; }
    return gRStripWindow;
}
// The content's bounds and turn: the screen as it is seen now (this window class turns with the screen on 15; the turn is read, as the Mac
// Switcher's DMMSWTurnIn reads it). The root's transform is the turn and nothing else: each card slides in and out by its own transform inside the
// slide (DMRStripShowAs), so the turn never undoes a step aside.
static void DMRStripCardDragReturn(NSString *why, BOOL gone);
static void DMRStripTurnIn(void) {
    UIWindow *l = gRStripWindow; UIView *root = gRStripRoot, *slide = gRStripSlide;
    if (!l || !root || !slide) return;
    UIScreen *on = [UIScreen mainScreen];
    CGSize screen = on.bounds.size, win = l.bounds.size;
    id<UICoordinateSpace> scr = on.coordinateSpace;
    CGPoint o = [l convertPoint:CGPointZero toCoordinateSpace:scr], x = [l convertPoint:CGPointMake(100, 0) toCoordinateSpace:scr];
    CGFloat angle = hypot(x.x - o.x, x.y - o.y) > 50.0 ? -round(atan2(x.y - o.y, x.x - o.x) / M_PI_2) * M_PI_2 : 0;
    BOOL turned = fabs(angle) > 0.01;
    CGRect want = CGRectMake(0, 0, turned ? screen.width : win.width, turned ? screen.height : win.height);
    if (CGRectEqualToRect(root.bounds, want) && CGAffineTransformEqualToTransform(root.transform, turned ? CGAffineTransformMakeRotation(angle) : CGAffineTransformIdentity)) return;
    root.transform = CGAffineTransformIdentity;
    root.bounds = want;
    root.center = CGPointMake(win.width / 2.0, win.height / 2.0);
    root.transform = turned ? CGAffineTransformMakeRotation(angle) : CGAffineTransformIdentity;
    slide.bounds = CGRectMake(0, 0, want.size.width, want.size.height);
    slide.center = CGPointMake(want.size.width / 2.0, want.size.height / 2.0);
    gRStripLayoutSig = nil;
    if (gRStripCardDrag) DMRStripCardDragReturn(@"the iPad turned", NO);   // (a turn cuts a card drag short: back to its slot in the new layout)
}
static void DMRStripCloseCard(NSString *k);
static DMRStripCard *DMRStripCardFor(NSString *k) {
    if (!gRStripCards) gRStripCards = [NSMutableDictionary dictionary];
    DMRStripCard *c = gRStripCards[k];
    if (c) return c;
    c = [[DMRStripCard alloc] initWithFrame:CGRectZero];
    c.key = k; c.bundle = k;
    c.backgroundColor = [UIColor clearColor];
    c.exclusiveTouch = YES;   // (one card at a time: a second finger on another card is not taken)
    c.lift = [[UIView alloc] initWithFrame:CGRectZero];
    c.lift.userInteractionEnabled = NO;
    [c addSubview:c.lift];
    c.shadow = [[UIView alloc] initWithFrame:CGRectZero];
    c.shadow.userInteractionEnabled = NO;
    CALayer *sl = c.shadow.layer;
    sl.shadowColor = [UIColor blackColor].CGColor; sl.shadowOpacity = 0.32; sl.shadowRadius = kMSBDRStripShadow; sl.shadowOffset = CGSizeMake(0, 3);
    [c.lift addSubview:c.shadow];
    UIImage *img = DMRStripIsNativeKey(k) ? DMRStripNativeIcon([k substringFromIndex:7]) : DMAppIcon(k);
    if (DMRStripIsNativeKey(k)) {   // (a group's stack behind its front picture, and its count)
        NSMutableArray *st = [NSMutableArray array];
        for (int i = 0; i < kMSBDRStripStackMax - 1; i++) {
            UIView *b = [[UIView alloc] initWithFrame:CGRectZero];
            b.userInteractionEnabled = NO; b.hidden = YES;
            b.layer.cornerRadius = 7.0; b.layer.masksToBounds = YES; b.layer.contentsGravity = kCAGravityResize;
            b.backgroundColor = [UIColor colorWithWhite:0.80 alpha:1.0];
            [c.lift addSubview:b]; [st addObject:b];
        }
        c.stack = st;
        UILabel *n = [[UILabel alloc] initWithFrame:CGRectZero];
        n.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold]; n.textColor = [UIColor whiteColor]; n.textAlignment = NSTextAlignmentCenter;
        n.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55]; n.layer.cornerRadius = 9.0; n.layer.masksToBounds = YES; n.hidden = YES;
        c.badge = n;
    }
    c.pic = [[UIView alloc] initWithFrame:CGRectZero];
    c.pic.userInteractionEnabled = NO;
    CALayer *pl = c.pic.layer;
    pl.cornerRadius = 7.0; pl.masksToBounds = YES; pl.contentsGravity = kCAGravityResize;
    if (@available(iOS 13.0, *)) pl.cornerCurve = kCACornerCurveContinuous;
    c.pic.backgroundColor = DMRStripIconTint(k, img);   // (seen only while there is no picture: the layer's contents cover it)
    [c.lift addSubview:c.pic];
    c.icon = [[UIImageView alloc] initWithImage:img];
    c.icon.userInteractionEnabled = NO;
    c.icon.contentMode = UIViewContentModeScaleAspectFit;
    [c.lift addSubview:c.icon];
    if (c.badge) [c.lift addSubview:c.badge];
    DMRStripTarget *t = [DMRStripTarget shared];
    DMRStripPress *press = [[DMRStripPress alloc] initWithTarget:t action:@selector(press:)];
    press.cancelsTouchesInView = NO; press.delaysTouchesBegan = NO; press.delaysTouchesEnded = NO;
    [c addGestureRecognizer:press];
    [c addGestureRecognizer:[[UIHoverGestureRecognizer alloc] initWithTarget:t action:@selector(hover:)]];
    // (a file, text or picture dragged from an app and held over the card: UIKit's own spring loading brings its window back with no swap, so the
    //  drag's source stays on the desktop, KT's choice; the drop then goes into the window itself)
    [c addInteraction:[[UISpringLoadedInteraction alloc] initWithActivationHandler:^(UISpringLoadedInteraction *i, id<UISpringLoadedInteractionContext> ctx) {
        DMRStripCard *x = [i.view isKindOfClass:[DMRStripCard class]] ? (DMRStripCard *)i.view : nil;
        if (x) { DM_FEATURE_MARK("recent-strip-spring-load"); DMRStripPick(x, YES, @"a drag held over it"); }
    }]];
    // (VoiceOver, Switch Control, Full Keyboard Access: a button, its window's name, and the card's menu's actions)
    NSString *name = DMRStripIsNativeKey(k) ? [k substringFromIndex:7] : (DMCall(DMProxyForBundle(k), @"localizedName") ?: k);
    c.isAccessibilityElement = YES;
    c.accessibilityLabel = [NSString stringWithFormat:@"%@ window, in the strip", name];
    c.accessibilityTraits = UIAccessibilityTraitButton;
    __weak DMRStripCard *wc = c;
    c.accessibilityCustomActions = @[
        [[UIAccessibilityCustomAction alloc] initWithName:@"Bring Back" actionHandler:^BOOL(UIAccessibilityCustomAction *a) { DMRStripCard *x = wc; if (x) DMRStripPick(x, YES, @"VoiceOver's Bring Back"); return x != nil; }],
        [[UIAccessibilityCustomAction alloc] initWithName:@"Close Window" actionHandler:^BOOL(UIAccessibilityCustomAction *a) { DMRStripCard *x = wc; if (x) DMRStripCloseCard(x.key); return x != nil; }] ];
    gRStripCards[k] = c;
    return c;
}
// A card's picture: the window's picture as its picture layer's contents (none yet: the tinted card with the icon).
static void DMRStripCardPicture(DMRStripCard *c) {
    NSArray<DMNativeWindow *> *members = DMRStripIsNativeKey(c.key) ? gRStripGroups[c.key] : nil;
    UIView *p = gRStripPics[members ? DMRStripNativePicKey(members.firstObject) : c.key];
    id contents = p.layer.contents;
    if (c.pic.layer.contents != contents) c.pic.layer.contents = contents;
    if (!members) return;
    NSUInteger n = members.count;
    for (NSUInteger i = 0; i < c.stack.count; i++) {   // (the ones behind: lower and smaller, the rules' stack)
        UIView *b = c.stack[i];
        b.hidden = i + 1 >= (NSUInteger)MSBDRStripStackShown((int)n);
        if (b.hidden) continue;
        b.frame = DMRStripCGRect(MSBDRStripStackRect(DMRStripRectOf(c.picRect), (int)i + 1));
        b.layer.contents = gRStripPics[DMRStripNativePicKey(members[i + 1])].layer.contents;
        [c.lift insertSubview:b belowSubview:(i ? c.stack[i - 1] : c.pic)];
    }
    c.badge.hidden = !MSBDRStripStackBadge((int)n);
    if (!c.badge.hidden) {
        c.badge.text = [NSString stringWithFormat:@"%lu", (unsigned long)n];
        c.badge.frame = CGRectMake(CGRectGetMaxX(c.picRect) - 22.0, CGRectGetMinY(c.picRect) - 6.0, 26.0, 18.0);
    }
    c.accessibilityLabel = [NSString stringWithFormat:@"%@, %lu window%@, in the strip", [c.key substringFromIndex:7], (unsigned long)n, n == 1 ? @"" : @"s"];
}
static void DMRStripCardPlace(DMRStripCard *c, MSBDRRect r) {
    CGFloat icon = 26.0;
    CGRect pr = DMRStripCGRect(r);
    CGRect ir = CGRectMake(CGRectGetMinX(pr) - 6.0, CGRectGetMaxY(pr) - icon + 8.0, icon, icon);   // (the app's icon over the picture's lower left corner)
    CGRect all = CGRectUnion(pr, ir);
    c.bounds = CGRectMake(0, 0, all.size.width, all.size.height);   // (bounds and centre: right whatever its slide's transform is now)
    c.center = CGPointMake(CGRectGetMidX(all), CGRectGetMidY(all));
    c.screenRect = r;
    c.picRect = CGRectOffset(pr, -all.origin.x, -all.origin.y);
    c.lift.bounds = c.bounds; c.lift.center = CGPointMake(all.size.width / 2.0, all.size.height / 2.0);
    c.shadow.frame = c.picRect;
    c.shadow.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:c.shadow.bounds cornerRadius:7.0].CGPath;
    c.pic.frame = c.picRect;
    c.icon.frame = CGRectOffset(ir, -all.origin.x, -all.origin.y);
    BOOL hc = UIAccessibilityDarkerSystemColorsEnabled();   // (Increase Contrast: a 1 pt outline, drawn by the picture's own layer)
    c.pic.layer.borderWidth = hc ? 1.0 : 0.0;
    if (hc) c.pic.layer.borderColor = [UIColor colorWithWhite:[UIScreen mainScreen].traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? 1.0 : 0.0 alpha:0.45].CGColor;
    DMRStripCardPicture(c);
}
static void DMRStripCardRefresh(NSString *k) {   // (a picture came: its card shows it; one of our own windows': its app's card, in its stack)
    if ([k hasPrefix:@"nw:"]) { for (NSString *ck in gRStripGroups) { DMRStripCard *g = gRStripCards[ck]; if (g) DMRStripCardPicture(g); } return; }
    DMRStripCard *c = gRStripCards[k];
    if (c) DMRStripCardPicture(c);
}
// The strip's offset of a card while away: past its side's edge (Reduce Motion: a fade, with the tiny scale).
static CGAffineTransform DMRStripAway(void) {
    if (MSBReduceMotion()) return CGAffineTransformMakeScale(kMSBRMScale, kMSBRMScale);
    CGFloat d = gRStripBand.w + 24.0;
    return CGAffineTransformMakeTranslation(gRStripRight ? d : -d, 0);
}
// A card leaves (its window comes back, or it fell past the cap, or its window closed): into the window's flight (a short fade as the window
// grows out of it) or shrinking away; the others close the gap at the next layout. Not the card being dragged out: its view carries the press
// recogniser that drives the drag (DMRStripPress), and taken off the window UIKit cancels it at once -- the drag returned inside its own begin, so
// no card could ever be dragged out (1.8.8.4's first device pass, iPadOS 15.6.1, Aerial). It stays, hidden, out of the layout, until the drag ends: then the drag's
// end (DMRStripCardDragEnd, DMRStripCardDragReturn) lays the strip out again and it goes, or comes back to its slot.
static void DMRStripCardGoes(NSString *k, BOOL intoWindow) {
    DMRStripCard *c = gRStripCards[k];
    if (!c || (gRStripCardDrag && [k isEqualToString:gRStripDraggingKey ?: @""])) return;
    [gRStripCards removeObjectForKey:k];
    c.going = YES;
    if (!c.superview || c.alpha < 0.01 || gRStripShown == MSBDRStripHidden) { [c removeFromSuperview]; return; }
    MSBAnimate(intoWindow ? 0.15 : 0.18, 0, 0, UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState, ^{
        c.alpha = 0.0;
        c.lift.transform = intoWindow ? CGAffineTransformMakeScale(1.08, 1.08) : CGAffineTransformMakeScale(0.8, 0.8);
    }, ^(BOOL f) { [c removeFromSuperview]; });
}
// A window flies into this card: hidden until it lands, then shown where it landed (its fade in with the flight's last part, from the flight's own
// delay), with a small settle (DMRStripLanded).
static void DMRStripCardLanding(DMRStripCard *c, double delay) {
    c.landing = YES;
    c.settledAt = CACurrentMediaTime() + delay + 0.36 + kMSBDRStripSettle;
    c.transform = CGAffineTransformIdentity;   // (it does not slide in with the others: the flight brings it)
    c.alpha = 0.0;
    c.lift.transform = CGAffineTransformMakeScale(kMSBDRStripSettleScale, kMSBDRStripSettleScale);
    MSBAnimate(0.16, delay + 0.20, 0, UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction, ^{ c.alpha = 1.0; }, nil);
}
// The cards for items, at the rules' places (sig: what they are laid out for; the same: nothing is done). New ones come in (scale and fade, 40 ms
// apart) unless a flight brings them; moved ones spring to their places; ones not in items any more go.
static void DMRStripLayoutCards(NSArray<NSString *> *items, NSDictionary<NSString *, UIView *> *stageOf, CGSize sc, MSBDRRect usable, BOOL animated) {
    int n = (int)MIN(items.count, (NSUInteger)kMSBDRStripMax);
    double aspect[kMSBDRStripMax]; MSBDRRect cards[kMSBDRStripMax];
    // (and the card a drag holds out of the layout, if any: when the drag ends the layout is done again and that card goes or comes back to its
    //  slot -- with the same cards left, the same signature would keep a held card, hidden, after its window came back)
    NSMutableString *sig = [NSMutableString stringWithFormat:@"%.0fx%.0f %.0f,%.0f,%.0f,%.0f %d gap %d held %@", sc.width, sc.height, usable.x, usable.y, usable.w, usable.h, gRStripRight, gRStripGapAt, gRStripCardDrag ? gRStripDraggingKey : @"-"];
    for (int i = 0; i < n; i++) {
        NSString *k = items[(NSUInteger)i];
        UIView *st = stageOf[k] ?: gRStripGroups[k].firstObject;
        NSValue *keptPlace = gRStripGhosts[k][@"place"] ?: gRStripGone[k][@"place"];
        CGRect place = st ? DMRStripPlaceOf(st).CGRectValue : (keptPlace ? keptPlace.CGRectValue : CGRectNull);
        if (st && DMActiveEngine() == DMEngineAerial && ![st isKindOfClass:[DMNativeWindow class]]) { CGRect w = DMSnapWindowOfFrame(st, place); if (!CGRectIsNull(w)) place = w; }   // (the window as drawn: Aerial 5's stage has margins)
        aspect[i] = place.size.height > 1.0 ? place.size.width / place.size.height : 0.0;
        [sig appendFormat:@" %@:%.2f:%lu", k, aspect[i], (unsigned long)gRStripGroups[k].count];   // (a group's count: its stack)
    }
    if ([sig isEqualToString:gRStripLayoutSig ?: @""]) return;
    gRStripLayoutSig = [sig copy];
    gRStripLayouts++;
    MSBDRRect gapRect = { 0, 0, 0, 0 };
    n = MSBDRStripLayoutGap(sc.width, sc.height, usable, gRStripRight, n, aspect, gRStripGapAt, &gRStripBand, cards, &gapRect);
    gRStripSpan = MSBDRStripCardsSpan(gRStripBand, cards, n);
    if (gRStripGapAt >= 0 && gapRect.h > 0) {   // (the open slot counts as the cards' part: a window over it covers it)
        double top = n ? MIN(gRStripSpan.y, gapRect.y - 8.0) : gapRect.y - 8.0, bottom = n ? MAX(MSBDRMaxY(gRStripSpan), MSBDRMaxY(gapRect) + 10.0) : MSBDRMaxY(gapRect) + 10.0;
        gRStripSpan = (MSBDRRect){ gRStripBand.x, top, gRStripBand.w, bottom - top };
    }
    NSMutableSet<NSString *> *keep = [NSMutableSet set];
    int fresh = 0;
    for (int i = 0; i < n; i++) {
        NSString *k = items[(NSUInteger)i];
        [keep addObject:k];
        DMRStripCard *c = DMRStripCardFor(k);
        MSBDRRect r = cards[i];
        BOOL isNew = c.superview != gRStripSlide;
        if (isNew) {
            [gRStripSlide addSubview:c];
            DMRStripCardPlace(c, r);
            c.transform = gRStripShown == MSBDRStripHidden ? DMRStripAway() : CGAffineTransformIdentity;
            if (c.landing) { c.alpha = 0.0; continue; }   // (its flight shows it)
            if (!animated || gRStripShown == MSBDRStripHidden) { c.alpha = 1.0; c.settledAt = 0; continue; }
            c.alpha = 0.0; c.lift.transform = CGAffineTransformMakeScale(0.85, 0.85);
            c.settledAt = CACurrentMediaTime() + fresh * kMSBDRStripInsertStep + kMSBDRStripSettle;
            MSBAnimate(kMSBDRStripMoveTime, fresh * kMSBDRStripInsertStep, kMSBDRStripInsertDamp, UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction, ^{
                c.alpha = 1.0; c.lift.transform = CGAffineTransformIdentity;
            }, nil);
            fresh++;
            continue;
        }
        if (fabs(c.screenRect.x - r.x) < 0.5 && fabs(c.screenRect.y - r.y) < 0.5 && fabs(c.screenRect.w - r.w) < 0.5 && fabs(c.screenRect.h - r.h) < 0.5) continue;
        if (animated) MSBAnimate(kMSBDRStripMoveTime, 0, kMSBDRStripMoveDamp, UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction, ^{ DMRStripCardPlace(c, r); }, nil);
        else DMRStripCardPlace(c, r);
    }
    for (NSString *k in [gRStripCards allKeys]) if (![keep containsObject:k]) DMRStripCardGoes(k, NO);
    gRStripItems = [items subarrayWithRange:NSMakeRange(0, (NSUInteger)n)];
    NSMutableArray *ax = [NSMutableArray array];   // (VoiceOver, Switch Control, Full Keyboard Access: the strip is a container of its cards, top to bottom)
    for (NSString *k in gRStripItems) if (gRStripCards[k]) [ax addObject:gRStripCards[k]];
    gRStripSlide.accessibilityElements = ax;
}

// ---- the list now, and the strip laid out for it ----
// This desktop's windows off it, by their entry times (a window with none is seeded), and the kept cards (and the ones being decided);
// stageOf: key -> its window; anyShown: a window of the engine is on screen.
static NSArray<NSString *> *DMRStripCollect(NSDictionary<NSString *, UIView *> **stageOfOut, BOOL *anyShownOut) {
    NSArray<UIView *> *stages = DMAerialStages();
    NSMutableArray<NSString *> *off = [NSMutableArray arrayWithCapacity:stages.count];
    NSMutableDictionary<NSString *, NSNumber *> *at = [NSMutableDictionary dictionaryWithCapacity:stages.count];
    NSMutableDictionary<NSString *, UIView *> *stageOf = [NSMutableDictionary dictionaryWithCapacity:stages.count];
    BOOL anyShown = NO; int seed = 0;
    for (UIView *st in [stages reverseObjectEnumerator]) {   // (from the front one back)
        NSString *k = DMStageBundle(st);
        if (!k.length || stageOf[k]) continue;
        stageOf[k] = st;
        if (DMRStripStageOnScreen(st)) anyShown = YES;
        if (!DMRStripOffDesktop(st) || gRStripLeaving[k] || [k isEqualToString:gRStripDraggingKey ?: @""]) continue;
        double t = 0; int why = 0;
        if (!DMRStripEntryOf(st, &t, &why)) {
            NSArray *p = objc_getAssociatedObject(st, kRStripPendingKey);   // (a burst's window: its time is set, its flight not here yet)
            if (p.count == 2) t = [p[0] doubleValue];
            else {   // (found minimized: before the switch went on, by a respring with no time saved; older than every real one, in the stage order)
                t = MSBDRStripEntryAt(MSBDRStripWhySeeded, DMRStripClock(), NAN, seed);
                DMRStripSetEntry(st, t, MSBDRStripWhySeeded);
            }
        }
        seed++;
        [off addObject:k]; at[k] = @(t);
    }
    // (our own windows of this desktop in it, or on their way in: one card per app, its time its most recent window's)
    NSMutableDictionary<NSString *, NSMutableArray<DMNativeWindow *> *> *groups = [NSMutableDictionary dictionary];
    for (DMNativeWindow *nw in gNativeWindows) {
        BOOL going = objc_getAssociatedObject(nw, kRStripGoingKey) != nil;
        if (!going && (!nw.hidden || !nw.dm_wasMinimized)) { if (!nw.hidden && nw.superview && nw.alpha > 0.05) anyShown = YES; continue; }
        if (DMRStripNativeAway(nw)) continue;   // (minimized on another of the Mac Switcher's desktops: that desktop's strip, as the engines' windows)
        double t = 0; int why = 0;
        if (!DMRStripEntryOf(nw, &t, &why)) { t = MSBDRStripEntryAt(MSBDRStripWhySeeded, DMRStripClock(), NAN, seed++); DMRStripSetEntry(nw, t, MSBDRStripWhySeeded); }
        NSString *k = DMRStripNativeKey(nw);
        if (gRStripLeaving[k]) continue;
        // (a card dragged out: out of the list as the engines' windows are, but its windows kept in its group -- its drop shows them, and with none
        //  found the drop took them for gone, the window never came out and the held card stayed hidden in its slot: review of the 1.8.8.4 fix round)
        if (!groups[k]) { groups[k] = [NSMutableArray array]; if (![k isEqualToString:gRStripDraggingKey ?: @""]) [off addObject:k]; }
        [groups[k] addObject:nw];
        if (!at[k] || at[k].doubleValue < t) at[k] = @(t);
    }
    for (NSString *k in groups) [groups[k] sortUsingComparator:^NSComparisonResult(DMNativeWindow *a, DMNativeWindow *b) { double x = 0, y = 0; DMRStripEntryOf(a, &x, NULL); DMRStripEntryOf(b, &y, NULL); return x > y ? NSOrderedAscending : (x < y ? NSOrderedDescending : NSOrderedSame); }];
    gRStripGroups = groups;
    for (NSDictionary<NSString *, NSDictionary *> *kept in @[gRStripGone ?: @{}, gRStripGhosts ?: @{}])
        for (NSString *k in kept) if (!stageOf[k] && !gRStripLeaving[k] && !at[k] && ![k isEqualToString:gRStripDraggingKey ?: @""]) { [off addObject:k]; at[k] = kept[k][@"at"] ?: @(kMSBDRStripSeedAt); }
    if (stageOfOut) *stageOfOut = stageOf;
    if (anyShownOut) *anyShownOut = anyShown;
    return MSBDRStripList(off, at);
}
// iPadOS's Today View on the Home Screen (slid in over page 1, or kept there: Home Screen & Dock > Keep on Home Screen) lies at the left, where the
// strip is with the Dock not at Left: the strip keeps off it, as off the App Library. SpringBoard's own answers, each asked only where it has
// one with a BOOL's type (the Home Screen's icon manager and its root folder view; a device row reads which ones 15.6.1 has).
static BOOL DMRStripBoolGetter(Class c, SEL s) {   // (c has a BOOL getter s)
    Method m = c ? class_getInstanceMethod(c, s) : NULL;
    const char *t = m ? method_getTypeEncoding(m) : NULL;
    return t && (t[0] == 'B' || t[0] == 'c') && !strcmp(t + 1, "16@0:8");
}
static BOOL DMRStripTodayShown(void) {   // (each class's getters looked up once: nothing allocated or looked up again at rest)
    static Class mc = Nil, rc = Nil; static BOOL mok[2], rok[2]; static SEL ms[2], rs[2];
    if (!ms[0]) { ms[0] = NSSelectorFromString(@"isOverlayTodayViewVisible"); ms[1] = NSSelectorFromString(@"isTodayOverlayPresented");
                  rs[0] = NSSelectorFromString(@"isSidebarEffectivelyVisible"); rs[1] = NSSelectorFromString(@"isSidebarVisible"); }
    id mgr = DMCall(DMCall(objc_getClass("SBIconController"), @"sharedInstance"), @"iconManager");
    if (mgr && object_getClass(mgr) != mc) { mc = object_getClass(mgr); for (int i = 0; i < 2; i++) mok[i] = DMRStripBoolGetter(mc, ms[i]); }
    for (int i = 0; mgr && i < 2; i++) if (mok[i] && ((BOOL (*)(id, SEL))objc_msgSend)(mgr, ms[i])) return YES;
    id rfv = mgr ? DMCall(DMCall(mgr, @"rootFolderController"), @"rootFolderView") : nil;
    if (rfv && object_getClass(rfv) != rc) { rc = object_getClass(rfv); for (int i = 0; i < 2; i++) rok[i] = DMRStripBoolGetter(rc, rs[i]); }
    for (int i = 0; rfv && i < 2; i++) if (rok[i] && ((BOOL (*)(id, SEL))objc_msgSend)(rfv, rs[i])) return YES;
    return NO;
}
// Edit Home Screen (jiggle mode) on: SpringBoard's icon manager asked as Desktop.h's DMDesktopEditing asks it -- the strip's own copy, so a crash in
// it is the strip's (the crash map: recentStrip), never the desktop icons'.
static BOOL DMRStripHomeEditing(void) {
    id im = DMCall(DMSBManager("SBIconController"), @"iconManager");
    return [im respondsToSelector:@selector(isEditing)] && ((BOOL (*)(id, SEL))objc_msgSend)(im, @selector(isEditing));
}
// Nothing of the system's or ours over the windows (the window cards' and the menus' readings).
static BOOL DMRStripCalm(void) {
    if (!DMScreenOnAndUnlocked() || DMSwitcherVisible() || gMSWOpen || gMSWClosing || !DMMSWSessionIdle()) return NO;
    if (gWindowsHiddenForLibrary || gHomeMenuOpen || gDockMenuOpen || gSoftKeyboardH >= 100.0) return NO;
    if (DMActiveEngine() == DMEngineZetsu && gZetsuHiddenForSwitcherFlag) return NO;
    if (DMActiveEngine() == DMEngineMilkyWay && gMilkyWayHiddenForSwitcher) return NO;
    if (MSBDGuidedAccessActive() || DMLibraryVisible() || DMSpotlightShown() || DMCoverSheetShown()) return NO;
    if (DMRStripHomeEditing()) return NO;   // (Edit Home Screen, jiggle mode: the icons dragged to the edge are not under the cards; the band stays, review of 1.8.8.4)
    if (MSBDRStripTodayKeepsOff(!gRStripRight && DMRStripTodayShown(), gRStripRight)) return NO;   // (the Today View at its side: the strip keeps off its widgets)
    return YES;
}
static void DMRStripWatchMemory(void) {   // (once: a memory warning lets go of the pictures no card shows, DMRStripMemoryWarning)
    static BOOL on = NO;
    if (on) return;
    on = YES;
    [[NSNotificationCenter defaultCenter] addObserver:[DMRStripTarget shared] selector:@selector(memoryWarning:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
}
// A card dragged out holds the strip while its drag lives: it counts as one of the strip's (out of the list and its layout: the gap closes), so
// the last card dragged out does not leave the strip with nothing to show -- stepping aside cuts a card drag short (DMRStripShowAs).
static BOOL DMRStripDragHolds(void) { return gRStripCardDrag != nil; }
// The list read again and the cards laid out for it (YES: laid out; NO: nothing to show, or the strip cannot show now: the cards stay as they were).
static BOOL DMRStripRelayout(BOOL animated) {
    NSDictionary<NSString *, UIView *> *stageOf = nil; BOOL anyShown = NO;
    gRStripList = DMRStripCollect(&stageOf, &anyShown);
    gRStripStageOf = stageOf; gRStripAnyShown = anyShown;
    gRStripCalmNow = (gRStripList.count || gRStripDropTarget || DMRStripDragHolds()) && DMRStripCalm();   // (nothing in it, no window dragged to it and no card dragged out: nothing more is read)
    gRStripFrontNow = gRStripCalmNow && DMDesiredWindowLevel() > 10.0;   // (above the apps: not behind a full-screen app, as DMWindowsInFront)
    if (!gRStripCalmNow || !gRStripFrontNow) {
        if (!gRStripList.count && gRStripCards.count) { for (NSString *k in [gRStripCards allKeys]) DMRStripCardGoes(k, NO); gRStripItems = @[]; gRStripLayoutSig = nil; }
        return NO;
    }
    CGSize sc = [UIScreen mainScreen].bounds.size;
    // (the desktop below the menu bar and above the Dock: read again for a new screen shape, a Dock change, or once a second)
    static CGRect u; static CGSize uFor; static unsigned uDock = ~0u, uPlace = ~0u; static CFTimeInterval uAt = -10;
    CFTimeInterval now = CACurrentMediaTime();
    if (!CGSizeEqualToSize(uFor, sc) || uDock != gDMDockGen || uPlace != gDMDockPlaceGen || now - uAt > 1.0) { u = DMUsableArea(); uFor = sc; uDock = gDMDockGen; uPlace = gDMDockPlaceGen; uAt = now; }
    MSBDRRect usable = DMRStripRectOf(u);
    gRStripRight = MSBDRStripOnRight(DMDockSideNow(sc) == MSBDDockLeft);
    gRStripFit = MSBDRStripFit(sc.width, sc.height, usable);
    NSArray<NSString *> *items = MSBDRStripShown(gRStripList, (NSUInteger)gRStripFit);
    if ((!items.count && !gRStripDropTarget && !DMRStripDragHolds()) || !DMRStripEnsureWindow()) return NO;
    DMRStripTurnIn();
    DMRStripLayoutCards(items, stageOf, sc, usable, animated);
    DMRStripWatchMemory();
    return gRStripItems.count > 0 || gRStripDropTarget || DMRStripDragHolds();
}

// ---- the Home Screen's band ----
// While the switch is on and the strip can run, every Home Screen page keeps the band free on the strip's side (KT's choice: also with no card, so the
// icons move once, when the switch goes on): each page's icon list is placed beside it by the Dock part's page frame hook (dock/Dock.x
// MSBDHomeStripRoom, through dlsym: two-sided with a side Dock's room, the layout's shape kept, Edit Home Screen's buttons off it too); with the
// Dock part not loaded, by our own same hook (never both). The desktop's files and sticky notes are shown beside it (Desktop.h -dm_area), their
// saved places untouched. The pages are placed again only when the switch, the side or the band's width changes, never as the strip shows or hides.
static IMP gRStripTwinListFrameOrig, gRStripTwinLayoutOrig;
static BOOL gRStripTwinHooked = NO, gRStripTwinAsking = NO;
static CGRect DMRStripTwinListFrame(id self, SEL _cmd, CGRect page, unsigned long long index) {   // (our own hook of the pages' list frames: the band alone)
    CGRect f = ((CGRect (*)(id, SEL, CGRect, unsigned long long))gRStripTwinListFrameOrig)(self, _cmd, page, index);
    if (!(gRStripHomeRoom > 0.0) || gRStripTwinAsking || ([(UIView *)self window] && [(UIView *)self window].screen != [UIScreen mainScreen])) return f;
    SEL at = NSSelectorFromString(@"iconListViewAtIndex:"), ins = NSSelectorFromString(@"layoutInsetsForOrientation:"), lo = NSSelectorFromString(@"layoutOrientation");
    if (![self respondsToSelector:at]) return f;
    gRStripTwinAsking = YES;   // (nothing below may come back here)
    UIView *list = ((id (*)(id, SEL, unsigned long long))objc_msgSend)(self, at, index);
    if (![list respondsToSelector:ins]) list = ((id (*)(id, SEL, unsigned long long))objc_msgSend)(self, at, 0);   // (a page not made yet: the first page's layout)
    Method m = [list isKindOfClass:[UIView class]] ? class_getInstanceMethod(object_getClass(list), ins) : NULL;
    BOOL known = m && !strcmp(method_getTypeEncoding(m) ?: "", "{UIEdgeInsets=dddd}24@0:8q16");
    UIEdgeInsets i = UIEdgeInsetsZero;
    if (known) {
        long long o = [list respondsToSelector:lo] ? ((long long (*)(id, SEL))objc_msgSend)(list, lo) : 1;
        i = ((UIEdgeInsets (*)(id, SEL, long long))objc_msgSend)(list, ins, o >= 1 && o <= 4 ? o : 1);
    }
    gRStripTwinAsking = NO;
    if (!known) return f;
    double fl = 0, fr = 0;
    MSBDDockSideHomeFree(i.left, i.right, [(UIView *)self effectiveUserInterfaceLayoutDirection] == UIUserInterfaceLayoutDirectionRightToLeft, &fl, &fr);
    return MSBDHomeListFrameTwoSided(f, MSBDDockBottom, 0.0, gRStripHomeRight, gRStripHomeRoom, fl, fr);
}
// (... and Edit Home Screen's buttons off the band, from SpringBoard's own frame each time: the frame it last had from SpringBoard is kept, as the
//  Dock part's DMDockSideHomeEditButtons keeps it, so with the band gone a button is given back its own place -- a layout of SpringBoard's that
//  leaves the button alone had kept it the band's width over, review of 1.8.8.4 -- and a layout that leaves it alone never moves it twice)
static const void *kRStripTwinButtonBase = &kRStripTwinButtonBase, *kRStripTwinButtonSet = &kRStripTwinButtonSet;
static void DMRStripTwinLayout(id self, SEL _cmd) {
    ((void (*)(id, SEL))gRStripTwinLayoutOrig)(self, _cmd);
    UIView *rfv = self; CGSize b = rfv.bounds.size;
    BOOL band = gRStripHomeRoom > 0.0;
    for (NSString *k in @[@"widgetButton", @"doneButton"]) {
        UIView *v = DMCall(rfv, k);
        if (![v isKindOfClass:[UIView class]] || v.superview != rfv) continue;
        NSValue *set = objc_getAssociatedObject(v, kRStripTwinButtonSet), *base = objc_getAssociatedObject(v, kRStripTwinButtonBase);
        if (!band && !set) continue;   // (never moved by us: nothing to give back)
        CGRect apple = set && base && CGRectEqualToRect(v.frame, set.CGRectValue) ? base.CGRectValue : v.frame;   // (moved by us and left so: SpringBoard's is the kept one)
        CGRect f = apple;
        if (band && !gRStripHomeRight && CGRectGetMinX(f) < gRStripHomeRoom) f.origin.x += gRStripHomeRoom;
        else if (band && gRStripHomeRight && CGRectGetMaxX(f) > b.width - gRStripHomeRoom) f.origin.x -= gRStripHomeRoom;
        if (CGRectEqualToRect(f, v.frame)) continue;
        objc_setAssociatedObject(v, kRStripTwinButtonBase, [NSValue valueWithCGRect:apple], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v, kRStripTwinButtonSet, [NSValue valueWithCGRect:f], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        v.frame = f;
    }
}
static BOOL DMRStripTwinHook(void) {
    if (gRStripTwinHooked) return YES;
    static BOOL tried = NO;
    if (tried) return NO;
    tried = YES;
    Class rv = objc_getClass("SBRootFolderView");
    SEL lfs = NSSelectorFromString(@"_iconListFrameForPageRect:atIndex:"), lays = NSSelectorFromString(@"_layoutSubviews");
    Method lf = rv ? class_getInstanceMethod(rv, lfs) : NULL, lay = rv ? class_getInstanceMethod(rv, lays) : NULL;
    if (!lf || strcmp(method_getTypeEncoding(lf) ?: "", "{CGRect={CGPoint=dd}{CGSize=dd}}56@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16Q48")) {
        DMLog(@"[recentstrip] the Home Screen's page frames are not as expected here: its icons stay where they are (the strip steps aside on the Home Screen)");
        return NO;
    }
    MSHookMessageEx(rv, lfs, (IMP)DMRStripTwinListFrame, &gRStripTwinListFrameOrig);
    if (lay && !strcmp(method_getTypeEncoding(lay) ?: "", "v16@0:8")) MSHookMessageEx(rv, lays, (IMP)DMRStripTwinLayout, &gRStripTwinLayoutOrig);
    gRStripTwinHooked = YES;
    DM_FEATURE_MARK("recent-strip-home-twin");
    DMLog(@"[recentstrip] the Dock part is not loaded: the Home Screen's band by our own page frame hook");
    return YES;
}
static void DMRStripTwinRelayout(void) {   // (SpringBoard's own pass for its pages, in a short animation, as the Dock part's DMDockSideHomeRelayout)
    UIView *rfv = DMCall(DMCall(DMCall(DMCall(objc_getClass("SBIconController"), @"sharedInstance"), @"iconManager"), @"rootFolderController"), @"rootFolderView");
    SEL upd = NSSelectorFromString(@"_updateIconListFrames");
    Method m = [rfv isKindOfClass:[UIView class]] ? class_getInstanceMethod(object_getClass(rfv), upd) : NULL;
    if (!m || strcmp(method_getTypeEncoding(m) ?: "", "v16@0:8")) return;
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        ((void (*)(id, SEL))objc_msgSend)(rfv, upd);
        [rfv setNeedsLayout]; [rfv layoutIfNeeded];
    } completion:nil];
}
// Asked every tick (a few numbers): the band's width and side as the switch, the screen and the Dock say now; a change is handed on once.
__attribute__((noinline)) static void DMRStripHomeBandStep(void) {
    BOOL on = DMRStripOn();
    static double handed = 0.0; static BOOL handedRight = NO;   // (what was handed on last, kept or not: asked once per change; 0: no band)
    if (MSBDRStripBandIdle(on, handed)) return;   // (off with no band handed on: nothing read or handed, the tick's off path as before the band)
    CGSize sc = [UIScreen mainScreen].bounds.size;
    double room = MSBDRStripHomeRoom(on, sc.width, sc.height);
    BOOL right = MSBDRStripOnRight(DMDockSideNow(sc) == MSBDDockLeft);
    if (!MSBDRStripBandHandsOn(room, handed, right, handedRight)) return;
    static int (*dockRoom)(double, int) = NULL; static int asked = 0;
    if (!dockRoom && asked < 40) { asked++; dockRoom = (int (*)(double, int))dlsym(RTLD_DEFAULT, "MSBDHomeStripRoom"); }   // (the Dock part: loaded after us at a start)
    if (!dockRoom && room > 0.0 && asked < 40 && !gRStripTwinHooked) return;   // (the Dock part may still come: asked again at the next tick, 8 s at most)
    BOOL kept = NO;
    if (dockRoom) kept = dockRoom(room, right) != 0;
    else if (room > 0.0 ? DMRStripTwinHook() : gRStripTwinHooked) { gRStripHomeRoom = room; gRStripHomeRight = right; DMRStripTwinRelayout(); kept = room > 0.0; }
    gRStripHomeRoom = room; gRStripHomeRight = right; handed = room; handedRight = right;
    gRStripHomeBand = kept && room > 0.0;
    if (gRStripHomeBand) DM_FEATURE_MARK("recent-strip-home-band");
    DMLog([NSString stringWithFormat:@"[recentstrip] the Home Screen %@ (%@)", gRStripHomeBand ? [NSString stringWithFormat:@"keeps a band of %.0f pt free at its %@", room, right ? @"right" : @"left"] : @"keeps no band",
           dockRoom ? @"the Dock part's page frames" : gRStripTwinHooked ? @"our own page frames" : @"no page frames to place"]);
    if (gDesktop) [gDesktop dm_placeAgain];   // (the desktop's files and notes beside it, or back)
}
// The desktop's free area beside the band (Desktop.h -dm_area; the band on the screen, the desktop's view being the screen's): as it is with none.
// Its side from the screen as it is now, as the pages take theirs from their own shape (a turn with the Dock at Left places the files once; the
// side of the band's last step was the old shape's for one pass, review of 1.8.8.4).
__attribute__((noinline)) static CGRect DMRStripHomeAreaBeside(CGRect area) {
    if (!gRStripHomeBand || !(gRStripHomeRoom > 0.0) || CGRectIsNull(area)) return area;
    CGSize sc = [UIScreen mainScreen].bounds.size;
    BOOL right = MSBDRStripOnRight(DMDockSideNow(sc) == MSBDDockLeft);
    MSBDRRect band = { right ? sc.width - gRStripHomeRoom : 0.0, 0.0, gRStripHomeRoom, sc.height };
    return DMRStripCGRect(MSBDRStripAreaBeside(DMRStripRectOf(area), band, right));
}
__attribute__((noinline)) static BOOL DMRStripHomeBandOn(void) { return gRStripHomeBand && gRStripHomeRoom > 0.0; }

// ---- showing and stepping aside ----
static void DMRStripSysHoverUpdate(BOOL want);
static void DMRStripCardDragReturn(NSString *why, BOOL gone);
// Out from the edge (a spring, the cards 25 ms apart top to bottom) or aside past it (ease in, all at once); with Reduce Motion a fade.
static void DMRStripShowAs(MSBDRStripShow show, NSString *why) {
    MSBDRStripShow was = gRStripShown;
    if (show == was) return;
    gRStripShown = show;
    // (a hide cuts a card drag short first, before the cards that step aside are gathered: the card the drag held comes back to its slot and steps
    //  aside with the others -- gathered first, it stayed out, shown, while the window stayed up for the handle: review of the 1.8.8.4 fix round)
    if (show == MSBDRStripHidden) { if (gRStripCardDrag) DMRStripCardDragReturn([NSString stringWithFormat:@"the strip steps aside: %@", why], NO); }
    UIWindow *w = gRStripWindow;
    NSMutableArray<DMRStripCard *> *cards = [NSMutableArray array];
    for (NSString *k in gRStripItems) { DMRStripCard *c = gRStripCards[k]; if (c.superview == gRStripSlide) [cards addObject:c]; }
    if (show == MSBDRStripHidden) {
        DMRStripKeysTake(NO);
        if (!w || w.hidden) return;
        DMLog([NSString stringWithFormat:@"[recentstrip] steps aside (%@)", why]);
        if (!cards.count) { if (!DMRStripHandleWanted()) w.hidden = YES; return; }
        __block NSUInteger left = cards.count;
        for (DMRStripCard *c in cards)
            MSBAnimate(kMSBDRStripAsideTime, 0, 0, UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState, ^{ c.transform = DMRStripAway(); if (MSBReduceMotion()) c.alpha = 0.0; }, ^(BOOL f) {
                if (--left || gRStripShown != MSBDRStripHidden) return;
                if (!DMRStripHandleWanted()) w.hidden = YES;   // (the handle alone keeps it up)
                for (DMRStripCard *x in cards) if (!x.landing && !x.going) x.alpha = 1.0;
            });
        return;
    }
    DM_FEATURE_MARK("recent-strip-shown");
    DMLog([NSString stringWithFormat:@"[recentstrip] %@ (%@): %@", show == MSBDRStripOverWindows ? @"comes out over the windows" : @"shows on the desktop", why, [gRStripItems componentsJoinedByString:@", "]]);
    if (!w) return;
    CGFloat level = DMDesiredWindowLevel() + 0.5;   // (just above the windows: over every engine window, under the Dock's floor, Finder and our menus)
    if (fabs(w.windowLevel - level) > 0.01) w.windowLevel = level;
    if (was == MSBDRStripHidden && w.hidden) for (DMRStripCard *c in cards) if (!c.landing) { c.transform = DMRStripAway(); if (MSBReduceMotion()) c.alpha = 0.0; }
    w.hidden = NO;
    if (was != MSBDRStripHidden) return;   // (on the desktop to over the windows, or back: it is out already)
    int i = 0;
    for (DMRStripCard *c in cards) {
        if (c.landing) continue;   // (its flight brings it)
        MSBAnimate(kMSBDRStripShowTime, MSBDRStripStaggerAt(i++), kMSBDRStripShowDamp, UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction, ^{
            c.transform = CGAffineTransformIdentity;
            if (!c.going) c.alpha = 1.0;
        }, nil);
    }
}
static void DMRStripKeysTake(BOOL take);
// The finger's handle (KT's choice): shown by the rules (stepped aside with cards, no trackpad or mouse attached), at the strip's edge centred on the
// cards, its touch area the rules' (20 pt at the edge, the handle's height and 22 pt above and below: an app's own edge swipe elsewhere stays the
// app's). While it shows the strip's window stays up for it alone.
static BOOL DMRStripHandleWanted(void) { return MSBDRStripHandleShown(gRStripMayRevealNow && gRStripShown == MSBDRStripHidden && gRStripItems.count > 0, gDMPointerAttached); }
static void DMRStripHandleUpdate(void) {
    UIView *h = gRStripHandle, *t = gRStripHandleTouch;
    if (!h || !t) return;
    BOOL want = DMRStripHandleWanted();
    if (want) {
        CGSize sc = gRStripRoot.bounds.size;
        h.frame = DMRStripCGRect(MSBDRStripHandleRect(sc.width, gRStripSpan, gRStripRight));
        t.frame = DMRStripCGRect(MSBDRStripHandleTouch(sc.width, gRStripSpan, gRStripRight));
        if (h.hidden) { h.hidden = NO; t.hidden = NO; gRStripWindow.hidden = NO; DM_FEATURE_MARK("recent-strip-handle"); MSBAnimate(0.25, 0, 0, UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState, ^{ h.alpha = 1.0; }, nil); }
        return;
    }
    if (h.hidden) return;
    t.hidden = YES;
    MSBAnimate(0.15, 0, 0, UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState, ^{ h.alpha = 0.0; }, ^(BOOL f) {
        if (DMRStripHandleWanted()) return;
        h.hidden = YES;
        if (gRStripShown == MSBDRStripHidden) gRStripWindow.hidden = YES;
    });
}
static void DMRStripRevealEnd(NSString *why) {
    if (!gRStripReveal) return;
    DMLog([NSString stringWithFormat:@"[recentstrip] its reveal ends (%@)", why]);
    gRStripReveal = 0; gRStripPointerOutAt = 0;
    DMRStripKeysTake(NO);
}
// Everything of it goes (switched off, another engine, the strip's iPadOS left): the window hidden, the cards, pictures and kept cards let go.
static void DMRStripReset(NSString *why) {
    if (gRStripWindow && !gRStripWindow.hidden) DMLog([NSString stringWithFormat:@"[recentstrip] off (%@)", why]);
    gRStripShown = MSBDRStripHidden; gRStripReveal = 0; gRStripMayRevealNow = NO;
    gRStripWindow.hidden = YES;
    for (DMRStripCard *c in gRStripCards.allValues) [c removeFromSuperview];
    [gRStripCards removeAllObjects]; [gRStripPics removeAllObjects]; [gRStripPicAt removeAllObjects]; [gRStripPicDue removeAllObjects];
    [gRStripGhosts removeAllObjects]; [gRStripGone removeAllObjects]; [gRStripLeaving removeAllObjects]; [gRStripLeavingAt removeAllObjects]; [gRStripRelaunch removeAllObjects];
    gRStripList = nil; gRStripItems = nil; gRStripStageOf = nil; gRStripLastSeen = nil; gRStripLayoutSig = nil; gRStripFront = @"";
    gRStripDragWin = nil; gRStripDropTarget = NO; gRStripGapAt = -1; gRStripHighlight.alpha = 0.0;
    [gRStripCardDrag.holder removeFromSuperview]; gRStripCardDrag = nil; gRStripDraggingKey = nil;
    gRStripHandle.hidden = YES; gRStripHandle.alpha = 0.0; gRStripHandleTouch.hidden = YES;
    DMRStripKeysTake(NO);
    DMRStripSysHoverUpdate(NO);
}

// ---- a window going in, and coming back out ----
// Our minimize, before its flag is set and its flight starts (StatusBar.x DMMinimizeStage, DMMinimizeWindow: the yellow light, Command-M, the app
// menu, Window > Minimize and Move to Strip, Minimize All, Home, a title bar double tap, Aerial's chip caught): its entry (a swap's, a burst's or a
// respring's set before, else now), its place, and its picture right before it goes (MSBDRStripPicAtEntry: what you saw when you sent it).
__attribute__((noinline)) static void DMRStripWillMinimize(UIView *stage) {
    if (!stage || !DMRStripOn()) return;
    NSString *k = DMStageBundle(stage);
    if (!k.length) return;
    NSArray *p = objc_getAssociatedObject(stage, kRStripPendingKey);
    double at = DMRStripClock(); int why = MSBDRStripWhyMinimized;
    if (p.count == 2 && isfinite([p[0] doubleValue])) { at = [p[0] doubleValue]; why = [p[1] intValue]; }
    objc_setAssociatedObject(stage, kRStripPendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DMRStripSetEntry(stage, at, why);
    objc_setAssociatedObject(stage, kRStripPlaceKey, [NSValue valueWithCGRect:DMRStripPlaceNow(stage)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [gRStripGhosts removeObjectForKey:k]; [gRStripGone removeObjectForKey:k];
    if (stage.hidden || stage.alpha < 0.05) return;   // (not on screen: a respring's restore -- an icon card until it is seen once)
    BOOL burst = objc_getAssociatedObject(stage, kRStripDelayKey) != nil;
    NSNumber *t = gRStripPicAt[k];
    if (!MSBDRStripPicAtEntry(gRStripPics[k] != nil, t ? CACurrentMediaTime() - t.doubleValue : 1e9, burst, !burst || [k isEqualToString:gRStripBurstFront ?: @""])) return;
    DMRStripPicture(stage, k, burst ? @"it goes in with the others" : @"it goes in");
}
// The cover: a full-screen app behind the windows lies over the whole edge; a window (as drawn) or one of ours over the cards' part of it.
static BOOL DMRStripCoveredNow(BOOL laid) {
    BOOL covered = laid && DMFrontApp() != nil && DMFullScreenAppInFront();
    for (UIView *st in gRStripStageOf.allValues) {
        if (covered || !laid) break;
        if (!DMRStripStageOnScreen(st)) continue;
        CGRect w = DMSnapWindowOf(st);   // (the drawn window: Aerial's stage is wider by its margins, 1.8.8.2 f29 R5)
        if (!CGRectIsNull(w) && MSBDRStripCovers(gRStripSpan, DMRStripRectOf(w))) covered = YES;
    }
    if (!covered && laid && gNativeLayer && !gNativeLayer.hidden) {
        id<UICoordinateSpace> scr = [UIScreen mainScreen].coordinateSpace;
        for (DMNativeWindow *nw in gNativeWindows) if (!nw.hidden && nw.superview && nw.alpha > 0.05 && MSBDRStripCovers(gRStripSpan, DMRStripRectOf([nw convertRect:nw.bounds toCoordinateSpace:scr]))) { covered = YES; break; }
    }
    return covered;
}
// The card's place on the screen as laid out (a flight's end or start).
static CGRect DMRStripCardScreenRect(DMRStripCard *c) { return c ? DMRStripCGRect(c.screenRect) : CGRectNull; }
// The place of a minimize's or a way back's flight (StatusBar.x DMMinimizedTransform asks this first, for both): a window going into the strip
// flies into the slot it takes in the list as it is now (laid out at once, the others making room; past the cap into the last slot, *faded); a
// window coming back grows out of its card when the card is on the screen. CGRectNull: its Dock icon, as before (the switch off, the strip
// unable to show: something over the windows, the windows behind a full-screen app).
__attribute__((noinline)) static CGRect DMRStripFlightRect(UIView *window, BOOL *faded) {
    if (faded) *faded = NO;
    if (!window || !DMRStripOn()) return CGRectNull;
    NSString *k = DMStageBundle(window);
    if (!k.length) return CGRectNull;
    if (!DMRStripOffDesktop(window)) {   // (coming back: our minimize's flag is off already)
        NSValue *r = gRStripLeaving[k];
        [gRStripLeaving removeObjectForKey:k]; [gRStripLeavingAt removeObjectForKey:k];
        DMRStripCard *c = gRStripCards[k];
        if (!r && MSBDRStripGrowsOut(c && c.superview && !c.going, gRStripShown != MSBDRStripHidden, c.landing)) r = [NSValue valueWithCGRect:DMRStripCardScreenRect(c)];
        DMRStripCardGoes(k, r != nil);
        DMRStripClearEntry(window);
        DMRStripRelayout(YES);   // (the gap closes with a spring)
        if (r) DM_FEATURE_MARK("recent-strip-back-from-card");
        return r ? r.CGRectValue : CGRectNull;
    }
    DMRStripCard *mine = gRStripCards[k];
    if (!mine) { mine = DMRStripCardFor(k); mine.landing = YES; }   // (its card is made for the flight: the layout leaves it hidden, the landing shows it)
    if (gRStripBursting)   // (a burst: the cards of its windows still to fly are made hidden too, so none shows before its own flight brings it)
        for (UIView *st in DMAerialStages()) if (DMRStripBurstPending(st)) { NSString *bk = DMStageBundle(st); if (bk.length && !gRStripCards[bk]) DMRStripCardFor(bk).landing = YES; }
    BOOL laid = DMRStripRelayout(gRStripShown != MSBDRStripHidden);
    // (with no window left on the desktop the strip shows only on a Home Screen that keeps its band free: else the Dock icon, as before)
    if (!laid || !MSBDRStripFliesIn(YES, gRStripCalmNow, gRStripFrontNow) || (!gRStripAnyShown && !gRStripHomeBand)) {
        if (mine.landing && mine.superview != gRStripSlide) { mine.landing = NO; [gRStripCards removeObjectForKey:k]; }
        else if (mine.landing) mine.landing = NO;
        return CGRectNull;
    }
    NSUInteger slot = [gRStripList indexOfObject:k];
    if (slot == NSNotFound) return CGRectNull;
    BOOL past = NO;
    int at = MSBDRStripFlightSlot(slot, gRStripFit, &past);
    if (at < 0 || (NSUInteger)at >= gRStripItems.count) return CGRectNull;
    DMRStripCard *c = gRStripCards[gRStripItems[(NSUInteger)at]];
    if (!c) return CGRectNull;
    if (faded) *faded = past;
    double delay = [objc_getAssociatedObject(window, kRStripDelayKey) doubleValue];
    if (!past) DMRStripCardLanding(c, delay);
    else if (mine.landing) mine.landing = NO;
    // (the strip shows for the landing: on its own where nothing covers it; stepped aside under a window, out for the landing and then aside again,
    //  the Flight reveal)
    MSBDRStripState s = { 1, (int)gRStripItems.count, gRStripCalmNow, gRStripFrontNow, gRStripAnyShown, DMRStripCoveredNow(YES), gRStripReveal != 0, gRStripHomeBand, 0 };
    if (MSBDRStripMayReveal(s) && !gRStripReveal) {
        gRStripReveal = MSBDRStripRevealFlight; s.revealed = 1;
        gRStripTouchedAt = CACurrentMediaTime() + delay + 0.36;   // (the peek lasts kMSBDRStripFlightShow from the landing)
    }
    MSBDRStripShow show = MSBDRStripShowFor(s);
    if (show != MSBDRStripHidden) DMRStripShowAs(show, @"a window flies in");
    DM_FEATURE_MARK("recent-strip-flight-in");
    return DMRStripCardScreenRect(c);
}
// Our own window's minimize and way back (NativeWindow.h -minimize, -show ask this first): going in, its entry (a swap's or a drag's set before,
// else now), its picture, and the place of its app's card it flies into (a new card hidden until it lands; one already there takes it into its
// stack); coming back, its app's card's place when on the screen (the card stays while others of its app wait there). Screen points; CGRectNull:
// the Dock's Finder icon, as before (the switch off, the strip unable to show).
__attribute__((noinline)) static CGRect DMRStripNativeFlight(DMNativeWindow *w, BOOL into) {
    if (!w || !DMRStripOn()) return CGRectNull;
    NSString *k = DMRStripNativeKey(w);
    if (!into) {
        objc_setAssociatedObject(w, kRStripGoingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSValue *r = gRStripLeaving[k];   // (a pick of its card: every window of it grows out of it; the mark lapses by itself)
        DMRStripCard *c = gRStripCards[k];
        if (!r && MSBDRStripGrowsOut(c && c.superview && !c.going, gRStripShown != MSBDRStripHidden, c.landing)) r = [NSValue valueWithCGRect:DMRStripCardScreenRect(c)];
        NSUInteger others = 0;
        for (DMNativeWindow *o in gRStripGroups[k]) if (o != w && DMRStripHiddenByUs(o)) others++;
        if (!others) DMRStripCardGoes(k, r != nil);   // (its app's last one: the card goes into it)
        DMRStripClearEntry(w);
        [gRStripPics removeObjectForKey:DMRStripNativePicKey(w)];
        DMRStripRelayout(YES);
        return r ? r.CGRectValue : CGRectNull;
    }
    NSArray *p = objc_getAssociatedObject(w, kRStripPendingKey);
    double at = DMRStripClock(); int why = MSBDRStripWhyMinimized;
    if (p.count == 2 && isfinite([p[0] doubleValue])) { at = [p[0] doubleValue]; why = [p[1] intValue]; }
    objc_setAssociatedObject(w, kRStripPendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DMRStripSetEntry(w, at, why);
    objc_setAssociatedObject(w, kRStripGoingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSString *pk = DMRStripNativePicKey(w);
    NSNumber *t = gRStripPicAt[pk];
    if (!w.hidden && w.alpha > 0.05 && MSBDRStripPicAtEntry(gRStripPics[pk] != nil, t ? CACurrentMediaTime() - t.doubleValue : 1e9, NO, YES)) DMRStripPicture(w, pk, @"it goes in");
    DMRStripCard *mine = gRStripCards[k];
    BOOL fresh = !mine;
    if (fresh) { mine = DMRStripCardFor(k); mine.landing = YES; }
    BOOL laid = DMRStripRelayout(gRStripShown != MSBDRStripHidden);
    if (!laid || !MSBDRStripFliesIn(YES, gRStripCalmNow, gRStripFrontNow) || (!gRStripAnyShown && !gRStripHomeBand)) {
        if (fresh && mine.superview != gRStripSlide) [gRStripCards removeObjectForKey:k];
        mine.landing = NO;
        return CGRectNull;   // (it still goes in: its card shows once the strip can)
    }
    NSUInteger slot = [gRStripList indexOfObject:k];
    BOOL past = NO;
    int at2 = slot == NSNotFound ? -1 : MSBDRStripFlightSlot(slot, gRStripFit, &past);
    DMRStripCard *c = at2 >= 0 && (NSUInteger)at2 < gRStripItems.count ? gRStripCards[gRStripItems[(NSUInteger)at2]] : nil;
    if (!c) { mine.landing = NO; return CGRectNull; }
    if (!past && c == mine && fresh) DMRStripCardLanding(c, 0.0); else mine.landing = NO;
    MSBDRStripState s = { 1, (int)gRStripItems.count, gRStripCalmNow, gRStripFrontNow, gRStripAnyShown, DMRStripCoveredNow(YES), gRStripReveal != 0, gRStripHomeBand, 0 };
    if (MSBDRStripMayReveal(s) && !gRStripReveal) { gRStripReveal = MSBDRStripRevealFlight; s.revealed = 1; gRStripTouchedAt = CACurrentMediaTime() + 0.36; }
    MSBDRStripShow show = MSBDRStripShowFor(s);
    if (show != MSBDRStripHidden) DMRStripShowAs(show, @"one of our windows flies in");
    DM_FEATURE_MARK("recent-strip-native-in");
    return DMRStripCardScreenRect(c);
}
// ... and its flight landed (its window hidden): its card shows, a window dropped in goes back to where it was before the drag.
__attribute__((noinline)) static void DMRStripNativeLanded(DMNativeWindow *w) {
    if (!w) return;
    objc_setAssociatedObject(w, kRStripGoingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!DMRStripOn()) return;
    NSValue *back = objc_getAssociatedObject(w, kRStripReturnKey);
    if (back) { objc_setAssociatedObject(w, kRStripReturnKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); w.frame = DMNativeClamp(back.CGRectValue, w.minSize); }
    DMRStripCard *c = gRStripCards[DMRStripNativeKey(w)];
    if (c.landing) {
        c.landing = NO; c.settledAt = CACurrentMediaTime() + 0.12;
        MSBAnimate(kMSBDRStripShowTime, 0, kMSBDRStripShowDamp, UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction, ^{ c.alpha = 1.0; c.lift.transform = CGAffineTransformIdentity; }, nil);
    } else if (c) DMRStripCardPicture(c);   // (into a card already there: its stack)
    if (gRStripReveal == MSBDRStripRevealFlight) gRStripTouchedAt = CACurrentMediaTime();
    DMRStripRelayout(gRStripShown != MSBDRStripHidden);
}
// A burst's flight starts this much later (Minimize All, Home: 30 ms apart, the one in front last). Asked once by its flight.
__attribute__((noinline)) static double DMRStripFlightDelay(UIView *window) {
    NSNumber *d = window ? objc_getAssociatedObject(window, kRStripDelayKey) : nil;
    if (!d) return 0.0;
    objc_setAssociatedObject(window, kRStripDelayKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return DMRStripOn() && isfinite(d.doubleValue) && d.doubleValue > 0.0 ? MIN(d.doubleValue, 1.0) : 0.0;
}
// A window dropped into the strip, now hidden: back at its engine frame from before the drag (the engine's own setter, no animation; Aerial 5's
// remembered state with it), so it comes back there, as on a Mac. Its tile and its place are as they were.
static void DMRStripPutBack(UIView *st, CGRect f) {
    if (!st || CGRectIsNull(f) || f.size.width < 150.0 || f.size.height < 150.0 || !DMRStripHiddenByUs(st)) return;
    Class zc = objc_getClass("ZetsuWindow");
    if (zc && [st isKindOfClass:zc]) [UIView performWithoutAnimation:^{ st.frame = f; }];
    else {
        if (DMActiveEngine() == DMEngineAerial) DMAerial5SyncState(st, f);
        [UIView performWithoutAnimation:^{ DMSetStageFrameSafe(st, f); [st layoutIfNeeded]; }];
    }
    DMSetStageIntent(st, f);
    objc_setAssociatedObject(st, kRStripPlaceKey, [NSValue valueWithCGRect:f], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DMSaveWindowState();
}
// The flight of our minimize has landed (StatusBar.x: its window hidden): the card it flew into shows there with a small settle.
__attribute__((noinline)) static void DMRStripLanded(UIView *window) {
    if (!window || !DMRStripOn()) return;
    NSValue *back = objc_getAssociatedObject(window, kRStripReturnKey);
    if (back) { objc_setAssociatedObject(window, kRStripReturnKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); DMRStripPutBack(window, back.CGRectValue); }
    DMRStripCard *c = gRStripCards[DMStageBundle(window) ?: @""];
    if (c.landing) {
        c.landing = NO;
        c.settledAt = CACurrentMediaTime() + 0.12;
        MSBAnimate(kMSBDRStripShowTime, 0, kMSBDRStripShowDamp, UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction, ^{ c.alpha = 1.0; c.lift.transform = CGAffineTransformIdentity; }, nil);
    }
    if (gRStripReveal == MSBDRStripRevealFlight) gRStripTouchedAt = CACurrentMediaTime();
}
// Minimize All and Home Minimizes Windows (StatusBar.x DMMinimizeAllWindows): every window it takes gets its time first, back to front (the one in
// front newest), and its flight's delay, so each flies into its slot of the final list, 30 ms apart. Returns them for DMRStripBurstEnd.
__attribute__((noinline)) static NSArray<UIView *> *DMRStripBurstBegin(void) {
    if (!DMRStripOn()) return nil;
    NSMutableArray<UIView *> *out = [NSMutableArray array];
    DMEngine e = DMActiveEngine();
    if (e == DMEngineZetsu) { for (UIView *w in DMAerialStages()) if (!w.hidden && !DMStageMinimized(w)) [out addObject:w]; }   // (the loops' own choice and order)
    else if (e == DMEngineAerial) { for (UIView *s in DMAerialStages()) if (!s.hidden && !DMStageMinimized(s) && DMStageBundle(s).length) [out addObject:s]; }
    else if (e == DMEngineMilkyWay) { Class vc = objc_getClass("AXWindowView"); for (UIView *v in DMMilkyWayLayer().subviews) if (vc && [v isKindOfClass:vc] && !v.hidden && !DMWindowMinimized(v)) [out addObject:v]; }
    if (out.count < 2) return nil;   // (one window: a single minimize)
    gRStripBurstFront = [DMRStripFrontNow() copy]; gRStripBursting = YES;
    double now = DMRStripClock();
    for (NSUInteger i = 0; i < out.count; i++) {
        objc_setAssociatedObject(out[i], kRStripPendingKey, @[@(MSBDRStripBurstAt(now, (int)i)), @(MSBDRStripWhyMinimized)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(out[i], kRStripDelayKey, @(MSBDRStripBurstDelay((int)i)), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    DM_FEATURE_MARK("recent-strip-burst");
    return out;
}
__attribute__((noinline)) static void DMRStripBurstEnd(NSArray<UIView *> *burst) {
    for (UIView *w in burst) {   // (a window the loop did not take after all: no burst entry left on it)
        if (DMRStripHiddenByUs(w)) continue;
        objc_setAssociatedObject(w, kRStripPendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(w, kRStripDelayKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    gRStripBurstFront = nil; gRStripBursting = NO;
}

static void DMRStripMinimizeNow(UIView *w) {   // (our minimize, the engine's way; our own windows' own)
    if ([w isKindOfClass:[DMNativeWindow class]]) { [(DMNativeWindow *)w minimize]; return; }
    Class mwc = objc_getClass("AXWindowView");
    if (mwc && [w isKindOfClass:mwc]) DMMinimizeWindow(w); else DMMinimizeStage(w);
}
// ---- a window dragged by hand over it ----
// The touch of a gesture on the iPad's screen (a window's title bar drag: every engine's, our own windows').
__attribute__((noinline)) static CGPoint DMRStripTouchOnScreen(UIGestureRecognizer *g) {
    UIView *v = g.view;
    if (!v || !(v.window || [v isKindOfClass:[UIWindow class]])) return CGPointMake(NAN, NAN);
    UIScreen *scr = (v.window ?: (UIWindow *)v).screen ?: [UIScreen mainScreen];
    if (scr != [UIScreen mainScreen]) return CGPointMake(NAN, NAN);   // (the strip is the iPad's)
    return [v convertPoint:[g locationInView:v] toCoordinateSpace:scr.coordinateSpace];
}
static BOOL DMRStripCanJoin(UIView *w) {   // (a window that can wait in the strip: an engine's of this desktop, or one of ours, on screen, not on its way out)
    if ([w isKindOfClass:[DMNativeWindow class]]) return !w.hidden && w.superview && [gNativeWindows containsObject:(DMNativeWindow *)w];
    return w && DMStageBundle(w).length && !DMRStripHiddenByUs(w) && ![objc_getAssociatedObject(w, kStageClosingKey) boolValue]
        && ![objc_getAssociatedObject(w, kStageGoingFullKey) boolValue] && ![objc_getAssociatedObject(w, kMSWAwayKey) boolValue];
}
static MSBDRStripShow DMRStripApplyShow(BOOL laid, BOOL covered, NSString *why);
// The drop zone's state: out over the windows with a slot open at the top and the band's soft highlight (cards or none), or back as the rules say.
static void DMRStripSetDropTarget(BOOL on) {
    if (on == gRStripDropTarget) return;
    gRStripDropTarget = on; gRStripGapAt = on ? 0 : -1;
    if (on) DM_FEATURE_MARK("recent-strip-drop-target");
    BOOL laid = DMRStripRelayout(YES);
    UIView *hl = gRStripHighlight;
    if (hl && on) {
        BOOL dark = [UIScreen mainScreen].traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark, solid = UIAccessibilityIsReduceTransparencyEnabled() || UIAccessibilityDarkerSystemColorsEnabled();
        hl.backgroundColor = [UIColor colorWithWhite:dark ? 1.0 : 0.0 alpha:solid ? (dark ? 0.26 : 0.18) : (dark ? 0.10 : 0.07)];   // (light or dark, a solid one for Reduce Transparency or Increase Contrast)
        hl.frame = CGRectInset(DMRStripCGRect(gRStripBand), 6.0, 8.0);
        [hl.superview sendSubviewToBack:hl];
    }
    if (hl) MSBAnimate(kMSBDRStripMoveTime, 0, kMSBDRStripMoveDamp, UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction, ^{ hl.alpha = on ? 1.0 : 0.0; }, nil);
    DMRStripApplyShow(laid, DMRStripCoveredNow(laid), on ? @"a window dragged to its edge" : @"the window dragged away from its edge");
}
// A window's drag by hand (StatusBar.x: Zetsu's title bar, MilkyWay4's title bar, Aerial's drags through DMAerialGestureAfter, Aerial 5's
// -dragTrace: and -areaDrag:; NativeWindow.h: our own windows), at every state with its recognizer (its touch on the screen read here, after the
// switch's test). Over the cards: the strip steps aside
// in that same frame; at its edge (the drop zone, the rules'): it comes out with a slot open at the top, also with no card; let go there: the
// window goes into the strip from where it was let go, and back to where it was before the drag once hidden (YES: the site then leaves its snap,
// Behind the Dock, the title bar's record and its place alone). Any other drop: NO, the drop it always was. Off: one test per move.
__attribute__((noinline)) static BOOL DMRStripWindowDrag(UIView *win, UIGestureRecognizer *g, UIGestureRecognizerState state) {
    if (!gRStripPref || !win || !DMRStripOn()) return NO;
    CGPoint p = DMRStripTouchOnScreen(g);
    CFTimeInterval now = CACurrentMediaTime();
    BOOL end = state == UIGestureRecognizerStateEnded || state == UIGestureRecognizerStateCancelled || state == UIGestureRecognizerStateFailed;
    if (end && win == gRStripDropTakenWin && now - gRStripDropTakenAt < 0.5) return state == UIGestureRecognizerStateEnded;   // (the same drop's second end call)
    if (state == UIGestureRecognizerStateBegan || (!end && !gRStripDragWin)) {
        gRStripDragWin = win; gRStripDragFrom = DMRStripPlaceNow(win); gRStripDragCovers = NO;
        // (one of ours: -dm_move: has moved it by the pan's own start already -- it keeps no engine's place --, so where it was at the touch: the
        //  frame less the pan's way, the landing's clamp as at the start; it came back 10 pt off where it was before the drag, review of 1.8.8.4)
        if ([win isKindOfClass:[DMNativeWindow class]] && [g isKindOfClass:[UIPanGestureRecognizer class]] && win.superview) {
            CGPoint t = [(UIPanGestureRecognizer *)g translationInView:win.superview];
            if (isfinite(t.x) && isfinite(t.y)) gRStripDragFrom = CGRectOffset(win.frame, -t.x, -t.y);
        }
        gRStripDragScreen = CGSizeZero;   // (its band just below)
    }
    if (gRStripDragWin != win) return NO;
    // (the drop zone for the screen as it is: a turn during the drag gives the new shape's band, and its side -- with the Dock at Left the strip goes
    //  to the other edge --; before, the zone stayed the old shape's until the drag ended, review of 1.8.8.4)
    CGSize sc = [UIScreen mainScreen].bounds.size;
    if (!CGSizeEqualToSize(sc, gRStripDragScreen)) {
        gRStripDragScreen = sc;
        gRStripDragRight = MSBDRStripOnRight(DMDockSideNow(sc) == MSBDDockLeft);
        gRStripDragBand = MSBDRStripBand(sc.width, sc.height, DMRStripRectOf(DMUsableArea()), gRStripDragRight);
    }
    gRStripDragAt = now;
    BOOL joins = DMRStripCanJoin(win);
    BOOL inZone = joins && isfinite(p.x) && isfinite(p.y) && MSBDRStripInDropZone(p.x, p.y, gRStripDragBand, gRStripDragRight);
    if (!end) {
        if (inZone != gRStripDropTarget) { DMRStripSetDropTarget(inZone); return NO; }
        if (inZone) return NO;
        // (over the cards: aside now, not at the next tick; off them again: back as the rules say; the window as drawn, ours as it is)
        CGRect w = [win isKindOfClass:[DMNativeWindow class]] ? (win.superview ? [win.superview convertRect:win.frame toCoordinateSpace:[UIScreen mainScreen].coordinateSpace] : CGRectNull) : DMSnapWindowOf(win);
        BOOL covers = gRStripItems.count && !CGRectIsNull(w) && MSBDRStripCovers(gRStripSpan, DMRStripRectOf(w));
        if (covers != gRStripDragCovers) { gRStripDragCovers = covers; DMRStripApplyShow(gRStripItems.count > 0, covers || DMRStripCoveredNow(gRStripItems.count > 0), covers ? @"a window dragged over it" : @"the window dragged off it"); }
        return NO;
    }
    gRStripDragWin = nil;
    BOOL take = state == UIGestureRecognizerStateEnded && MSBDRStripDropTakes(inZone, DMRStripCalm() && DMDesiredWindowLevel() > 10.0, joins);
    if (!take) { DMRStripSetDropTarget(NO); return NO; }
    // (into the strip from where it was let go, into the slot open at the top; back to where it was before the drag once hidden)
    gRStripDropTarget = NO; gRStripGapAt = -1;   // (the flight's layout puts its card where the slot was)
    if (gRStripHighlight) MSBAnimate(kMSBDRStripMoveTime, 0, kMSBDRStripMoveDamp, UIViewAnimationOptionBeginFromCurrentState, ^{ gRStripHighlight.alpha = 0.0; }, nil);
    objc_setAssociatedObject(win, kRStripPendingKey, @[@(DMRStripClock()), @(MSBDRStripWhyDragged)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(win, kRStripReturnKey, [NSValue valueWithCGRect:gRStripDragFrom], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    gRStripDropTakenWin = win; gRStripDropTakenAt = now;
    DM_FEATURE_MARK("recent-strip-drag-in");
    DMLog([NSString stringWithFormat:@"[recentstrip] %@ dropped on the strip: it goes in (back at %@ when it comes out)", [win isKindOfClass:[DMNativeWindow class]] ? DMRStripNativeKey((DMNativeWindow *)win) : DMStageBundle(win), NSStringFromCGRect(gRStripDragFrom)]);
    DMRStripMinimizeNow(win);
    return YES;
}

// ---- a pick ----
// The window in front for a swap: the focused one (the active window, Command-M's: DMKeepCoveredActive), with the windows in front. Our own window
// focused (Finder, TextEdit...): *ours (it does not wait in the strip yet: a pick then only brings back).
static UIView *DMRStripFrontWindow(BOOL *ours) {
    if (ours) *ours = NO;
    DMNativeWindow *nw = DMNativeActiveApp();
    if (nw) { if (ours) *ours = YES; return nw; }   // (our own window focused: it waits in the strip too)
    if (!DMWindowsInFront()) return nil;
    BOOL stageEngine = DMActiveEngine() == DMEngineAerial || DMActiveEngine() == DMEngineZetsu;
    return DMKeepCoveredActive(stageEngine ? DMTopStage() : DMTopWindow());
}
// A kept card's app, or MilkyWay4's grey window's: opened again as a window at its place, the engine's own way (the Mac Switcher's relaunch).
static void DMRStripRelaunchNow(NSString *b, CGRect f) {
    BOOL placed = !CGRectIsNull(f) && f.size.width > 100.0 && f.size.height > 100.0;
    DMEngine e = DMActiveEngine();
    DMLog([NSString stringWithFormat:@"[recentstrip] %@: its app opens again as a window at %@", b, placed ? NSStringFromCGRect(f) : @"its usual place"]);
    if (e == DMEngineZetsu || e == DMEngineMilkyWay) {
        if (placed) { if (!gLastWindowFrames) gLastWindowFrames = [NSMutableDictionary dictionary]; gLastWindowFrames[b] = [NSValue valueWithCGRect:f]; }
        if (e == DMEngineZetsu) DMZetsuLaunch(b); else DMLaunchAsWindow(b);
    } else if (placed) DMLaunchIntoTile(b, f);
    else DMOpenApp(b);
}
// A tap or click on a card (shift: Shift held): its window comes back out of its card to its place and comes to the front, and the window in front
// flies into the slot the card leaves (a swap, the rules' MSBDRStripPickSwaps: not with Shift, not with no window in front). One pick at a time,
// none before a card has settled (MSBDRStripPickTakes).
static void DMRStripPick(DMRStripCard *card, BOOL shift, NSString *how) {
    NSString *k = card.key;
    if (!k.length || gRStripShown == MSBDRStripHidden || !card.superview || card.going || card.landing) return;
    CFTimeInterval now = CACurrentMediaTime();
    if (!MSBDRStripPickTakes(now, card.settledAt, gRStripLastPickAt)) { static int told = 0; if (told++ < 6) DMLog([NSString stringWithFormat:@"[recentstrip] %@ on %@ not taken (a pick just before, or the card still settling)", how, k]); return; }
    gRStripLastPickAt = now;
    DMRStripTouched();
    NSDictionary *kept = gRStripGhosts[k] ?: gRStripGone[k];
    NSArray<DMNativeWindow *> *members = DMRStripIsNativeKey(k) ? [gRStripGroups[k] copy] : nil;   // (our own windows: the whole app's)
    UIView *st = kept || members ? members.firstObject : gRStripStageOf[k];
    if (!kept && !members && (!st || ![DMAerialStages() containsObject:st])) st = DMStageForBundle(k);
    if (!kept && !st) return;
    BOOL ours = NO;
    UIView *front = DMRStripFrontWindow(&ours);
    BOOL frontJoins = front && !DMRStripOffDesktop(front) && ![objc_getAssociatedObject(front, kStageClosingKey) boolValue] && ![objc_getAssociatedObject(front, kStageGoingFullKey) boolValue];
    if ([front isKindOfClass:[DMNativeWindow class]]) frontJoins = DMRStripCanJoin(front) && ![members containsObject:(DMNativeWindow *)front];
    BOOL swaps = MSBDRStripPickSwaps(YES, shift, front != nil, frontJoins, front == st);
    double pickedAt = NAN; int pickedWhy = 0;
    if (kept) pickedAt = [kept[@"at"] doubleValue]; else DMRStripEntryOf(st, &pickedAt, &pickedWhy);
    // (the picked one leaves the list now -- Aerial 5 may show it only once its own restore is over --, its card's place kept for its flight)
    if (!gRStripLeaving) gRStripLeaving = [NSMutableDictionary dictionary];
    if (!gRStripLeavingAt) gRStripLeavingAt = [NSMutableDictionary dictionary];
    gRStripLeaving[k] = [NSValue valueWithCGRect:DMRStripCardScreenRect(card)]; gRStripLeavingAt[k] = @(now);
    if (gRStripReveal == MSBDRStripRevealMenu || gRStripReveal == MSBDRStripRevealFlight) DMRStripRevealEnd(@"a pick");
    DM_FEATURE_MARK("recent-strip-pick");
    if (swaps) DM_FEATURE_MARK("recent-strip-swap");
    DMLog([NSString stringWithFormat:@"[recentstrip] %@ on %@ (slot %lu): %@", how, k, (unsigned long)[gRStripItems indexOfObject:k],
           swaps ? [NSString stringWithFormat:@"it comes back, %@ takes its slot", [front isKindOfClass:[DMNativeWindow class]] ? DMRStripNativeKey((DMNativeWindow *)front) : DMStageBundle(front)] : @"it comes back"]);
    if (gNativeActive && !members) DMNativeSetActive(nil);   // (an app's window comes forward: our own windows step back, as the Mac Switcher's pick)
    if (members) {   // (our own windows: all of the app's come back, out of the card, the most recent last so it is in front -- KT's choice)
        for (DMNativeWindow *nw in [members reverseObjectEnumerator]) [nw show];
    } else if (kept) {   // (a kept card: its app opens again at its place)
        [gRStripGhosts removeObjectForKey:k]; [gRStripGone removeObjectForKey:k];
        [gRStripPics removeObjectForKey:k]; [gRStripPicAt removeObjectForKey:k];
        DMRStripCardGoes(k, NO);
        DMRStripRelaunchNow(k, [kept[@"place"] CGRectValue]);
    } else if (DMActiveEngine() == DMEngineMilkyWay && DMMSWMWAppGone(st, k, NULL)) {   // (MilkyWay4 kept the window of an app iPadOS ended: grey; closed, its app opens again)
        CGRect place = DMRStripPlaceOf(st).CGRectValue;
        DMLog([NSString stringWithFormat:@"[recentstrip] %@'s MilkyWay window kept no app (iPadOS ended it): closed, its app opens again", k]);
        DMRStripCardGoes(k, NO);
        DMMSWMWCloseGone(st);
        if (!gRStripRelaunch) gRStripRelaunch = [NSMutableDictionary dictionary];
        gRStripRelaunch[k] = @{ @"due": @(now + 0.4), @"place": [NSValue valueWithCGRect:place] };   // (once MilkyWay's close is through: the next ticks)
    } else if (!DMSurfaceWindowForApp(k)) DMRaiseStageForBundle(k);   // (what a Dock tap on that app does: shown again, that engine's own raise)
    if (swaps) {   // (the window in front into the slot the card leaves: the picked card's time, so it lands exactly there)
        objc_setAssociatedObject(front, kRStripPendingKey, @[@(MSBDRStripEntryAt(MSBDRStripWhySwapped, DMRStripClock(), pickedAt, 0)), @(MSBDRStripWhySwapped)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        DMRStripMinimizeNow(front);
    }
    DMRStripRelayout(YES);
}

// ---- a card dragged out, its menu, its keys ----
// A card's window placed hidden at an engine frame (a drag out's drop: the engine's own setter, no animation; Aerial 5's remembered state with
// it), then shown by the way back every window takes (DMSurfaceWindowForApp), growing out of the card where it was let go.
static void DMRStripPlaceHidden(UIView *st, CGRect f) {
    if (!st || CGRectIsNull(f) || f.size.width < 150.0 || f.size.height < 150.0) return;
    Class zc = objc_getClass("ZetsuWindow");
    if (zc && [st isKindOfClass:zc]) [UIView performWithoutAnimation:^{ st.frame = f; }];
    else {
        if (DMActiveEngine() == DMEngineAerial) DMAerial5SyncState(st, f);
        [UIView performWithoutAnimation:^{ DMSetStageFrameSafe(st, f); [st layoutIfNeeded]; }];
    }
    DMSetStageIntent(st, f);
    objc_setAssociatedObject(st, kRStripPlaceKey, [NSValue valueWithCGRect:f], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
// The proxy's place for the touch at p: the rules' size for how far past the band it is, the grab point under the touch.
static void DMRStripDragFollow(CGPoint p) {
    DMRStripDrag *d = gRStripCardDrag;
    if (!d) return;
    CGRect u = DMUsableArea();
    double w = d.cw, h = d.ch;
    MSBDRStripProxySize(d.cw, d.ch, d.ww, d.wh, DMRStripRectOf(u), MSBDRStripPastBand(p.x, gRStripBand, gRStripRight), &w, &h);
    d.holder.bounds = CGRectMake(0, 0, w, h);
    d.holder.center = CGPointMake(p.x - d.gx * w + w / 2.0, p.y - d.gy * h + h / 2.0);
    d.pic.frame = d.holder.bounds;
    d.holder.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:d.holder.bounds cornerRadius:7.0].CGPath;
}
// A drag out begins (the rules' press: moved past the finger's or the pointer's slop, also after a hold): the card lifts out as its proxy, the
// others close its gap.
static void DMRStripCardDragBegin(DMRStripCard *c, DMRStripPress *g) {
    NSString *k = c.key;
    if (!k.length || gRStripCardDrag || c.landing || c.going || gRStripShown == MSBDRStripHidden || !gRStripRoot) return;
    UIView *st = gRStripStageOf[k] ?: gRStripGroups[k].firstObject;
    NSDictionary *kept = gRStripGhosts[k] ?: gRStripGone[k];
    if (!st && !kept) return;
    CGRect place = st ? DMRStripPlaceOf(st).CGRectValue : [kept[@"place"] CGRectValue];
    CGRect drawn = [st isKindOfClass:[DMNativeWindow class]] ? place : st ? DMSnapWindowOfFrame(st, place) : place;
    if (CGRectIsNull(drawn) || drawn.size.width < 50.0) drawn = CGRectMake(0, 0, 600, 420);
    CGRect pr = DMRStripCardScreenRect(c);
    DMRStripDrag *d = [DMRStripDrag new];
    d.key = k; d.cw = pr.size.width; d.ch = pr.size.height; d.ww = drawn.size.width; d.wh = drawn.size.height;
    d.gx = pr.size.width > 1 ? MAX(0.0, MIN(1.0, (g.down.x - pr.origin.x) / pr.size.width)) : 0.5;
    d.gy = pr.size.height > 1 ? MAX(0.0, MIN(1.0, (g.down.y - pr.origin.y) / pr.size.height)) : 0.5;
    UIView *holder = [[UIView alloc] initWithFrame:pr];
    holder.userInteractionEnabled = NO;
    holder.layer.shadowColor = [UIColor blackColor].CGColor; holder.layer.shadowOpacity = 0.36; holder.layer.shadowRadius = kMSBDRStripLiftShadow; holder.layer.shadowOffset = CGSizeMake(0, 6);
    UIView *pic = [[UIView alloc] initWithFrame:holder.bounds];
    pic.userInteractionEnabled = NO;
    pic.layer.cornerRadius = 7.0; pic.layer.masksToBounds = YES; pic.layer.contentsGravity = kCAGravityResize;
    if (@available(iOS 13.0, *)) pic.layer.cornerCurve = kCACornerCurveContinuous;
    pic.layer.contents = c.pic.layer.contents; pic.backgroundColor = c.pic.backgroundColor;
    if (!pic.layer.contents) {   // (no picture yet: the tinted card with its app's icon in the middle)
        UIImageView *ic = [[UIImageView alloc] initWithImage:c.icon.image];
        ic.contentMode = UIViewContentModeScaleAspectFit; ic.userInteractionEnabled = NO;
        ic.frame = CGRectMake(0, 0, 40, 40);
        ic.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        ic.center = CGPointMake(pr.size.width / 2.0, pr.size.height / 2.0);
        [pic addSubview:ic];
    }
    [holder addSubview:pic];
    [gRStripRoot addSubview:holder];
    d.holder = holder; d.pic = pic;
    gRStripCardDrag = d; gRStripDraggingKey = [k copy];
    c.alpha = 0.0;
    DMRStripDragFollow(g.last);
    MSBAnimate(kMSBDRStripHoverTime, 0, kMSBDRStripHoverDamp, UIViewAnimationOptionBeginFromCurrentState, ^{ holder.transform = CGAffineTransformMakeScale(kMSBDRStripLiftScale, kMSBDRStripLiftScale); }, nil);
    DMRStripTouched();
    DMRStripRelayout(YES);   // (the gap closes with a spring)
    DM_FEATURE_MARK("recent-strip-drag-out");
    DMLog([NSString stringWithFormat:@"[recentstrip] %@'s card dragged out (%@)", k, g.pointer ? @"the pointer" : @"a finger"]);
}
// Back to its slot (let go in the band, or the drag cut short: a turn, a lock, the App Switcher, the strip going aside): the proxy flies back,
// the card shows there again. gone: its window went meanwhile (its app quit): the proxy shrinks and fades, nothing comes back.
static void DMRStripCardDragReturn(NSString *why, BOOL gone) {
    DMRStripDrag *d = gRStripCardDrag;
    if (!d) return;
    gRStripCardDrag = nil; gRStripDraggingKey = nil;
    UIView *holder = d.holder;
    DMLog([NSString stringWithFormat:@"[recentstrip] %@'s card back to its slot (%@)", d.key, why]);
    if (gone) {
        MSBAnimate(0.18, 0, 0, UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState, ^{ holder.alpha = 0.0; holder.transform = CGAffineTransformMakeScale(0.6, 0.6); }, ^(BOOL f) { [holder removeFromSuperview]; });
        DMRStripRelayout(YES);
        DMRStripCard *left = gRStripCards[d.key];   // (its card still in the strip after all -- the card the drag held, hidden: shown again, never left hidden)
        if (left && !left.going) { left.landing = NO; left.alpha = 1.0; }
        return;
    }
    DMRStripCard *c = gRStripCards[d.key];
    if (!c) { c = DMRStripCardFor(d.key); c.landing = YES; }
    BOOL laid = DMRStripRelayout(YES);
    c = gRStripCards[d.key];
    if (!laid || !c || c.superview != gRStripSlide) { [holder removeFromSuperview]; if (c) { c.landing = NO; c.alpha = 1.0; } return; }
    c.landing = YES; c.alpha = 0.0;
    CGRect to = DMRStripCardScreenRect(c);
    MSBAnimate(kMSBDRStripMoveTime, 0, kMSBDRStripMoveDamp, UIViewAnimationOptionBeginFromCurrentState, ^{
        holder.transform = CGAffineTransformIdentity; holder.bounds = CGRectMake(0, 0, to.size.width, to.size.height); holder.center = CGPointMake(CGRectGetMidX(to), CGRectGetMidY(to));
        d.pic.frame = holder.bounds;
    }, ^(BOOL f) {
        [holder removeFromSuperview];
        DMRStripCard *x = gRStripCards[d.key];
        if (x) { x.landing = NO; x.alpha = 1.0; x.settledAt = CACurrentMediaTime(); }
    });
}
// Let go: back in the band, or the window comes back where it was let go (the rules' frame: the grab point under the drop, a throw's landing point,
// kept as our windows are, then snapped as a move by hand), out of the card, at the front, with no swap (the Mac's add). A move by hand: Fit to
// Window's tiles let it go, its place is kept there.
static void DMRStripCardDragEnd(DMRStripPress *g) {
    DMRStripDrag *d = gRStripCardDrag;
    if (!d) return;
    CGPoint p = g.last;
    double dt = g.lastAt - g.prevAt, vx = 0, vy = 0;
    if (dt > 0.004 && dt < 0.1) { vx = (g.last.x - g.prev.x) / dt; vy = (g.last.y - g.prev.y) / dt; }
    double ox = p.x, oy = p.y;
    if (hypot(vx, vy) > 400.0) MSBDRStripFlickTo(p.x, p.y, vx, vy, &ox, &oy);   // (thrown: where its speed takes it)
    if (MSBDRStripDropsBack(ox, gRStripBand, gRStripRight)) { DMRStripCardDragReturn(@"let go in the band", NO); return; }
    NSString *k = d.key;
    NSDictionary *kept = gRStripGhosts[k] ?: gRStripGone[k];
    NSArray<DMNativeWindow *> *members = DMRStripIsNativeKey(k) ? [gRStripGroups[k] copy] : nil;
    if (members) {   // (our own windows: the most recent where it is let go, kept as our windows are; the others at their places; all back, it in front)
        DMNativeWindow *top = members.firstObject;
        if (!top || !DMRStripHiddenByUs(top)) { DMRStripCardDragReturn(@"its windows went meanwhile", YES); return; }
        CGRect drawn = DMRStripCGRect(MSBDRStripDropFrame(d.ww, d.wh, d.gx, d.gy, ox, oy, DMRStripRectOf(DMUsableArea())));
        CGRect from = [d.holder.superview convertRect:d.holder.frame toCoordinateSpace:[UIScreen mainScreen].coordinateSpace];
        gRStripCardDrag = nil; gRStripDraggingKey = nil;
        UIView *holder = d.holder;
        if (gNativeRotator) top.frame = DMNativeClamp([gNativeRotator convertRect:drawn fromCoordinateSpace:[UIScreen mainScreen].coordinateSpace], top.minSize);
        if (!gRStripLeaving) gRStripLeaving = [NSMutableDictionary dictionary];
        if (!gRStripLeavingAt) gRStripLeavingAt = [NSMutableDictionary dictionary];
        gRStripLeaving[k] = [NSValue valueWithCGRect:from]; gRStripLeavingAt[k] = @(CACurrentMediaTime());
        DM_FEATURE_MARK("recent-strip-drag-out-drop");
        for (DMNativeWindow *nw in [members reverseObjectEnumerator]) [nw show];
        MSBAnimate(kMSBDRStripPlaceFade, 0, 0, UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState, ^{ holder.alpha = 0.0; }, ^(BOOL f) { [holder removeFromSuperview]; });
        DMRStripRelayout(YES);
        return;
    }
    UIView *st = kept ? nil : DMStageForBundle(k);
    if (!kept && (!st || !DMRStripHiddenByUs(st))) { DMRStripCardDragReturn(@"its window went meanwhile", YES); return; }
    MSBDRRect desk = DMRStripRectOf(DMUsableArea());
    CGRect drawn = DMRStripCGRect(MSBDRStripDropFrame(d.ww, d.wh, d.gx, d.gy, ox, oy, desk));
    if (st) drawn = DMSnapEngineWindow(st, drawn, MSBDSnapMove);   // (lines up with what is near, kept out of a side Dock: a move by hand's end)
    CGRect engine = st ? DMSnapEngineFrameFor(st, drawn) : (DMActiveEngine() == DMEngineAerial ? DMA5StageFromWindow(drawn) : drawn);   // (a kept card: the engine's frame for it)
    CGRect from = [d.holder.superview convertRect:d.holder.frame toCoordinateSpace:[UIScreen mainScreen].coordinateSpace];
    gRStripCardDrag = nil; gRStripDraggingKey = nil;
    UIView *holder = d.holder;
    DM_FEATURE_MARK("recent-strip-drag-out-drop");
    DMLog([NSString stringWithFormat:@"[recentstrip] %@'s card let go at {%.0f, %.0f}: its window comes back at %@", k, ox, oy, NSStringFromCGRect(drawn)]);
    if (kept) {   // (a kept card: its app opens again there)
        [gRStripGhosts removeObjectForKey:k]; [gRStripGone removeObjectForKey:k];
        DMRStripCardGoes(k, NO);
        DMRStripRelaunchNow(k, engine);
    } else {
        DMRStripPlaceHidden(st, engine);
        DMFitGroupForget(k);   // (a move by hand: no longer tiled, as a hand move of a tiled window)
        DMTitleRecordMovedView(st);
        if (!gRStripLeaving) gRStripLeaving = [NSMutableDictionary dictionary];
        if (!gRStripLeavingAt) gRStripLeavingAt = [NSMutableDictionary dictionary];
        gRStripLeaving[k] = [NSValue valueWithCGRect:from]; gRStripLeavingAt[k] = @(CACurrentMediaTime());   // (the window grows out of the card where it was let go)
        if (gNativeActive) DMNativeSetActive(nil);
        if (!DMSurfaceWindowForApp(k)) DMRaiseStageForBundle(k);
        DMRememberStageFrame(st);
        DMSaveWindowState();
    }
    MSBAnimate(kMSBDRStripPlaceFade, 0, 0, UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState, ^{ holder.alpha = 0.0; }, ^(BOOL f) { [holder removeFromSuperview]; });
    DMRStripRelayout(YES);
}
// A card pressed (DMRStripPress): the rules' tap, menu or drag; a secondary click, two fingers on a trackpad or Control click: the menu; Shift: back
// with no swap. A finger held still: the card rises a little at the hold's time, ready (its menu on release, a drag if it moves on): the card's
// own press, DMRStripLiftTo, one animation of its lift; the release springs back from where it is drawn (no jump to an animation's end).
static void DMRStripPressed(DMRStripPress *g) {
    DMRStripCard *c = [g.view isKindOfClass:[DMRStripCard class]] ? (DMRStripCard *)g.view : nil;
    if (!c) return;
    double held = g.lastAt - g.downAt, moved = hypot(g.last.x - g.down.x, g.last.y - g.down.y);
    switch (g.state) {
        case UIGestureRecognizerStateBegan:
            DMRStripTouched();
            return;
        case UIGestureRecognizerStateChanged:
            if (gRStripCardDrag) { DMRStripDragFollow(g.last); return; }
            if (!g.secondary && MSBDRStripPressFor(held, moved, NO, g.pointer) == MSBDRStripPressDrag) { [c.lift.layer removeAllAnimations]; c.lift.transform = CGAffineTransformIdentity; DMRStripCardDragBegin(c, g); }
            return;
        case UIGestureRecognizerStateEnded: {
            c.pressed = NO; c.fingerDown = NO; DMRStripLiftTo(c);
            if (gRStripCardDrag) { DMRStripCardDragEnd(g); return; }
            MSBDRStripPress kind = MSBDRStripPressFor(held, moved, YES, g.pointer);
            if (g.secondary || (g.mods & UIKeyModifierControl)) kind = MSBDRStripPressMenu;
            if (kind == MSBDRStripPressMenu) DMRStripCardMenu(c, g.secondary ? @"a secondary click" : (g.mods & UIKeyModifierControl) ? @"a Control click" : @"a held finger");
            else if (kind == MSBDRStripPressTap) { BOOL shift = (g.mods & UIKeyModifierShift) != 0; DMRStripPick(c, shift, shift ? @"a Shift tap or click" : @"a tap or click"); }
            return;
        }
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            c.pressed = NO; c.fingerDown = NO; DMRStripLiftTo(c);
            if (gRStripCardDrag) DMRStripCardDragReturn(@"the touch was cancelled", NO);
            return;
        default: return;
    }
}
// Close Window from the card's menu or VoiceOver: the window's red light's own way (DMForceQuitBundle: the window closes, the app ends -- the
// user's quit, so its card goes); a kept card is let go.
static void DMRStripCloseCard(NSString *k) {
    if (!k.length) return;
    DM_FEATURE_MARK("recent-strip-close");
    if (gRStripGhosts[k] || gRStripGone[k]) { [gRStripGhosts removeObjectForKey:k]; [gRStripGone removeObjectForKey:k]; [gRStripPics removeObjectForKey:k]; DMRStripCardGoes(k, NO); DMRStripRelayout(YES); return; }
    DMLog([NSString stringWithFormat:@"[recentstrip] Close Window on %@'s card", k]);
    if (DMRStripIsNativeKey(k)) { for (DMNativeWindow *nw in [gRStripGroups[k] copy]) [nw close]; DMRStripRelayout(YES); return; }   // (our own windows: each closes)
    DMForceQuitBundle(k);
}
// The card's menu (a held finger's release, a secondary click, two fingers on a trackpad, Control click): ours, beside the card, with the menus'
// keys and VoiceOver (DMMakeBarMenuPanel, DMAXMenuPanel): Bring Back (no swap), Close Window.
static void DMRStripCardMenu(DMRStripCard *c, NSString *how) {
    if (!c.key.length || gRStripShown == MSBDRStripHidden || c.landing || c.going) return;
    if (!gMenuWindow && !DMCtorSkip("menuwin")) DMCreateMenuWindow();   // (our menus' window, as every menu of ours: above the strip)
    UIView *host = gMenuWindow ? DMMenuHost() : nil;
    if (!host || DMGARefuses(@"menu")) return;
    NSString *k = [c.key copy], *name = DMRStripIsNativeKey(k) ? [k substringFromIndex:7] : (DMCall(DMProxyForBundle(k), @"localizedName") ?: k);
    NSArray<DMNativeWindow *> *members = DMRStripIsNativeKey(k) ? [gRStripGroups[k] copy] : nil;
    NSMutableArray *items = [NSMutableArray arrayWithObject:[[DMRow alloc] initWithTitle:members.count > 1 ? @"Bring Back All" : @"Bring Back" enabled:YES handler:DMCloseThen(^{ DMRStripCard *x = gRStripCards[k]; if (x) DMRStripPick(x, YES, @"the card's Bring Back"); })]];
    if (members.count > 1) {   // (each of its windows by name: back alone, no swap, as a Mac's pile's pick)
        [items addObject:[NSNull null]];
        for (DMNativeWindow *nw in members) {
            __weak DMNativeWindow *wnw = nw;
            [items addObject:[[DMRow alloc] initWithTitle:nw.title.length ? nw.title : name enabled:YES handler:DMCloseThen(^{ DMNativeWindow *x = wnw; if (x && DMRStripHiddenByUs(x)) { DM_FEATURE_MARK("recent-strip-pile-pick"); [x show]; } })]];
        }
        [items addObject:[NSNull null]];
    }
    [items addObject:[[DMRow alloc] initWithTitle:members.count > 1 ? @"Close Windows" : @"Close Window" enabled:YES handler:DMCloseThen(^{ DMRStripCloseCard(k); })]];
    UIControl *o = DMMakeOverlayFor(host, 0.0, YES);
    [o addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { DMCloseOverlay(); }] forControlEvents:UIControlEventTouchUpInside];
    CGRect anchor = [host convertRect:DMRStripCardScreenRect(c) fromCoordinateSpace:[UIScreen mainScreen].coordinateSpace];
    UIView *panel = DMMakeBarMenuPanel(items, host, anchor);
    CGRect pf = panel.frame, hb = host.bounds;
    pf.origin.x = gRStripRight ? CGRectGetMinX(anchor) - pf.size.width - 8.0 : CGRectGetMaxX(anchor) + 8.0;   // (beside the card, on the desktop's side)
    pf.origin.y = MAX(CGRectGetMinY(hb) + 4.0, MIN(CGRectGetMinY(anchor), CGRectGetMaxY(hb) - pf.size.height - 4.0));
    panel.frame = pf;
    [o addSubview:panel];
    DMAXMenuPanel(panel, [NSString stringWithFormat:@"%@ window", name]);
    panel.alpha = 0.0;
    [UIView animateWithDuration:0.10 animations:^{ panel.alpha = 1.0; }];
    DMRStripTouched();
    DM_FEATURE_MARK("recent-strip-card-menu");
    DMLog([NSString stringWithFormat:@"[recentstrip] %@'s card menu (%@)", k, how]);
}
// The keys while Window > Show Recent Windows brought the strip out (the keyboard's focus held for it, as for our own windows: FocusLock.h): Up and
// Down move the selection (the rules' MSBDRStripKeyStep, an accent ring on the card), Return picks it (a swap), Escape ends the reveal. From
// SpringBoard's own presses (StatusBar.x DMOverlayPressesBegan).
static void DMRStripKeySelShow(void) {
    for (NSUInteger i = 0; i < gRStripItems.count; i++) {
        DMRStripCard *c = gRStripCards[gRStripItems[i]];
        if (!c) continue;
        BOOL sel = (int)i == gRStripKeySel && gRStripFocusLock, hc = UIAccessibilityDarkerSystemColorsEnabled();
        c.pic.layer.borderWidth = sel ? 3.0 : (hc ? 1.0 : 0.0);
        if (sel) c.pic.layer.borderColor = [UIColor systemBlueColor].CGColor;
        else if (hc) c.pic.layer.borderColor = [UIColor colorWithWhite:[UIScreen mainScreen].traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? 1.0 : 0.0 alpha:0.45].CGColor;
    }
}
static void DMRStripKeysTake(BOOL take) {
    if (take == (gRStripFocusLock != nil)) return;
    if (take) {
        if (!DMHardwareKeyboardAttached() || !gRStripWindow.windowScene) return;
        DMInstallOverlayEsc();   // (SpringBoard's presses: where the strip's keys are read)
        NSString *how = nil;
        gRStripFocusLock = MSBDFocusLock(gRStripWindow.windowScene, @"MacStatusBar Recent Windows Strip", &how);
        gRStripKeySel = -1;
        DMLog([NSString stringWithFormat:@"[recentstrip] the keys: %@", gRStripFocusLock ? @"Up, Down, Return, Escape" : @"no focus to hold"]);
    } else {
        id l = gRStripFocusLock; gRStripFocusLock = nil; gRStripKeySel = -1;
        MSBDFocusUnlock(l);
        DMRStripKeySelShow();
    }
}
__attribute__((noinline)) static BOOL DMRStripKeys(NSSet<UIPress *> *presses) {
    if (!gRStripFocusLock || gRStripReveal != MSBDRStripRevealMenu) return NO;
    for (UIPress *p in presses) {
        UIKeyboardHIDUsage code = p.key.keyCode;
        if (code == UIKeyboardHIDUsageKeyboardDownArrow || code == UIKeyboardHIDUsageKeyboardUpArrow) {
            gRStripKeySel = MSBDRStripKeyStep(gRStripKeySel, (int)gRStripItems.count, code == UIKeyboardHIDUsageKeyboardDownArrow ? 1 : -1);
            DMRStripTouched(); DMRStripKeySelShow();
            return YES;
        }
        if (code == UIKeyboardHIDUsageKeyboardReturnOrEnter || code == UIKeyboardHIDUsageKeypadEnter) {
            DMRStripCard *c = gRStripKeySel >= 0 && gRStripKeySel < (int)gRStripItems.count ? gRStripCards[gRStripItems[(NSUInteger)gRStripKeySel]] : nil;
            if (c) DMRStripPick(c, NO, @"Return");
            return YES;
        }
        if (code == UIKeyboardHIDUsageKeyboardEscape) { DMRStripRevealEnd(@"Escape"); DMRStripTick(); return YES; }
    }
    return NO;
}

// ---- a waiting window whose window went, and the switch turned off ----
// A window of the list that went since the last look (no window of its app on any desktop, not back on this one): its card waits
// kMSBDRStripGoneWait, then stays as a kept card when iPadOS ended its app (memory, a time-out), or goes (the user's quit, a crash: StatusBar.x's exit
// notes). A kept card goes once its app has a window again or is open full screen.
static void DMRStripGoneStep(CFTimeInterval now) {
    NSMutableDictionary<NSString *, NSDictionary *> *seen = [NSMutableDictionary dictionary];
    for (NSString *k in gRStripList) {
        UIView *st = gRStripStageOf[k]; double at = 0; int why = 0;
        if (st && DMRStripEntryOf(st, &at, &why)) seen[k] = @{ @"at": @(at), @"why": @(why), @"place": DMRStripPlaceOf(st) };
    }
    NSSet<NSString *> *anywhere = nil;
    for (NSString *k in gRStripLastSeen) {
        if (seen[k] || gRStripStageOf[k] || gRStripGone[k] || gRStripGhosts[k] || gRStripLeaving[k]) continue;   // (still here, back on the desktop, picked)
        if (!anywhere) { NSMutableSet *a = [NSMutableSet set]; for (UIView *st in DMAerialStagesAll()) { NSString *b = DMStageBundle(st); if (b.length) [a addObject:b]; } anywhere = a; }
        if ([anywhere containsObject:k]) continue;   // (its window is on another desktop now)
        NSMutableDictionary *g = [gRStripLastSeen[k] mutableCopy]; g[@"since"] = @(now);
        if (!gRStripGone) gRStripGone = [NSMutableDictionary dictionary];
        gRStripGone[k] = g;
    }
    gRStripLastSeen = seen;
    NSString *fullScreen = [DMFrontApp() bundleIdentifier] ?: @"";
    for (NSDictionary<NSString *, NSDictionary *> *set in @[gRStripGone ?: @{}, gRStripGhosts ?: @{}]) {
        for (NSString *k in [set allKeys]) {
            BOOL quit = [gAppsEndedByQuit containsObject:k], crashed = [gAppsEndedInCrash containsObject:k];
            BOOL back = gRStripStageOf[k] != nil || [k isEqualToString:fullScreen];
            double since = set == gRStripGone ? now - [set[k][@"since"] doubleValue] : 1e9;
            MSBDRStripGone step = MSBDRStripGoneStep(since, [gAppsQuitting containsObject:k], quit, crashed, back);
            if (step == MSBDRStripGoneWait || (step == MSBDRStripGoneKeep && set == gRStripGhosts)) continue;
            NSDictionary *g = set[k];
            [gRStripGone removeObjectForKey:k]; [gRStripGhosts removeObjectForKey:k];
            if (step == MSBDRStripGoneKeep) {
                if (!gRStripGhosts) gRStripGhosts = [NSMutableDictionary dictionary];
                gRStripGhosts[k] = @{ @"at": g[@"at"] ?: @(kMSBDRStripSeedAt), @"why": g[@"why"] ?: @(MSBDRStripWhySeeded), @"place": g[@"place"] ?: [NSValue valueWithCGRect:CGRectNull] };
                DM_FEATURE_MARK("recent-strip-kept-card");
                DMLog([NSString stringWithFormat:@"[recentstrip] %@: its window went while it waited (its app ended by iPadOS): its card stays, a pick opens it again", k]);
                continue;
            }
            if (!back) { [gRStripPics removeObjectForKey:k]; [gRStripPicAt removeObjectForKey:k]; }
            DMLog([NSString stringWithFormat:@"[recentstrip] %@: its card goes (%@)", k, back ? @"its app has a window again" : crashed ? @"its app crashed" : @"the app was quit"]);
        }
    }
}
// Settings: the switch turned off (StatusBar.x DMLoadPrefs, before it takes the new value). The windows of this desktop that went in by a swap
// or a drag come back to the desktop (behind the window in front, each out of its card), the ones the user minimized stay minimized (their Dock
// icons bring them back). Every window's entry goes, on every desktop (the state file carries none).
__attribute__((noinline)) static void DMRStripSwitchedOff(void) {
    if (gDMInCtor) return;   // (never inside a constructor: the prefs' first load runs there, the strip never on before it; no UIKit there)
    if (!DMRStripOn()) return;
    NSUInteger back = 0;
    for (UIView *st in [DMAerialStages() copy]) {
        double at = 0; int why = 0;
        if (!DMRStripEntryOf(st, &at, &why) || !DMRStripOffDesktop(st) || !MSBDRStripBackAtOff(why)) continue;
        NSString *b = DMStageBundle(st);
        back++;
        DMFitShownAgain(b);   // (the tiles laid out with it first, as any way back of a minimized window, 1.8.8 H2)
        Class mwc = objc_getClass("AXWindowView");
        if (mwc && [st isKindOfClass:mwc]) { objc_setAssociatedObject(st, kMinimizedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); DMRestoreAnimate(st); }
        else DMRestoreStage(st);
    }
    for (DMNativeWindow *nw in [gNativeWindows copy]) {   // (our own windows the same way)
        double at = 0; int why = 0;
        BOOL backNow = DMRStripEntryOf(nw, &at, &why) && DMRStripHiddenByUs(nw) && MSBDRStripBackAtOff(why);
        DMRStripClearEntry(nw);
        if (backNow) { back++; [nw show]; }
    }
    for (UIView *st in DMAerialStagesAll()) DMRStripClearEntry(st);
    DMLog([NSString stringWithFormat:@"[recentstrip] switched off: %lu window(s) that went in by a swap or a drag back on the desktop, the minimized ones stay minimized", (unsigned long)back]);
    DMRStripReset(@"switched off");
}
// The windows' state file (StatusBar.x DMSaveWindowState: a minimized window's entry, so a respring keeps the order; nothing with the switch off)
// and its way back (DMRestoreStep: before the restore minimizes the window again, as its pending entry).
__attribute__((noinline)) static NSDictionary *DMRStripSavedEntry(UIView *st) {
    double at = 0; int why = 0;
    if (!DMRStripOn() || !DMRStripEntryOf(st, &at, &why) || !isfinite(at)) return nil;
    return @{ @"stripAt": @(at), @"stripWhy": @(why) };
}
__attribute__((noinline)) static void DMRStripRestoreEntry(UIView *st, NSDictionary *saved) {
    double at = 0; int why = 0;
    if (!st || !DMRStripOn() || ![saved isKindOfClass:[NSDictionary class]] || !MSBDRStripSavedEntry(saved[@"stripAt"], saved[@"stripWhy"], &at, &why)) return;
    objc_setAssociatedObject(st, kRStripPendingKey, @[@(at), @(why)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static NSDictionary<NSString *, NSArray<NSString *> *> *DMRStripGroupPics(void) {   // (our own windows' cards: each one's windows' picture keys, most recent first)
    NSMutableDictionary<NSString *, NSArray<NSString *> *> *g = [NSMutableDictionary dictionaryWithCapacity:gRStripGroups.count];
    for (NSString *k in gRStripGroups) {
        NSMutableArray<NSString *> *keys = [NSMutableArray array];
        for (DMNativeWindow *w in gRStripGroups[k]) [keys addObject:DMRStripNativePicKey(w)];
        g[k] = keys;
    }
    return g;
}
static void DMRStripMemoryWarning(void) {   // (the pictures no card shows go; their cards come back with the icon until pictured again)
    NSSet<NSString *> *shown = MSBDRStripPicsFor(gRStripItems ?: @[], gRStripItems.count, DMRStripGroupPics());   // (a card of our own windows: its stack's)
    NSUInteger n = 0;
    for (NSString *k in [gRStripPics allKeys]) if (![shown containsObject:k]) { [gRStripPics removeObjectForKey:k]; [gRStripPicAt removeObjectForKey:k]; n++; }
    if (n) DMLog([NSString stringWithFormat:@"[recentstrip] a memory warning: %lu picture(s) no card shows let go", (unsigned long)n]);
}

// ---- the step ----
static BOOL DMRStripAssistive(void) { return DMAXRunning(); }   // (VoiceOver, Switch Control, Full Keyboard Access: no reveal ends by time)
// What the step reads, as one number (the rules' MSBDRStripSigMix): the screen, the Dock, the menu bar's line, the windows' level, the calm, the
// front app, the strip's own state, and each window's place, size, shown and hidden marks, ours too. No allocation of its own: the windows are the
// watcher's list of this tick (DMAerialStages, kept for the tick on Aerial and MilkyWay4).
static uint64_t DMRStripRestSig(void) {
    uint64_t h = 1469598103934665603ull;
    CGSize sc = [UIScreen mainScreen].bounds.size;
    h = MSBDRStripSigMix(h, ((uint64_t)llround(sc.width * 4.0) << 32) ^ (uint64_t)llround(sc.height * 4.0));
    h = MSBDRStripSigMix(h, ((uint64_t)gDMDockGen << 32) ^ (uint64_t)gDMDockPlaceGen);
    h = MSBDRStripSigMix(h, ((uint64_t)llround(DMTopLimit() * 4.0) << 32) ^ (uint64_t)llround(DMDesiredWindowLevel() * 4.0));
    h = MSBDRStripSigMix(h, (uint64_t)(DMRStripCalm() ? 1 : 0) | ((uint64_t)gRStripShown << 1) | ((uint64_t)gRStripDropTarget << 3) | ((uint64_t)gDMPointerAttached << 4)
                            | ((uint64_t)(gNativeLayer && !gNativeLayer.hidden) << 5) | ((uint64_t)gRStripReveal << 6) | ((uint64_t)gRStripHomeBand << 10));
    h = MSBDRStripSigMix(h, (uint64_t)(uintptr_t)(__bridge void *)DMFrontApp());
    h = MSBDRStripSigMix(h, (uint64_t)DMMSWCurId());   // (the Mac Switcher's desktop: our own minimized windows wait in their own desktop's strip)
    for (UIView *st in DMAerialStages()) {
        CGRect f = st.frame;
        h = MSBDRStripSigMix(h, (uint64_t)(uintptr_t)(__bridge void *)st);
        h = MSBDRStripSigMix(h, ((uint64_t)(llround(f.origin.x) & 0xffff) << 48) ^ ((uint64_t)(llround(f.origin.y) & 0xffff) << 32) ^ ((uint64_t)(llround(f.size.width) & 0xffff) << 16) ^ (uint64_t)(llround(f.size.height) & 0xffff));
        h = MSBDRStripSigMix(h, (uint64_t)(st.hidden ? 1 : 0) | (st.alpha > 0.05 ? 2 : 0) | (DMStageMinimized(st) ? 4 : 0) | (DMRStripHiddenByUs(st) ? 8 : 0)
                                | ([objc_getAssociatedObject(st, kStageClosingKey) boolValue] ? 16 : 0) | (objc_getAssociatedObject(st, kRStripAtKey) ? 32 : 0));
    }
    for (DMNativeWindow *nw in gNativeWindows) {
        CGRect f = nw.frame;
        h = MSBDRStripSigMix(h, ((uint64_t)(llround(f.origin.x) & 0xffff) << 48) ^ ((uint64_t)(llround(f.origin.y) & 0xffff) << 32) ^ ((uint64_t)(llround(f.size.width) & 0xffff) << 16) ^ (uint64_t)(llround(f.size.height) & 0xffff));
        h = MSBDRStripSigMix(h, (uint64_t)(nw.hidden ? 1 : 0) | (nw.alpha > 0.05 ? 2 : 0) | (nw.dm_wasMinimized ? 4 : 0) | (objc_getAssociatedObject(nw, kRStripAtKey) ? 8 : 0));
    }
    return h;
}
// The rules' answer for what the last look read (laid: cards or a drop target laid out; covered: the cover now), applied at once: the tick's, a
// drag's, a flight's.
static MSBDRStripShow DMRStripApplyShow(BOOL laid, BOOL covered, NSString *why) {
    MSBDRStripState s = { 1, laid ? (int)gRStripItems.count + (DMRStripDragHolds() ? 1 : 0) : 0, gRStripCalmNow, gRStripFrontNow, gRStripAnyShown, covered, gRStripReveal != 0, gRStripHomeBand, gRStripDropTarget };   // (a card dragged out counts)
    gRStripMayRevealNow = MSBDRStripMayReveal(s);
    MSBDRStripShow show = MSBDRStripShowFor(s);
    DMRStripShowAs(show, why ?: (!gRStripList.count && !gRStripDropTarget ? @"nothing to show" : !gRStripCalmNow ? @"something is over the windows" : !gRStripFrontNow ? @"the windows are behind a full-screen app"
                                : !laid ? @"nothing to show" : gRStripDropTarget ? @"a window dragged to its edge" : !gRStripAnyShown ? @"no window on screen" : covered && !gRStripReveal ? @"a window covers it"
                                : gRStripReveal == MSBDRStripRevealPointer ? @"the pointer at the edge" : gRStripReveal == MSBDRStripRevealMenu ? @"Window > Show Recent Windows"
                                : gRStripReveal == MSBDRStripRevealFlight ? @"a window flew in" : @"the desktop is free"));
    return show;
}
__attribute__((noinline)) static void DMRStripTick(void) {
    gRStripTicks++;
    DMRStripHomeBandStep();   // (the Home Screen's band: a few numbers; handed on only when it changes)
    if (!DMRStripOn()) {
        if ((gRStripWindow && !gRStripWindow.hidden) || gRStripCards.count || gRStripPics.count || gRStripGhosts.count || gRStripSysHover) DMRStripReset(@"switched off, or not this engine");
        return;
    }
    if (!DMWindowWorkNeeded() && !gRStripGhosts.count && !gRStripGone.count && !gNativeWindows.count) { gRStripStageOf = nil; DMRStripShowAs(MSBDRStripHidden, @"no window"); DMRStripSysHoverUpdate(NO); return; }
    CFTimeInterval now = CACurrentMediaTime();
    // (nothing at rest: the look is skipped while nothing it reads changed and nothing time-bound waits -- the rules' MSBDRStripTickWorks)
    static uint64_t lastSig = 0;
    uint64_t sig = DMRStripRestSig();
    // (a reveal is time-bound only as the rules' MSBDRStripRevealTimed say: a pointer held in the band, or the Window menu's or the handle's under
    //  VoiceOver or Switch Control, waits for an event -- the step rests meanwhile; before, every tick worked for as long as the pointer stayed there)
    BOOL menuLike = gRStripReveal == MSBDRStripRevealMenu || gRStripReveal == MSBDRStripRevealHandle;
    BOOL timed = MSBDRStripRevealTimed(gRStripReveal, gRStripPointerOutAt > 0, menuLike && DMRStripAssistive()) || gRStripPointerOutAt > 0 || gRStripGone.count || gRStripPicDue.count
                 || gRStripLeavingAt.count || gRStripRelaunch.count || gRStripDragWin || gRStripCardDrag;
    if (!MSBDRStripTickWorks(sig != lastSig, timed)) return;
    lastSig = sig;
    gRStripWorkTicks++;
    for (NSString *k in [gRStripLeavingAt allKeys]) if (now - [gRStripLeavingAt[k] doubleValue] > 1.5) { [gRStripLeaving removeObjectForKey:k]; [gRStripLeavingAt removeObjectForKey:k]; }   // (a pick that did not take)
    if (gRStripDragWin && now - gRStripDragAt > 2.0) { gRStripDragWin = nil; DMRStripSetDropTarget(NO); }   // (a drag that never ended: its window went meanwhile)
    for (NSString *k in [gRStripRelaunch allKeys]) if (now >= [gRStripRelaunch[k][@"due"] doubleValue]) { CGRect f = [gRStripRelaunch[k][@"place"] CGRectValue]; [gRStripRelaunch removeObjectForKey:k]; DMRStripRelaunchNow(k, f); }
    BOOL laid = DMRStripRelayout(gRStripShown != MSBDRStripHidden);
    DMRStripGoneStep(now);
    // the picture of a window that left the front (a burst pictures only the one in front: the windows behind keep this one)
    NSString *front = DMRStripFrontNow(), *was = gRStripFront;
    if (![front isEqualToString:was]) {
        if (was.length && DMRStripStageOnScreen(gRStripStageOf[was])) { if (!gRStripPicDue) gRStripPicDue = [NSMutableDictionary dictionary]; gRStripPicDue[was] = @(now + 0.6); }
        gRStripFront = [front copy];
    }
    BOOL calmForPic = !DMSwitcherVisible() && !gMSWOpen && !gMSWClosing && DMMSWSessionIdle() && !DMWinCardBusy();
    for (NSString *k in [gRStripPicDue allKeys]) {
        if ([gRStripPicDue[k] doubleValue] > now) continue;
        UIView *st = gRStripStageOf[k];
        if (st && !calmForPic) continue;   // (asked again at the next tick)
        [gRStripPicDue removeObjectForKey:k];
        if (DMRStripStageOnScreen(st) && ![k isEqualToString:front]) DMRStripPicture(st, k, @"it left the front");
    }
    // (pictures kept: the list's cards and 3 more down it, and the 6 newest of windows on screen, for a burst; none of a window that went)
    if (gRStripPics.count > (NSUInteger)kMSBDRStripMax) {
        NSMutableArray<NSString *> *onScreen = [NSMutableArray array];
        for (NSString *k in gRStripPics) if (DMRStripStageOnScreen(gRStripStageOf[k])) [onScreen addObject:k];
        [onScreen sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) { return [gRStripPicAt[b] compare:gRStripPicAt[a] ?: @0]; }];
        NSSet<NSString *> *recent = [NSSet setWithArray:[onScreen subarrayWithRange:NSMakeRange(0, MIN(onScreen.count, (NSUInteger)kMSBDRStripMax))]];
        NSSet<NSString *> *cards = MSBDRStripPicsFor(gRStripList, gRStripItems.count + kMSBDRStripPicKeepMore, DMRStripGroupPics());   // (a card of our own windows: its stack's)
        for (NSString *k in [gRStripPics allKeys]) {
            if ([cards containsObject:k] || [recent containsObject:k]) continue;
            [gRStripPics removeObjectForKey:k]; [gRStripPicAt removeObjectForKey:k];
        }
    }
    BOOL covered = DMRStripCoveredNow(laid);
    // the reveals' ends (the rules': the pointer's, the Window menu's, a flight's peek)
    if (gRStripReveal && MSBDRStripRevealEnds(gRStripReveal, now - gRStripTouchedAt, gRStripPointerOutAt > 0 ? now - gRStripPointerOutAt : 0, DMRStripAssistive()))
        DMRStripRevealEnd(gRStripReveal == MSBDRStripRevealPointer ? @"the pointer moved away" : gRStripReveal == MSBDRStripRevealFlight ? @"the window landed" : @"untouched for 6 s");
    if (gRStripReveal == MSBDRStripRevealPointer && !gDMPointerAttached) DMRStripRevealEnd(@"the pointer went");
    if (gRStripReveal && (!gRStripCalmNow || !gRStripFrontNow || !laid)) DMRStripRevealEnd(@"the windows went, or something came over them");
    MSBDRStripShow show = DMRStripApplyShow(laid, covered, nil);
    DMRStripHandleUpdate();
    if (show != MSBDRStripHidden && gRStripWindow && !gRStripWindow.hidden) {   // (the windows' level moved: a full-screen app came or went)
        CGFloat level = DMDesiredWindowLevel() + 0.5;
        if (fabs(gRStripWindow.windowLevel - level) > 0.01) gRStripWindow.windowLevel = level;
    }
    DMRStripSysHoverUpdate(gDMPointerAttached && (gRStripMayRevealNow || gRStripReveal == MSBDRStripRevealPointer));
}

// ---- the pointer ----
// The pointer's place from SpringBoard's system gestures window of the iPad (every pointer move on that display reaches it): at the strip's edge
// while it stepped aside, it comes out; past the band, its reveal ends a moment later. Only while wanted: a trackpad or mouse attached and the
// strip stepped aside with something to show, or out by the pointer.
static void DMRStripSysHoverSeen(UIHoverGestureRecognizer *g) {
    UIView *v = g.view;
    BOOL inside = g.state == UIGestureRecognizerStateBegan || g.state == UIGestureRecognizerStateChanged;
    CFTimeInterval now = CACurrentMediaTime();
    if (!inside) { if (gRStripReveal == MSBDRStripRevealPointer && !gRStripPointerOutAt) gRStripPointerOutAt = now; return; }
    UIScreen *s = [UIScreen mainScreen];
    CGPoint p = [v convertPoint:[g locationInView:v] toCoordinateSpace:s.coordinateSpace];
    if (gRStripReveal == MSBDRStripRevealPointer) {
        if (MSBDRStripPointerLeft(p.x, gRStripBand, gRStripRight)) { if (!gRStripPointerOutAt) gRStripPointerOutAt = now; }
        else gRStripPointerOutAt = 0;
        return;
    }
    if (!gRStripMayRevealNow || !MSBDRStripPointerAtEdge(p.x, s.bounds.size.width, gRStripRight)) return;
    if (p.y < gRStripSpan.y - 40.0 || p.y > MSBDRMaxY(gRStripSpan) + 40.0) return;   // (at the edge beside the cards, not in the corners)
    gRStripReveal = MSBDRStripRevealPointer; gRStripPointerOutAt = 0;
    DM_FEATURE_MARK("recent-strip-reveal-pointer");
    DMLog(@"[recentstrip] the pointer at the edge: the strip comes out");
    DMRStripTick();
}
static void DMRStripSysHoverUpdate(BOOL want) {
    UIWindow *w = gRStripSysHoverWindow;
    if (want && gRStripSysHover && w && !w.hidden) return;
    if (!want) {
        if (gRStripSysHover) { [gRStripSysHover.view removeGestureRecognizer:gRStripSysHover]; gRStripSysHover = nil; gRStripSysHoverWindow = nil; }
        return;
    }
    if (gRStripSysHover) { [gRStripSysHover.view removeGestureRecognizer:gRStripSysHover]; gRStripSysHover = nil; }
    for (UIWindow *x in DMAllWindows()) {
        if (x.screen != [UIScreen mainScreen] || ![NSStringFromClass([x class]) isEqualToString:@"_UISystemGestureWindow"]) continue;
        UIHoverGestureRecognizer *h = [[DMPtrHoverRecognizer alloc] initWithTarget:[DMRStripTarget shared] action:@selector(sysHover:)];
        h.cancelsTouchesInView = NO; h.delaysTouchesBegan = NO; h.delaysTouchesEnded = NO;
        [x addGestureRecognizer:h];
        gRStripSysHover = h; gRStripSysHoverWindow = x;
        return;
    }
    static BOOL told = NO;   // (said once)
    if (!told) { told = YES; DMLog(@"[recentstrip] no system gestures window on the iPad's screen: the pointer at the edge cannot bring the strip out (Window > Show Recent Windows can)"); }
}

// ---- the Window menu's rows ----
// The handle tapped or swiped toward the desktop: the strip comes out over the windows (the rules' end: 6 s untouched, never while VoiceOver or
// Switch Control run).
static void DMRStripHandleReveal(NSString *why) {
    if (!DMRStripOn() || !gRStripMayRevealNow) return;
    gRStripReveal = MSBDRStripRevealHandle; DMRStripTouched();
    DM_FEATURE_MARK("recent-strip-reveal-handle");
    DMLog([NSString stringWithFormat:@"[recentstrip] %@: the strip comes out", why]);
    DMRStripTick();
}
// Window > Show Recent Windows: offered while the strip has stepped aside with something to show.
__attribute__((noinline)) static BOOL DMRStripMenuOffered(void) { return DMRStripOn() && gRStripMayRevealNow && gRStripItems.count > 0; }
__attribute__((noinline)) static void DMRStripMenuReveal(void) {
    if (!DMRStripOn() || !gRStripMayRevealNow) return;
    gRStripReveal = MSBDRStripRevealMenu; DMRStripTouched();
    DM_FEATURE_MARK("recent-strip-reveal-menu");
    DMLog(@"[recentstrip] Window > Show Recent Windows: the strip comes out");
    DMRStripTick();
    if (gRStripReveal == MSBDRStripRevealMenu) DMRStripKeysTake(YES);   // (Up, Down, Return, Escape)
}
// Window > Move to Strip: the window in front into the strip (with the switch on that is what Command-M and the yellow light do: DMMinimizeActiveApp),
// offered while a window of the engine is focused in front.
__attribute__((noinline)) static BOOL DMRStripMoveOffered(void) { BOOL ours = NO; return DMRStripOn() && DMRStripFrontWindow(&ours) != nil; }

// ---- debug (rstrip: the state, read-only; rstrip_reveal: as the Window menu's row; rstrip_edge: as the pointer at the edge; rstrip_pick_<n>: a
// tap on the nth card; rstrip_shiftpick_<n>: the same with Shift) ----
__attribute__((noinline)) static BOOL DMRStripTrigger(NSString *cmd) {
    if ([cmd isEqualToString:@"rstrip"]) {
        NSMutableString *t = [NSMutableString stringWithFormat:@"[rstrip] on %d (pref %d), shown %d, reveal %d, may reveal %d, front %@, list %@, items %@, band {%.0f, %.0f, %.0f, %.0f}, cards' part {%.0f, %.0f, %.0f, %.0f}, right %d, entries",
            DMRStripOn(), gRStripPref, (int)gRStripShown, gRStripReveal, gRStripMayRevealNow, gRStripFront.length ? gRStripFront : @"none", [gRStripList componentsJoinedByString:@" "],
            [gRStripItems componentsJoinedByString:@" "], gRStripBand.x, gRStripBand.y, gRStripBand.w, gRStripBand.h, gRStripSpan.x, gRStripSpan.y, gRStripSpan.w, gRStripSpan.h, gRStripRight];
        double clock = DMRStripClock();
        for (NSString *k in gRStripList) { double at = 0; int why = 0; if (DMRStripEntryOf(gRStripStageOf[k], &at, &why)) [t appendFormat:@" %@ %.1f s ago (why %d)", k, clock - at, why]; }
        [t appendFormat:@"; kept cards %@, deciding %@; pictures", [gRStripGhosts.allKeys componentsJoinedByString:@" "], [gRStripGone.allKeys componentsJoinedByString:@" "]];
        for (NSString *k in gRStripPics) [t appendFormat:@" %@ %.0fx%.0f %.0f s", k, gRStripPics[k].bounds.size.width, gRStripPics[k].bounds.size.height, CACurrentMediaTime() - [gRStripPicAt[k] doubleValue]];
        [t appendFormat:@"; window %@ level %.1f hidden %d; system hover %@; ticks %u, work ticks %u, layouts %u, pictures taken %u", gRStripWindow ? @"made" : @"none", gRStripWindow.windowLevel, gRStripWindow.hidden,
            gRStripSysHover ? @"on" : @"off", gRStripTicks, gRStripWorkTicks, gRStripLayouts, gRStripPicsTaken];
        DMLog(t);
        return YES;
    }
    if ([cmd isEqualToString:@"rstrip_reveal"]) { DMRStripMenuReveal(); return YES; }
    if ([cmd isEqualToString:@"rstrip_edge"]) {
        if (gRStripMayRevealNow) { gRStripReveal = MSBDRStripRevealPointer; gRStripPointerOutAt = 0; DMLog(@"[rstrip] as the pointer at the edge"); DMRStripTick(); }
        else DMLog(@"[rstrip] the strip has not stepped aside: nothing to bring out");
        return YES;
    }
    BOOL shift = [cmd hasPrefix:@"rstrip_shiftpick_"];
    if ([cmd hasPrefix:@"rstrip_pick_"] || shift) {
        NSInteger i = [[cmd substringFromIndex:shift ? 17 : 12] integerValue];
        NSString *k = i >= 0 && i < (NSInteger)gRStripItems.count ? gRStripItems[(NSUInteger)i] : nil;
        DMRStripCard *c = k ? gRStripCards[k] : nil;
        if (c) DMRStripPick(c, shift, shift ? @"the debug Shift pick" : @"the debug pick"); else DMLog([NSString stringWithFormat:@"[rstrip] no card %ld", (long)i]);
        return YES;
    }
    return NO;
}
