// WindowCards.h -- iPadOS's App Switcher cards for the engines' windows (1.7.0, engine parity with Stage Manager), included by StatusBar.x after
// MacSwitcher.h. KT, 28 Oct: "in stage manager the windowed apps appear in the app switcher since they are recognized as real apps ... can we make
// it so they behave the same way". Every app that has a window of Aerial, Zetsu or MilkyWay4 has its card, as a Stage Manager window has: a tap
// on it brings that window forward (DMCardTakes, 1.5.2 item 11), a swipe up quits the app (SpringBoard's own quit) and its window closes (each
// engine closes the window of an app that is gone; MilkyWay4's by DMMilkyWayCloseDeadWindows).
// Why the windows had none (M1 15.6.1, swtrace_ and the code read on the device): SpringBoard adds a card only from its main layout state's
// transitions -- -[SBMainSwitcherViewController _addAppLayoutToFront:removeAppLayout:], called from the switcher animation's start
// (SBUISwitcherAnimationController) and from -layoutStateTransitionCoordinator:transitionDidEndWithTransitionContext:. The engines show the app's
// scene in a window of their own, outside that state, with no such transition: an app opened straight into a window (Dock, Home Screen, Spotlight,
// the Go menu, the restore after a respring) had no card on any engine; one opened full screen first kept the card it got then.
// The fix tells SpringBoard's model, the place the cards live -- no list of ours: -[SBMainSwitcherViewController addAppLayoutForDisplayItem:
// completion:] is SpringBoard's own entry for an app scene that gets a card without becoming the layout state. Read on 15.6.1: when no card holds
// the display item, it builds the same one-app layout a full-screen app's card is (-[SBAppLayout initWithItemsForLayoutRoles:@{1: item}
// configuration:1 environment:1]) and inserts it first with -_insertAppLayout:atIndex:0 modelMutationBlock:^{ [model addToFront:] } completion:
// (the switcher's own insertion: animated while it shows, saved with the others). The display item is SpringBoard's own for the window's scene
// (+[SBDisplayItem applicationDisplayItemWithBundleIdentifier:sceneIdentifier:]), so the card is the one a full-screen open of that scene finds.
// The window in front is the most recent app, as a full-screen app is when its transition ends: its card goes first with -_addAppLayoutToFront:,
// SpringBoard's own call for that (also its switcher's "bring to front"), never while a switcher shows or a workspace transaction runs (a gesture,
// an app switch: -[SBWorkspace currentTransaction]), so the list never changes under a running switcher animation.
// The card's picture: below (SpringBoard's own picture of the window's scene). Kill switch /tmp/msb-nowincards (debug builds).
// iPadOS 16+ (read on 17.5.1, 29 Oct): the switcher lives in SBMainSwitcherControllerCoordinator, one SBSwitcherController per screen. The same
// entry is the coordinator's -addAppLayoutForDisplayItem:windowScene:completion:, the same code as 15's but for one screen: a card already holds the
// item = only the completion; else -[SBAppLayout initWithItemsForLayoutRoles:@{1: item} configuration:1 environment:1 preferredDisplayOrdinal:] (the
// ordinal of that screen's layout state), inserted first by -_insertAppLayout:atIndex:0 contentViewController:<that screen's switcher's>
// modelMutationBlock:completion:. -_addAppLayoutToFront: and -recentAppLayouts are the coordinator's, of 15's shapes; the scene handle the picture is
// saved to comes from the screen's SBSwitcherController (-_deviceApplicationSceneHandleForDisplayItem:, the view controller's on 15). On 17.5.1 the
// windows had no card before this either (Aerial 5.1: a window opened straight and one restored after a respring; Zetsu 1.6.6: the same).
// 16.7.7 (iPad 2, 29 Oct): the same calls of the same shapes; the windows had no card before this either (Aerial 5.1: restored after a respring).
// 18.5 (A12Z, 29 Oct): the same calls of the same shapes (the add call's code: a card holding the item = only the completion, else the one-app
// layout, configuration 1, environment 1, the screen's ordinal, inserted at 0; -_addAppLayoutToFront: the same tail call), and the same picture calls.
// Opened on the versions where it was read and checked on the engines (MSBDWinCardOSChecked): 15 to 18.
#include "WindowCardPlan.h"

static const void *kWinCardAskedKey = &kWinCardAskedKey;   // per window: NSNumber, how many times SpringBoard was asked for its card
static const void *kWinCardAskedAtKey = &kWinCardAskedAtKey;   // per window: NSNumber, when (CACurrentMediaTime)
static const void *kWinCardPicturedKey = &kWinCardPicturedKey;   // per window: its card has a picture of ours
static const void *kWinCardPicAtKey = &kWinCardPicAtKey;   // per window: @[when its card's picture was taken (CACurrentMediaTime), its shape then]
static NSMutableDictionary<NSString *, NSNumber *> *gWinCardFrontAt;   // app -> when its window was last the one in front (DMWinCardsTick)
static BOOL DMWinCardsOff(void) { return DMTestFlag("/tmp/msb-nowincards"); }
// (a window's shape for its picture: the screen's orientation and the window's size -- a picture of another shape is not current,
//  MSBDWinCardPictureCurrent)
static NSString *DMWinCardShape(UIView *stage) {
    long o = ((long (*)(id, SEL))objc_msgSend)([UIApplication sharedApplication], NSSelectorFromString(@"activeInterfaceOrientation"));
    return [NSString stringWithFormat:@"%ld %@", o, NSStringFromCGSize(stage.bounds.size)];
}
static void DMWinCardTaken(UIView *stage) {   // (its card's picture is of now: ours taken, or SpringBoard's adopted)
    objc_setAssociatedObject(stage, kWinCardPicturedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(stage, kWinCardPicAtKey, @[@(CACurrentMediaTime()), DMWinCardShape(stage)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void DMWinCardAdoptInstall(void);   // (below: SpringBoard's own pictures of the windows' scenes become their cards')
// (an app being quit -- our red light, Force Quit, Activity Monitor's Quit (DMForceQuitBundle: Aerial's own close animation leaves no
//  kStageClosingKey), or gone by itself: its window shows a moment longer, but nothing of it is pictured or adopted -- iPad 2 16.7.7, a red-light
//  quit: SpringBoard's suspend picture of the dying app was placed, then "did not keep its window's picture" as it ended)
static BOOL DMWinCardAppGoing(NSString *b) { return DMAppQuitRecently(b) || DMAppJustExited(b); }
static BOOL gWinCardScened = NO;   // YES: 16+'s coordinator, whose add call takes the window's screen (-addAppLayoutForDisplayItem:windowScene:completion:)
// The switcher with SpringBoard's calls as read on 15.6.1 / 17.5.1 (nil: not here, or of another shape -- nothing is asked, the cards stay iPadOS's).
static id DMWinCardSwitcher(void) {
    static int checked = -1;
    if (checked == 0) return nil;
    BOOL anyOS = DMTestFlag("/tmp/msb-wincards-anyos");   // (debug: try the same calls on a version not checked yet)
    NSInteger major = [NSProcessInfo processInfo].operatingSystemVersion.majorVersion;
    if (!anyOS && !MSBDWinCardOSChecked(major)) { if (checked < 0) DMLog([NSString stringWithFormat:@"[wincard] iPadOS %ld: windows' App Switcher cards stay as iPadOS has them (not checked on this iPadOS yet)", (long)major]); checked = 0; return nil; }
    id sw = DMSwitcherController();
    if (!sw) return nil;   // (not made yet: asked again later)
    if (checked == 1) return sw;
    Class di = objc_getClass("SBDisplayItem");
    Method dm = di ? class_getClassMethod(di, NSSelectorFromString(@"applicationDisplayItemWithBundleIdentifier:sceneIdentifier:")) : NULL;
    BOOL scened = ![sw isKindOfClass:objc_getClass("SBMainSwitcherViewController")];   // (15: the view controller; 16+: the coordinator, DMSwitcherController)
    BOOL ok = dm && [DMSMSigOfMethod(dm) isEqualToString:DMSMExpect(@encode(id), @encode(id), @encode(id), NULL)]
        && (scened ? DMSMSigOK(sw, NSSelectorFromString(@"addAppLayoutForDisplayItem:windowScene:completion:"), DMSMExpect(@encode(void), @encode(id), @encode(id), @encode(id), NULL), "addAppLayoutForDisplayItem:windowScene:completion:")
                     && DMSMSigOK(sw, NSSelectorFromString(@"switcherControllerForWindowScene:"), DMSMSigObjObj(), "switcherControllerForWindowScene:")
                   : DMSMSigOK(sw, NSSelectorFromString(@"addAppLayoutForDisplayItem:completion:"), DMSMExpect(@encode(void), @encode(id), @encode(id), NULL), "addAppLayoutForDisplayItem:completion:"))
        && DMSMSigOK(sw, NSSelectorFromString(@"_addAppLayoutToFront:"), DMSMExpect(@encode(void), @encode(id), NULL), "_addAppLayoutToFront:")
        && DMSMSigOK(sw, NSSelectorFromString(@"recentAppLayouts"), DMSMExpect(@encode(id), NULL), "recentAppLayouts");
    checked = ok ? 1 : 0;
    gWinCardScened = ok && scened;
    if (ok) { DMInitSwitcherLog(); DMWinCardAdoptInstall(); }   // (the switcher's environment events: the cards' pictures as iPadOS's App Switcher comes, DMWinCardsSwitcherComing; SpringBoard's own pictures of the windows: DMWinCardAdopt)
    DMLog(ok ? [NSString stringWithFormat:@"[wincard] every window gets its App Switcher card (SpringBoard's own add and bring-to-front calls are here: %@)", scened ? @"the coordinator's, per screen" : @"the switcher view controller's"]
             : @"[wincard] SpringBoard's add / bring-to-front calls are not as read on 15.6.1 / 17.5.1: windows' App Switcher cards stay as iPadOS has them");
    return ok ? sw : nil;
}
// 16+: the screen whose switcher gets the window's card -- the window's own, when SpringBoard's coordinator has a switcher for it, else the iPad's own
// screen's (nil: neither has one: nothing is asked). Its switcher controller in *switcher (the one with the scene handles and the picture cache).
// 15 has one switcher: nil scene, *switcher = the view controller.
static UIWindowScene *DMWinCardWindowScene(id sw, UIView *stage, id *switcher) {
    if (switcher) *switcher = gWinCardScened ? nil : sw;
    if (!gWinCardScened || !sw) return nil;
    UIWindow *w = [stage isKindOfClass:[UIWindow class]] ? (UIWindow *)stage : stage.window;   // (a Zetsu window is a UIWindow; Aerial's and MilkyWay's stages are views in one)
    UIWindowScene *own = w.windowScene, *main = MSBDMainWindowScene();
    for (UIWindowScene *sc in @[own ?: (id)[NSNull null], main ?: (id)[NSNull null]]) {
        if (![sc isKindOfClass:[UIWindowScene class]]) continue;
        id c = nil;
        @try { c = ((id (*)(id, SEL, id))objc_msgSend)(sw, NSSelectorFromString(@"switcherControllerForWindowScene:"), sc); } @catch (NSException *e) { c = nil; }
        if (c) { if (switcher) *switcher = c; return sc; }
    }
    return nil;
}
// The switcher's cards in their order (0 = most recent), each as its apps' bundle identifiers; layouts: the same cards (SBAppLayout).
static NSArray<NSArray<NSString *> *> *DMWinCardList(id sw, NSArray **layouts) {
    NSMutableArray *out = [NSMutableArray array];
    id list = sw ? ((id (*)(id, SEL))objc_msgSend)(sw, NSSelectorFromString(@"recentAppLayouts")) : nil;
    if (![list isKindOfClass:[NSArray class]]) { if (layouts) *layouts = @[]; return out; }
    for (id l in (NSArray *)list) {
        NSMutableArray *bs = [NSMutableArray array];
        id items = [l respondsToSelector:NSSelectorFromString(@"allItems")] ? DMCall(l, @"allItems") : nil;
        if ([items isKindOfClass:[NSArray class]]) for (id it in (NSArray *)items) { NSString *b = DMSMItemBundle(it); if (b.length) [bs addObject:b]; }
        [out addObject:bs];
    }
    if (layouts) *layouts = list;
    return out;
}
// The window's scene: the one its view shows (Aerial, MilkyWay4), else the app's scene SpringBoard last updated for it, else FrontBoard's foreground
// one (a Zetsu window has no view that names its scene: DMStageScene answers nil there, M1 par07).
static id DMWinCardScene(UIView *stage, NSString *b) {
    id sc = DMStageScene(stage, b);
    if (!sc) sc = DMSceneForBundle(b);
    if (!sc) sc = DMFrontBoardSceneForBundle(b);
    return sc;
}
static NSString *DMWinCardSceneID(UIView *stage, NSString *b) {   // (the window's scene: "sceneID:<bundle>-default" / "-<UUID>")
    id sc = DMWinCardScene(stage, b);
    NSString *sid = nil; @try { sid = sc ? [sc valueForKey:@"identifier"] : nil; } @catch (id e) { sid = nil; }
    return [sid isKindOfClass:[NSString class]] && [sid hasPrefix:@"sceneID:"] ? sid : nil;
}
static void DMWinCardAsk(id sw, UIView *stage, NSString *b, NSString *sid, NSString *why) {
    id item = nil;
    @try { item = ((id (*)(id, SEL, id, id))objc_msgSend)((id)objc_getClass("SBDisplayItem"), NSSelectorFromString(@"applicationDisplayItemWithBundleIdentifier:sceneIdentifier:"), b, sid); }
    @catch (NSException *e) { item = nil; }
    if (!item) { DMLog([NSString stringWithFormat:@"[wincard] %@: no display item for %@", b, sid]); return; }
    UIWindowScene *screen = DMWinCardWindowScene(sw, stage, NULL);   // (16+: the screen whose switcher takes the card; 15: none)
    if (gWinCardScened && !screen) { DMLog([NSString stringWithFormat:@"[wincard] %@: no switcher for its window's screen: not asked", b]); return; }
    NSInteger n = [objc_getAssociatedObject(stage, kWinCardAskedKey) integerValue] + 1;
    objc_setAssociatedObject(stage, kWinCardAskedKey, @(n), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(stage, kWinCardAskedAtKey, @(CACurrentMediaTime()), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSString *bb = [b copy];
    void (^done)(BOOL, BOOL) = ^(BOOL finished, BOOL other) { if (DMTestFlag("/tmp/macstatusbar-debug")) DMLog([NSString stringWithFormat:@"[wincard] %@: SpringBoard's insertion done (%d %d)", bb, finished, other]); };
    @try {
        if (gWinCardScened) ((void (*)(id, SEL, id, id, id))objc_msgSend)(sw, NSSelectorFromString(@"addAppLayoutForDisplayItem:windowScene:completion:"), item, screen, done);
        else ((void (*)(id, SEL, id, id))objc_msgSend)(sw, NSSelectorFromString(@"addAppLayoutForDisplayItem:completion:"), item, done);
    }
    @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[wincard] %@: SpringBoard's add failed: %@", b, e.reason]); return; }
    DM_FEATURE_MARK("window-app-switcher-card");
    DMLog([NSString stringWithFormat:@"[wincard] %@ has a window and no App Switcher card (%@): SpringBoard's own card asked for its scene %@", b, why, [sid substringFromIndex:8]]);
    __weak UIView *ws = stage;   // (its picture once the card is in: the next turn of the run loop)
    dispatch_async(dispatch_get_main_queue(), ^{ UIView *s2 = ws; extern BOOL DMWinCardPictureFlag(UIView *, NSString *); if (s2) DMWinCardPictureFlag(s2, bb); });
}
// SpringBoard in a workspace transaction (an app switch, a switcher gesture, the App Switcher coming or going): no list change then.
static BOOL DMWinCardBusy(void) {
    id ws = DMCall(objc_getClass("SBMainWorkspace"), @"sharedInstance");
    SEL t = NSSelectorFromString(@"currentTransaction");
    if (![ws respondsToSelector:t] || !DMSMSigOK(ws, t, DMSMExpect(@encode(id), NULL), "currentTransaction")) return YES;   // (cannot tell: wait)
    return ((id (*)(id, SEL))objc_msgSend)(ws, t) != nil;
}
// ---- the card's picture ----
// SpringBoard pictures an app when it leaves the screen (its suspend snapshot: the scene's own capture, -[FBScene createSnapshotWithContext:] and
// -[FBSceneSnapshot capture], saved by -[SBDeviceApplicationSceneHandle saveSuspendSnapshot:]), and a card shows the newest picture whose reference
// size is the full screen's (-[SBAppSwitcherSnapshotImageCache _loadSnapshotForRequest:withDisplayItem:inAppLayout:] asks the scene handle for the
// best snapshot of that size). A window's app never leaves the screen and its scene is the window's size, so there was no picture the card could
// use: the card stayed black (M1 15.6.1: Tips, Settings, App Store windows; 1.5.2's cards of windows too) or showed a full-screen picture from long
// before. So the window's scene is pictured the same way, and the picture says where the app's content lies in a full screen -- the reference size
// the screen's, the content frame the window's content fitted into it (-setReferenceSize:, -setContentFrame:; SpringBoard places a picture
// that is smaller than its card by that frame: -[SBAppSwitcherReusableSnapshotView _snapshotImageFrameForCacheEntry:]). When the card is made, when
// its window leaves the front, and whenever iPadOS's App Switcher comes up while the picture is not current (the windows' content then, as the
// full-screen app's card shows its content then; one window per turn of the run loop, DMWinCardsSwitcherComing).
typedef NS_ENUM(NSInteger, DMWinPicMode) { DMWinPicFit = 0, DMWinPicPlace = 1, DMWinPicFill = 2, DMWinPicRaw = 3, DMWinPicOff = 4 };
static DMWinPicMode DMWinCardPicMode(void) {
#if DEBUG
    NSString *m = [[NSString stringWithContentsOfFile:@"/tmp/msb-wincard-pic" encoding:NSUTF8StringEncoding error:nil] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];   // (debug: place / fill / raw / off, to compare)
    if ([m isEqualToString:@"place"]) return DMWinPicPlace;
    if ([m isEqualToString:@"fill"]) return DMWinPicFill;
    if ([m isEqualToString:@"raw"]) return DMWinPicRaw;
    if ([m isEqualToString:@"off"]) return DMWinPicOff;
#endif
    return DMWinPicFit;
}
static id DMWinCardItem(id sw, NSString *b) {   // (the card's display item of this app: a one-app card's)
    NSArray *layouts = nil; NSArray<NSArray<NSString *> *> *cards = DMWinCardList(sw, &layouts);
    for (NSUInteger i = 0; i < cards.count && i < layouts.count; i++) {
        if (cards[i].count != 1 || ![cards[i].firstObject isEqualToString:b]) continue;
        id items = DMCall(layouts[i], @"allItems");
        return [items isKindOfClass:[NSArray class]] ? [(NSArray *)items firstObject] : nil;
    }
    return nil;
}
// owner: the switcher that has the scene handles and the picture cache (15: the view controller; 16+: the screen's SBSwitcherController).
static BOOL DMWinCardPicOK(id owner, id handle, id scene) {   // (every call the picture makes, of the shape read on 15.6.1 / 17.5.1)
    static int ok = -1;
    if (ok >= 0) return ok;
    if (!owner || !handle || !scene) return NO;   // (asked again with all three)
    Class xs = objc_getClass("XBApplicationSnapshot"), fs = objc_getClass("FBSceneSnapshot");
    Method rs = xs ? class_getInstanceMethod(xs, NSSelectorFromString(@"setReferenceSize:")) : NULL, cf = xs ? class_getInstanceMethod(xs, NSSelectorFromString(@"setContentFrame:")) : NULL;
    Method cap = fs ? class_getInstanceMethod(fs, NSSelectorFromString(@"capture")) : NULL;
    ok = DMSMSigOK(owner, NSSelectorFromString(@"_deviceApplicationSceneHandleForDisplayItem:"), DMSMExpect(@encode(id), @encode(id), NULL), "_deviceApplicationSceneHandleForDisplayItem:")
      && DMSMSigOK(handle, NSSelectorFromString(@"saveSuspendSnapshot:"), DMSMExpect(@encode(void), @encode(id), NULL), "saveSuspendSnapshot:")
      && DMSMSigOK(handle, NSSelectorFromString(@"mostRecentSceneSnapshotsForScale:launchingOrientation:"), DMSMExpect(@encode(id), @encode(double), @encode(long long), NULL), "mostRecentSceneSnapshotsForScale:launchingOrientation:")
      && DMSMSigOK(scene, NSSelectorFromString(@"snapshotContext"), DMSMExpect(@encode(id), NULL), "snapshotContext")
      && DMSMSigOK(scene, NSSelectorFromString(@"createSnapshotWithContext:"), DMSMExpect(@encode(id), @encode(id), NULL), "createSnapshotWithContext:")
      && cap && [DMSMSigOfMethod(cap) isEqualToString:DMSMExpect(@encode(BOOL), NULL)]
      && rs && [DMSMSigOfMethod(rs) isEqualToString:DMSMExpect(@encode(void), @encode(CGSize), NULL)]
      && cf && [DMSMSigOfMethod(cf) isEqualToString:DMSMExpect(@encode(void), @encode(CGRect), NULL)];
    if (!ok) DMLog(@"[wincard] SpringBoard's picture calls are not as read on 15.6.1 / 17.5.1: windows' cards keep the picture SpringBoard has");
    return ok;
}
// A rect of the screen (the interface's points) in the screen's fixed portrait space, as SpringBoard's pictures are kept (DMScreenToNative's turn).
static CGRect DMWinCardPortraitRect(CGRect r, long o, CGSize portrait) {
    CGPoint a = r.origin, b = CGPointMake(CGRectGetMaxX(r), CGRectGetMaxY(r));
    CGPoint pa = DMScreenToNative(a, o, portrait), pb = DMScreenToNative(b, o, portrait);
    return CGRectMake(MIN(pa.x, pb.x), MIN(pa.y, pb.y), fabs(pb.x - pa.x), fabs(pb.y - pa.y));
}
// SpringBoard keeps the picture a few moments after -saveSuspendSnapshot: returns (its manifest's queue) and lets a suspend picture go 5 s after it
// was taken (-[SBApplication saveSuspendSnapshot:forSceneHandle:] -setExpirationDate: now + 5 s: it is the picture of an app leaving the screen
// until the app's own one comes, M1 15.6.1). A window's app never sends one of its own, so ours is kept until the next one replaces it (each
// App Switcher coming takes a new one unless it is current; SpringBoard's next suspend picture of the app -- full screen, leaving the screen --
// removes it as it removes its own older ones). The same for SpringBoard's own suspend picture of a window's scene that becomes its card's on 18
// (DMWinCardAdopt): its 5 s are that same wait for the app's own picture, which a window's scene never gets in a card's shape (the app pictures its
// scene at the window's size; the card asks for the screen's) -- at SpringBoard's 5 s it was gone 5 s after it was taken and nothing was left for
// the card (18.5 trace, 4826e12). Asked again every 0.1 s for 1.5 s until it is there; then the card's cache is told.
static double DMWinCardPicLife(void) {
#if DEBUG
    double d = [[NSString stringWithContentsOfFile:@"/tmp/msb-wincard-life" encoding:NSUTF8StringEncoding error:nil] doubleValue];
    if (d > 0) return d;
#endif
    return 1800.0;
}
static id DMWinCardContentOf(id owner) {   // (that switcher's content view controller: the cards' picture cache is its)
    SEL cv = NSSelectorFromString(@"contentViewController");
    return [owner respondsToSelector:cv] && DMSMSigOK(owner, cv, DMSMSigObj(), "contentViewController") ? ((id (*)(id, SEL))objc_msgSend)(owner, cv) : nil;
}
// The picture's orientation. SpringBoard keeps a scene's picture under the scene's own interface orientation (-[SBApplication saveSuspendSnapshot:
// forSceneHandle:] makes the XBApplicationSnapshot of the scene snapshot, and saves it only while the scene's settings and its client agree on the
// orientation), and a card asks for the screen's (-[SBAppSwitcherSnapshotImageCache _loadSnapshotForRequest:withDisplayItem:inAppLayout:]:
// -_orientationForAppLayout:, then -bestSnapshotWithImageName:...launchingOrientation:). Not always the same: on 16.7.7 an Aerial 5.1 window's
// scene is a portrait scene (1) in Aerial's turned window while the screen is landscape (3) (iPad 2, 29 Oct). Looked up under the screen's
// orientation ours was not found ("did not keep its window's picture"), kept the scene's size as its reference size and the card stayed black;
// found under the scene's but left at 1, the card drew it a quarter turned (sideways). So ours is looked up under the scene's orientation (sceneO)
// and given the screen's (-setInterfaceOrientation:): upright and current. The image itself needs no change (it is as the window shows it, with
// the imageOrientation 0 SpringBoard's own pictures have). Where the two agree (15's windows) nothing changes. Debug /tmp/msb-wincard-noturn:
// the orientation left as SpringBoard kept it, to compare.
static void DMWinCardPlacePicture(id owner, id handle, id item, NSString *b, CGSize sceneSize, CGRect content, CGSize portrait, long o, long sceneO, CFTimeInterval t0, int tries, NSString *why) {
    NSUInteger placed = 0;
    @try {
        id list = ((id (*)(id, SEL, double, long long))objc_msgSend)(handle, NSSelectorFromString(@"mostRecentSceneSnapshotsForScale:launchingOrientation:"), [UIScreen mainScreen].scale, (long long)sceneO);
        NSDate *since = [NSDate dateWithTimeIntervalSinceNow:-(CACurrentMediaTime() - t0) - 1.0];
        for (id x in ([list isKindOfClass:[NSArray class]] ? list : @[])) {   // (ours: just saved, of the scene's own size)
            CGSize rsz = [[x valueForKey:@"referenceSize"] CGSizeValue]; NSString *name = [x valueForKey:@"name"]; NSDate *made = [x valueForKey:@"creationDate"];
            if (![name isEqual:@"SBSuspendSnapshot"] || fabs(rsz.width - sceneSize.width) > 0.5 || fabs(rsz.height - sceneSize.height) > 0.5 || ![made isKindOfClass:[NSDate class]] || [made compare:since] == NSOrderedAscending) continue;
            NSMutableArray *all = [NSMutableArray arrayWithObject:x];
            id variants = [x respondsToSelector:NSSelectorFromString(@"variants")] ? DMCall(x, @"variants") : nil;
            if ([variants isKindOfClass:[NSArray class]]) [all addObjectsFromArray:variants];
            for (id v in all) {
                ((void (*)(id, SEL, CGSize))objc_msgSend)(v, NSSelectorFromString(@"setReferenceSize:"), portrait);
                ((void (*)(id, SEL, CGRect))objc_msgSend)(v, NSSelectorFromString(@"setContentFrame:"), content);
                if ([v respondsToSelector:NSSelectorFromString(@"setExpirationDate:")]) ((void (*)(id, SEL, id))objc_msgSend)(v, NSSelectorFromString(@"setExpirationDate:"), [NSDate dateWithTimeIntervalSinceNow:DMWinCardPicLife()]);
                SEL so = NSSelectorFromString(@"setInterfaceOrientation:");
                if (sceneO != o && !DMTestFlag("/tmp/msb-wincard-noturn") && DMSMSigOK(v, so, DMSMExpect(@encode(void), @encode(long long), NULL), "setInterfaceOrientation:")) {
                    ((void (*)(id, SEL, long long))objc_msgSend)(v, so, (long long)o);
                    DM_FEATURE_MARK("window-app-switcher-card-picture-turned");
                }
            }
            placed++;
        }
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[wincard] %@: its picture could not be placed: %@", b, e.reason]); return; }
    if (!placed) {
        if (tries >= 15) { DMLog([NSString stringWithFormat:@"[wincard] %@: SpringBoard did not keep its window's picture (%@)", b, why]); return; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMWinCardPlacePicture(owner, handle, item, b, sceneSize, content, portrait, o, sceneO, t0, tries + 1, why); });
        return;
    }
    id cc = DMWinCardContentOf(owner);
    id cache = [cc respondsToSelector:NSSelectorFromString(@"snapshotCache")] ? DMCall(cc, @"snapshotCache") : nil;
    SEL rl = NSSelectorFromString(@"reloadSnapshotForDisplayItem:");
    if (cache && DMSMSigOK(cache, rl, DMSMExpect(@encode(void), @encode(id), NULL), "reloadSnapshotForDisplayItem:")) ((void (*)(id, SEL, id))objc_msgSend)(cache, rl, item);
    if (DMTestFlag("/tmp/macstatusbar-debug")) DMLog([NSString stringWithFormat:@"[wincard] %@: its picture is the card's now (%.0f ms after it was taken, %lu kept; scene orientation %ld, screen %ld)", b, (CACurrentMediaTime() - t0) * 1000.0, (unsigned long)placed, sceneO, o]);
}
// Where a picture of the window's scene (sf: the scene's size) goes in its card: the screen as the reference (portrait), the window's content fitted
// into it (content), the screen's orientation (o) and the scene's own (sceneO, the one SpringBoard keeps the picture under).
static void DMWinCardPlacement(UIView *stage, id scene, CGSize sf, DMWinPicMode mode, CGRect *content, CGSize *portrait, long *o, long *sceneO) {
    CGSize screen = [UIScreen mainScreen].bounds.size;
    *portrait = CGSizeMake(MIN(screen.width, screen.height), MAX(screen.width, screen.height));
    *o = ((long (*)(id, SEL))objc_msgSend)([UIApplication sharedApplication], NSSelectorFromString(@"activeInterfaceOrientation"));
    *sceneO = *o;   // (the orientation SpringBoard keeps the picture under: the scene's own, DMWinCardPlacePicture)
    @try { id st = DMCall(scene, @"settings"); SEL io = NSSelectorFromString(@"interfaceOrientation"); if (st && DMSMSigOK(st, io, DMSMExpect(@encode(long long), NULL), "interfaceOrientation")) *sceneO = (long)((long long (*)(id, SEL))objc_msgSend)(st, io); } @catch (NSException *e) { *sceneO = *o; }
    if (*sceneO < 1 || *sceneO > 4) *sceneO = *o;
    *content = CGRectMake(0, 0, sf.width, sf.height);
    if (mode == DMWinPicFit) {   // (the window's content as large as the card allows, its own shape kept, in the middle)
        double k = MIN(portrait->width / sf.width, portrait->height / sf.height);
        CGSize z = CGSizeMake(round(sf.width * k), round(sf.height * k));
        *content = CGRectMake(round((portrait->width - z.width) / 2.0), round((portrait->height - z.height) / 2.0), z.width, z.height);
    } else if (mode == DMWinPicFill) *content = CGRectMake(0, 0, portrait->width, portrait->height);
    else if (mode == DMWinPicPlace) *content = DMWinCardPortraitRect([stage convertRect:stage.bounds toCoordinateSpace:[UIScreen mainScreen].coordinateSpace], *o, *portrait);
}
static BOOL gWinCardSaving = NO;   // (our own -saveSuspendSnapshot: is running: SpringBoard's own pictures are adopted below, ours are placed here)
static BOOL DMWinCardPicture(UIView *stage, NSString *b, NSString *why) {
    DMWinPicMode mode = DMWinCardPicMode();
    if (mode == DMWinPicOff || !stage || !b.length) return NO;
    id sw = DMWinCardSwitcher();
    id item = sw ? DMWinCardItem(sw, b) : nil;
    id owner = nil; DMWinCardWindowScene(sw, stage, &owner);   // (the switcher of the window's screen: 15's view controller, 16+'s SBSwitcherController)
    SEL hs = NSSelectorFromString(@"_deviceApplicationSceneHandleForDisplayItem:");
    id handle = item && [owner respondsToSelector:hs] ? ((id (*)(id, SEL, id))objc_msgSend)(owner, hs, item) : nil;
    id scene = DMWinCardScene(stage, b);
    if (!item || !handle || !scene || !DMWinCardPicOK(owner, handle, scene)) return NO;
    CFTimeInterval t0 = CACurrentMediaTime();
    id ctx = DMCall(scene, @"snapshotContext");
    id shot = nil; BOOL captured = NO; CGRect sf = CGRectZero;
    @try {
        shot = ctx ? ((id (*)(id, SEL, id))objc_msgSend)(scene, NSSelectorFromString(@"createSnapshotWithContext:"), ctx) : nil;
        captured = shot && ((BOOL (*)(id, SEL))objc_msgSend)(shot, NSSelectorFromString(@"capture"));
        sf = [[ctx valueForKey:@"frame"] CGRectValue];
    } @catch (NSException *e) { captured = NO; }
    if (!captured || sf.size.width < 50.0 || sf.size.height < 50.0) { if (DMTestFlag("/tmp/macstatusbar-debug")) DMLog([NSString stringWithFormat:@"[wincard] %@: its window's picture could not be taken (%@)", b, why]); return NO; }
    gWinCardSaving = YES;
    @try { ((void (*)(id, SEL, id))objc_msgSend)(handle, NSSelectorFromString(@"saveSuspendSnapshot:"), shot); } @finally { gWinCardSaving = NO; }
    CGRect content; CGSize portrait; long o, sceneO;
    DMWinCardPlacement(stage, scene, sf.size, mode, &content, &portrait, &o, &sceneO);
    if (mode != DMWinPicRaw) DMWinCardPlacePicture(owner, handle, item, b, sf.size, content, portrait, o, sceneO, t0, 0, why);
    DM_FEATURE_MARK("window-app-switcher-card-picture");
    DMLog([NSString stringWithFormat:@"[wincard] %@: its window pictured for its card (%@): scene %@, to be shown in %@ of the card, %.1f ms", b, why, NSStringFromCGSize(sf.size), NSStringFromCGRect(content), (CACurrentMediaTime() - t0) * 1000.0]);
    return YES;
}
// SpringBoard's own picture of a window's scene. iPadOS 18 (A12Z 18.5, Aerial 5.1, 29 Oct): as iPadOS's App Switcher comes, SpringBoard takes the
// windows' scenes into the background for a moment (Clock's window: will resign active, did enter background, and in the foreground again 7 ms
// later), and pictures each one as it leaves the screen -- -[SBApplication saveSuspendSnapshot:forSceneHandle:] deletes the scene's older suspend
// pictures (ours, taken as the switcher came) and saves its own of the scene's size, under the scene's orientation (portrait in the landscape
// screen), for 5 s. The card, asking for the screen's orientation, found nothing and showed the app's launch picture (contentType
// GeneratedDefault, the bars without content) -- on 15-17 the windows' scenes stayed in the foreground, so ours was never replaced. So SpringBoard's
// own picture of a scene that has an engine's window becomes its card's picture as ours does (DMWinCardPlacePicture: the screen as the reference,
// the window fitted into it, the screen's orientation, the longer life): it is the window as it left the screen, as a full-screen app's card is.
// Our own saves go through the same method and are left to DMWinCardPicture (gWinCardSaving).
static void DMWinCardAdopt(NSString *b, id handle) {
    DMWinPicMode mode = DMWinCardPicMode();
    if (mode == DMWinPicOff || mode == DMWinPicRaw || !b.length || !handle || DMWinCardsOff() || DMSMEngine() || DMActiveEngine() == DMEngineNone || DMWinCardAppGoing(b)) return;
    UIView *stage = nil;
    for (UIView *st in DMAerialStagesAll()) if ([DMStageBundle(st) isEqualToString:b] && ![objc_getAssociatedObject(st, kStageClosingKey) boolValue]) { stage = st; break; }
    id sw = stage ? DMWinCardSwitcher() : nil;
    id item = sw ? DMWinCardItem(sw, b) : nil;   // (only an app whose window has its one-app card)
    id owner = nil; DMWinCardWindowScene(sw, stage, &owner);
    id scene = item ? DMWinCardScene(stage, b) : nil;
    id ctx = scene ? DMCall(scene, @"snapshotContext") : nil;
    CGRect sf = CGRectZero; @try { sf = ctx ? [[ctx valueForKey:@"frame"] CGRectValue] : CGRectZero; } @catch (NSException *e) { sf = CGRectZero; }
    if (!item || !owner || !scene || sf.size.width < 50.0 || sf.size.height < 50.0 || !DMWinCardPicOK(owner, handle, scene)) return;
    CGRect content; CGSize portrait; long o, sceneO;
    DMWinCardPlacement(stage, scene, sf.size, mode, &content, &portrait, &o, &sceneO);
    DMWinCardPlacePicture(owner, handle, item, b, sf.size, content, portrait, o, sceneO, CACurrentMediaTime(), 0, @"SpringBoard pictured its window");
    DMWinCardTaken(stage);
    DM_FEATURE_MARK("window-app-switcher-card-picture-adopted");
    if (DMTestFlag("/tmp/macstatusbar-debug")) DMLog([NSString stringWithFormat:@"[wincard] %@: SpringBoard pictured its window's scene itself: that picture is the card's (scene %@, shown in %@)", b, NSStringFromCGSize(sf.size), NSStringFromCGRect(content)]);
}
static void (*o_WinCardSBSave)(id, SEL, id, id);
static void DMWinCardSBSave(id self, SEL _cmd, id snapshot, id handle) {   // -[SBApplication saveSuspendSnapshot:forSceneHandle:]
    o_WinCardSBSave(self, _cmd, snapshot, handle);
    if ([NSThread isMainThread] && gWinCardSaving) return;   // (ours: DMWinCardPicture places it -- its save runs on the main thread, inside the flag)
    NSString *b = [self respondsToSelector:@selector(bundleIdentifier)] ? [self bundleIdentifier] : nil;
    if (![b isKindOfClass:[NSString class]]) return;
    id h = handle; NSString *bb = [b copy];
    // (whether the app has a window is asked on the main thread: it walks the engines' views, and nothing says SpringBoard saves on that thread.
    //  A full-screen app leaving the screen: SpringBoard's picture as it is. SpringBoard's manifest keeps the picture a moment later:
    //  DMWinCardPlacePicture waits for it)
    dispatch_async(dispatch_get_main_queue(), ^{ if (DMHasWindowFor(bb)) DMWinCardAdopt(bb, h); });
}
static void DMWinCardAdoptInstall(void) {   // (once, where the cards are on: DMWinCardSwitcher)
    static BOOL done = NO;
    if (done) return;
    done = YES;
    Class c = objc_getClass("SBApplication");
    SEL sel = sel_registerName("saveSuspendSnapshot:forSceneHandle:");
    Method m = c ? class_getInstanceMethod(c, sel) : NULL;
    if (!m || ![DMSMSigOfMethod(m) isEqualToString:DMSMExpect(@encode(void), @encode(id), @encode(id), NULL)]) {
        DMLog([NSString stringWithFormat:@"[wincard] SpringBoard's suspend picture call is %s here: its own pictures of the windows stay as it saves them", m ? method_getTypeEncoding(m) : "not there"]);
        return;
    }
    MSHookMessageEx(c, sel, (IMP)DMWinCardSBSave, (IMP *)&o_WinCardSBSave);
    DMLog(@"[wincard] SpringBoard's own pictures of the windows' scenes become their cards' pictures");
}
// (a new card's picture: an app that is still starting has nothing to picture yet -- Clock's cold start in a MilkyWay4 window, M1 par05 -- so it is
//  tried again each second, three times)
static void DMWinCardPictureNew(UIView *stage, NSString *b, int tries) {
    if (!stage) return;   // (the window went meanwhile; a Zetsu window is a UIWindow of its own, with no superview)
    if (DMWinCardPicture(stage, b, tries ? @"its card is new, the app has started" : @"its card is new")) { DMWinCardTaken(stage); return; }
    if (tries >= 3) return;
    __weak UIView *ws = stage; NSString *bb = [b copy];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ UIView *s2 = ws; if (s2 && ![objc_getAssociatedObject(s2, kWinCardPicturedKey) boolValue]) DMWinCardPictureNew(s2, bb, tries + 1); });
}
BOOL DMWinCardPictureFlag(UIView *stage, NSString *b) { DMWinCardPictureNew(stage, b, 0); return YES; }
// iPadOS's App Switcher is coming (a switcher transition to its environment, 2): every window that is showing gets a picture of now for its card,
// and each one never pictured. Not inside SpringBoard's transition event, where they were all taken at once (review of 1.7.0): each one is the
// scene rendered and saved, 2-8 ms a window with SpringBoard calm and far more under an animation (33 ms in the switcher's closing one, 158 ms
// under our Mac Switcher's), so a few windows held the switcher's start back. The event only works out which (MSBDWinCardPictureOrder: not a
// picture that is still current -- taken since the window was last in front, at this orientation and size, under 5 s ago) and in which order
// (the window in front first: its card is the switcher's first); they are then taken one per turn of the main run loop, while the App Switcher is
// coming or up. Gone meanwhile: the rest is left (the tick pictures the window that leaves the front; the next coming the others). Each picture
// still reaches its card ~110 ms after it is taken (SpringBoard's manifest), within the switcher's coming, as before. Once per coming (the event
// comes several times).
static NSPointerArray *gWinCardPicQueue;   // (this coming's windows still to picture, weakly: a window that closes meanwhile is left out)
static BOOL gWinCardPicStepping = NO;
static void DMWinCardsPictureStep(void) {
    UIView *st = nil;
    while (!st && gWinCardPicQueue.count) { st = (__bridge UIView *)[gWinCardPicQueue pointerAtIndex:0]; [gWinCardPicQueue removePointerAtIndex:0]; }
    if (!st || gEnvMode != 2 || DMWinCardsOff()) { gWinCardPicQueue = nil; gWinCardPicStepping = NO; return; }   // (done, or the App Switcher went)
    NSString *b = DMStageBundle(st);
    if (b.length && ![objc_getAssociatedObject(st, kStageClosingKey) boolValue] && !DMWinCardAppGoing(b) && DMWinCardPicture(st, b, @"the App Switcher comes")) DMWinCardTaken(st);
    dispatch_async(dispatch_get_main_queue(), ^{ DMWinCardsPictureStep(); });   // (the next window: the next turn of the run loop)
}
static void DMWinCardsSwitcherComing(long long mode) {
    static CFTimeInterval last = 0;
    if (mode != 2 || DMSMEngine() || DMActiveEngine() == DMEngineNone || DMWinCardsOff()) return;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - last < 1.0) return;
    last = now;
    if (!DMWinCardSwitcher()) return;
    NSArray<UIView *> *stages = DMAerialStagesAll();   // (back to front)
    NSUInteger n = stages.count;
    if (!n) return;
    NSString *front = [DMActiveApp() bundleIdentifier];
    if (!front.length || !DMHasWindowFor(front)) front = nil;   // (a full-screen app or Home in front: the windows front to back)
    MSBDWinCardPicWindow *w = calloc(n, sizeof *w); NSUInteger *order = calloc(n, sizeof *order);
    if (!w || !order) { free(w); free(order); return; }
    for (NSUInteger i = 0; i < n; i++) {
        UIView *st = stages[i]; NSString *b = DMStageBundle(st);
        NSArray *at = objc_getAssociatedObject(st, kWinCardPicAtKey);
        w[i].hasApp = b.length > 0;
        w[i].showing = !st.hidden && !DMStageMinimized(st) && ![objc_getAssociatedObject(st, kMSWAwayKey) boolValue];
        w[i].pictured = [objc_getAssociatedObject(st, kWinCardPicturedKey) boolValue];
        w[i].current = at.count == 2 && b.length && MSBDWinCardPictureCurrent([at[0] doubleValue], [gWinCardFrontAt[b] doubleValue], now, at[1], DMWinCardShape(st));
        w[i].front = front && [b isEqualToString:front];
    }
    NSUInteger k = MSBDWinCardPictureOrder(w, n, order);
    gWinCardPicQueue = [NSPointerArray weakObjectsPointerArray];
    for (NSUInteger j = 0; j < k; j++) [gWinCardPicQueue addPointer:(__bridge void *)stages[order[j]]];
    free(w); free(order);
    if (DMTestFlag("/tmp/macstatusbar-debug")) DMLog([NSString stringWithFormat:@"[wincard] the App Switcher comes: %lu of %lu window(s) to picture, one per turn (in front: %@)", (unsigned long)k, (unsigned long)n, front ?: @"no window"]);
    if (k && !gWinCardPicStepping) { gWinCardPicStepping = YES; dispatch_async(dispatch_get_main_queue(), ^{ DMWinCardsPictureStep(); }); }
}
// Each 0.2 s tick (DMSyncWindowsForLibraryBody): a window whose app has no card gets SpringBoard's (once; again after 5 s at most twice if the card
// went while the window stayed), and the front window's card goes first once the front has held for 0.5 s. The switcher's list is read only when
// the windows changed, every 2 s anyway, or when the front window changed (0.46 ms a tick when it was read every time, M1 par08).
static void DMWinCardsTick(void) {
    if (DMSMEngine() || DMActiveEngine() == DMEngineNone || DMWinCardsOff()) return;
    NSArray<UIView *> *stages = DMAerialStagesAll();   // (every desktop's windows: a Stage Manager desktop's windows are cards too)
    static NSString *lastFront = nil, *picPending = nil; static CFTimeInterval frontSince = 0, lastScan = 0; static BOOL frontDone = NO, scanDue = YES;
    static NSArray *lastStages = nil;
    if (!stages.count) { lastFront = nil; picPending = nil; lastStages = nil; return; }
    CFTimeInterval now = CACurrentMediaTime();
    if (![stages isEqualToArray:lastStages ?: @[]]) { lastStages = [stages copy]; scanDue = YES; }   // (a window came or went: views compare by identity)
    if (now - lastScan > 2.0) scanDue = YES;
    // the window in front (read every tick: it is what the status bar shows anyway)
    SBApplication *app = DMActiveApp();
    NSString *front = [app bundleIdentifier];
    if (!front.length || !DMHasWindowFor(front)) front = nil;   // (a full-screen app in front: SpringBoard's own transition put it first)
    if (front && !DMSwitcherVisible()) {   // (in use, so its card's picture is no longer current: MSBDWinCardPictureCurrent; not under the App Switcher)
        if (!gWinCardFrontAt) gWinCardFrontAt = [NSMutableDictionary dictionary];
        gWinCardFrontAt[front] = @(now);
    }
    if (![front ?: @"" isEqualToString:lastFront ?: @""]) { if (lastFront.length) picPending = lastFront; lastFront = [front copy]; frontSince = now; frontDone = NO; }
    BOOL frontDue = front && !frontDone && now - frontSince >= 0.5;
    if (!scanDue && !frontDue && !(picPending.length && now - frontSince >= 1.0)) return;
    id sw = DMWinCardSwitcher();
    if (!sw) return;
    // (asked only while no switcher shows and no transaction runs, and only for an app that runs: an app quit from its card leaves a MilkyWay4
    //  window for a moment, until DMMilkyWayCloseDeadWindows closes it -- asked for then, it got a card again with no app behind it, M1 par04)
    BOOL calm = !DMSwitcherVisible() && !DMWinCardBusy() && !gMSWOpen && !gMSWClosing;   // (and not under our Mac Switcher: a picture taken while it closed cost 158 ms, M1 par09)
    NSArray *layouts = nil;
    NSArray<NSArray<NSString *> *> *cards = DMWinCardList(sw, &layouts);
    if (scanDue && calm) {
        scanDue = NO; lastScan = now;
        NSSet<NSString *> *running = DMLiveRunningBundleIDs();
        for (UIView *st in stages) {
            NSString *b = DMStageBundle(st);
            if (!b.length) { scanDue = YES; continue; }   // (not ready: the next tick)
            NSInteger asked = [objc_getAssociatedObject(st, kWinCardAskedKey) integerValue];
            double at = [objc_getAssociatedObject(st, kWinCardAskedAtKey) doubleValue];
            BOOL mayAsk = asked == 0 || (asked < 3 && now - at > 5.0);
            BOOL closing = [objc_getAssociatedObject(st, kStageClosingKey) boolValue];
            if (MSBDWinCardHasCard(b, cards) || !mayAsk || closing) continue;
            if (![running containsObject:b]) { scanDue = YES; continue; }   // (still starting, or quit with its window still going: asked again)
            NSString *sid = DMWinCardSceneID(st, b);
            if (!MSBDWinCardShouldAsk(b, NO, closing, sid != nil, cards)) { scanDue = YES; continue; }   // (no scene yet: the next tick)
            DMWinCardAsk(sw, st, b, sid, asked ? @"its card went while the window stayed" : @"opened as a window");
            cards = DMWinCardList(sw, &layouts);   // (one card per app: a second window of the app is not asked again)
        }
    }
    // (the window that was in front: its card's picture is its look as it was left, as a full-screen app's is when it leaves the screen -- taken
    //  once SpringBoard is calm, not inside the App Switcher's closing animation: 33 ms there once, M1 par06; never for an app just quit)
    if (picPending.length && calm && now - frontSince >= 1.0) {   // (once the new front has held a second: no picture inside a window's own animation)
        NSString *was = picPending; picPending = nil;
        BOOL quit = [gPrewarmQuitSet containsObject:was] || DMAppJustExited(was);
        for (UIView *st in (quit ? @[] : stages)) if ([DMStageBundle(st) isEqualToString:was] && !st.hidden && !DMStageMinimized(st) && ![objc_getAssociatedObject(st, kStageClosingKey) boolValue] && MSBDWinCardHasCard(was, cards)) {
            if (DMWinCardPicture(st, was, @"its window left the front")) DMWinCardTaken(st);
            break;
        }
    }
    if (!frontDue) return;
    MSBDWinCardFront plan = MSBDWinCardFrontPlan(front, cards, !calm && DMSwitcherVisible(), !calm);
    if (plan == MSBDWinCardFrontWait) return;
    frontDone = YES;
    if (plan != MSBDWinCardFrontMove) return;
    id layout = nil;
    for (NSUInteger i = 0; i < cards.count && i < layouts.count; i++) if (cards[i].count == 1 && [cards[i].firstObject isEqualToString:front]) { layout = layouts[i]; break; }
    if (!layout) return;
    @try { ((void (*)(id, SEL, id))objc_msgSend)(sw, NSSelectorFromString(@"_addAppLayoutToFront:"), layout); }
    @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[wincard] %@: bringing its card first failed: %@", front, e.reason]); return; }
    DM_FEATURE_MARK("window-app-switcher-card-front");
    DMLog([NSString stringWithFormat:@"[wincard] %@'s window is in front: its App Switcher card goes first (as a full-screen app's does)", front]);
}

#if DEBUG
// wincards: the switcher's cards as SpringBoard has them (each layout's apps, scene ids, configuration, environment) and every window with its ask
// count -- read-only. wincard_<bundle>: ask SpringBoard for that window's card now. wincardinfo_<bundle>: the card's snapshots as SpringBoard
// would show them (the scene handle's most recent snapshots, the switcher's cache entries). wincardsnap_<bundle>: the window's scene pictured
// the way SpringBoard does it for a suspending app (-[FBScene createSnapshotWithContext:] + -capture, -[SBDeviceApplicationSceneHandle
// saveSuspendSnapshot:]) and the switcher's cache told (-reloadSnapshotForDisplayItem:).
static id DMWinCardItemFor(NSString *b, id *layoutOut) {
    id sw = DMSwitcherController();
    NSArray *layouts = nil; NSArray<NSArray<NSString *> *> *cards = DMWinCardList(sw, &layouts);
    for (NSUInteger i = 0; i < cards.count && i < layouts.count; i++) {
        if (![cards[i] containsObject:b]) continue;
        id items = DMCall(layouts[i], @"allItems");
        for (id it in ([items isKindOfClass:[NSArray class]] ? items : @[])) if ([DMSMItemBundle(it) isEqualToString:b]) { if (layoutOut) *layoutOut = layouts[i]; return it; }
    }
    return nil;
}
static BOOL DMWinCardTrigger(NSString *cmd) {
    if ([cmd isEqualToString:@"wincards"]) {
        id sw = DMSwitcherController();
        NSArray *layouts = nil; DMWinCardList(sw, &layouts);
        NSMutableString *s = [NSMutableString stringWithFormat:@"[wincards] %lu card(s) in %@ (busy %d, switcher up %d)", (unsigned long)layouts.count, NSStringFromClass([sw class]), DMWinCardBusy(), DMSwitcherVisible()];
        NSUInteger i = 0;
        for (id l in layouts) {
            long long conf = [l respondsToSelector:NSSelectorFromString(@"configuration")] ? ((long long (*)(id, SEL))objc_msgSend)(l, NSSelectorFromString(@"configuration")) : -1;
            long long env = [l respondsToSelector:NSSelectorFromString(@"environment")] ? ((long long (*)(id, SEL))objc_msgSend)(l, NSSelectorFromString(@"environment")) : -1;
            [s appendFormat:@"\n  %lu %@ %p configuration %lld environment %lld:", (unsigned long)i++, NSStringFromClass([l class]), l, conf, env];
            for (id it in (DMCall(l, @"allItems") ?: @[])) {
                long long ty = [it respondsToSelector:NSSelectorFromString(@"type")] ? ((long long (*)(id, SEL))objc_msgSend)(it, NSSelectorFromString(@"type")) : -1;
                [s appendFormat:@" [%@ uid %@ type %lld]", DMSMItemBundle(it), DMSMItemUid(it), ty];
            }
        }
        for (UIView *st in DMAerialStagesAll()) {
            NSString *b = DMStageBundle(st);
            [s appendFormat:@"\n  window %@ %@ asked %ld scene %@ min %d hidden %d", NSStringFromClass([st class]), b, (long)[objc_getAssociatedObject(st, kWinCardAskedKey) integerValue], DMWinCardSceneID(st, b), DMStageMinimized(st), st.hidden];
        }
        DMLog(s);
        return YES;
    }
    if ([cmd hasPrefix:@"wincard_"]) {
        NSString *b = [cmd substringFromIndex:8];
        id sw = DMWinCardSwitcher();
        UIView *st = nil; for (UIView *s2 in DMAerialStagesAll()) if ([DMStageBundle(s2) isEqualToString:b]) { st = s2; break; }
        NSString *sid = st ? DMWinCardSceneID(st, b) : nil;
        if (!sw || !st || !sid) { DMLog([NSString stringWithFormat:@"[wincard] wincard_%@: switcher %d window %d scene %@", b, sw != nil, st != nil, sid]); return YES; }
        DMWinCardAsk(sw, st, b, sid, @"debug trigger");
        return YES;
    }
    if ([cmd hasPrefix:@"wincardinfo_"] || [cmd hasPrefix:@"wincardsnap_"]) {
        BOOL snap = [cmd hasPrefix:@"wincardsnap_"];
        NSString *b = [cmd substringFromIndex:12];
        id layout = nil, item = DMWinCardItemFor(b, &layout);
        id sw = DMMainSwitcherController();   // (the scene handles: 15's view controller, 16+'s SBSwitcherController of the iPad's own screen)
        SEL hs = NSSelectorFromString(@"_deviceApplicationSceneHandleForDisplayItem:");
        id handle = item && [sw respondsToSelector:hs] ? ((id (*)(id, SEL, id))objc_msgSend)(sw, hs, item) : nil;
        id content = DMMainSwitcherContent();
        id cache = [content respondsToSelector:NSSelectorFromString(@"snapshotCache")] ? DMCall(content, @"snapshotCache") : nil;
        NSMutableString *s = [NSMutableString stringWithFormat:@"[wincard] %@ %@: item %@ handle %@ cache %@", snap ? @"snap" : @"info", b, item ? DMSMItemUid(item) : @"none", handle ? NSStringFromClass([handle class]) : @"none", cache ? NSStringFromClass([cache class]) : @"none"];
        SEL mr = NSSelectorFromString(@"mostRecentSceneSnapshotsForScale:launchingOrientation:");
        if ([handle respondsToSelector:mr]) {
            long o = ((long (*)(id, SEL))objc_msgSend)([UIApplication sharedApplication], NSSelectorFromString(@"activeInterfaceOrientation"));
            [s appendFormat:@"\n  screen orientation %ld", o];
            for (long oo = 1; oo <= 4; oo++) {   // (every orientation: a window's scene may have another one than the screen, 16.7.7's Aerial windows)
                id list = ((id (*)(id, SEL, double, long long))objc_msgSend)(handle, mr, [UIScreen mainScreen].scale, (long long)oo);
                [s appendFormat:@"\n  most recent snapshots (orientation %ld): %lu", oo, (unsigned long)([list respondsToSelector:@selector(count)] ? [list count] : 0)];
                for (id x in ([list isKindOfClass:[NSArray class]] ? list : @[])) {
                    NSMutableString *p = [NSMutableString string];
                    for (NSString *k in @[@"name", @"referenceSize", @"contentFrame", @"interfaceOrientation", @"imageOrientation", @"creationDate", @"expirationDate", @"contentType", @"fullScreen", @"imageScale", @"variantID"]) { id v = nil; @try { v = [x valueForKey:k]; } @catch (id e) { v = @"?"; } [p appendFormat:@" %@=%@", k, v]; }
                    [s appendFormat:@"\n    %@ %p%@", NSStringFromClass([x class]), x, p];
                }
            }
        }
        @try { id cached = [cache valueForKey:@"_cachedSnapshots"]; [s appendFormat:@"\n  cache: %@", [[[cached description] stringByReplacingOccurrencesOfString:@"\n" withString:@" "] substringToIndex:MIN((NSUInteger)1500, [[cached description] length])]]; } @catch (id e) {}
        if (snap) {
            id scene = DMSceneForBundle(b);
            id ctx = [scene respondsToSelector:NSSelectorFromString(@"snapshotContext")] ? DMCall(scene, @"snapshotContext") : nil;
            id shot = ctx && [scene respondsToSelector:NSSelectorFromString(@"createSnapshotWithContext:")] ? ((id (*)(id, SEL, id))objc_msgSend)(scene, NSSelectorFromString(@"createSnapshotWithContext:"), ctx) : nil;
            BOOL captured = shot && [shot respondsToSelector:NSSelectorFromString(@"capture")] ? ((BOOL (*)(id, SEL))objc_msgSend)(shot, NSSelectorFromString(@"capture")) : NO;
            CGRect cf = CGRectZero; @try { cf = [[ctx valueForKey:@"frame"] CGRectValue]; } @catch (id e) {}
            [s appendFormat:@"\n  picture: scene %@ context frame %@ snapshot %@ captured %d", scene ? @"yes" : @"no", NSStringFromCGRect(cf), shot ? NSStringFromClass([shot class]) : @"none", captured];
            if (captured && handle && [handle respondsToSelector:NSSelectorFromString(@"saveSuspendSnapshot:")]) {
                ((void (*)(id, SEL, id))objc_msgSend)(handle, NSSelectorFromString(@"saveSuspendSnapshot:"), shot);
                [s appendString:@" saved as the suspend snapshot"];
                if ([cache respondsToSelector:NSSelectorFromString(@"reloadSnapshotForDisplayItem:")]) { ((void (*)(id, SEL, id))objc_msgSend)(cache, NSSelectorFromString(@"reloadSnapshotForDisplayItem:"), item); [s appendString:@", cache told"]; }
            }
        }
        DMLog(s);
        return YES;
    }
    return NO;
}
#endif
