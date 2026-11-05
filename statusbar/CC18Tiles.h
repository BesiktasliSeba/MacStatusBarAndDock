// CC18Tiles.h -- our Mac tiles on iPadOS 18 (1.8.1 item 1, plans/cc18tiles-1.8.1.md): Connectivity, Display, Sound and Now Playing as Control Center's own
// modules in Apple's grid. Each module (ccmodule/MSBDMacTileModule.h, a bundle of its own) asks this part for its content view controller (MSBDCCMacTileHost,
// found with dlsym); the tile in it is CCTiles.h's, the 15-17 panel's own drawing and state. Apple's container gives the tile its place at the grid's size and
// draws the platter behind it. A tile's page (Wi-Fi's, Bluetooth's, Sound's) opens in the panel in place of the tiles, as on 15-17 (DMCC18PageOpen); the
// panel's calls of CCTiles.h come here through CCPanel.h's (DMCC18TilesAreOurs). Nothing runs while Control Center is closed: as on 15-17, a tile's state is
// read at the presentation (DMCC18TilesWillPresent), and its observers only mark it old. Included once by StatusBar.x, after CC18Shape.h.
#pragma once

static BOOL gCC18TilesMade = NO;   // (a module of ours asked for its host: the tiles' calls are ours, on 18 only)
static BOOL DMCC18TilesAreOurs(void) { return gCC18TilesMade; }

// Control Center about to show / closed: Apple's calls on each module's host, and (Mac) SBControlCenterController's (CC18Shape.h): whichever comes first.
static void DMCC18TilesWillPresent(void) {
    if (!gCC18TilesMade || gCCTShown) return;
    BOOL locked = DMCCPLockedNow(), changed = locked != gCCPLocked;
    gCCPLocked = locked;
    DMCCTPanelWillPresent();
    for (DMCCTTile *t in gCCTTiles.allObjects) { if (changed) [t tileLockedChanged:locked]; [t tileWillPresent]; }
}
static void DMCC18TilesDidDismiss(void) {
    if (!gCC18TilesMade || !gCCTShown) return;
    for (DMCCTTile *t in gCCTTiles.allObjects) if ([t respondsToSelector:@selector(tileDidDismiss)]) [t tileDidDismiss];
    DMCCTPanelDidDismiss();
}

// ---- a module's content view controller ---------------------------------------------------------------------------------------------------------
@protocol CCUIContentModuleContentViewController <NSObject>   // (Control Center's own, by name, as ccmodule/MSBDRAMCPUModule.m declares it)
- (CGFloat)preferredExpandedContentHeight;
@end
@interface DMCC18TileHost : UIViewController <CCUIContentModuleContentViewController>
@property (nonatomic) int role;
@property (nonatomic, strong) DMCCTTile *tile;
@property (nonatomic) long long gridSizeClass;   // (Control Center tells it: its frame follows)
@property (nonatomic) BOOL stateRead;
@end
@implementation DMCC18TileHost
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    self.view.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;   // (18's tiles sit on a dark material in both appearances; the tile's colours follow this)
    self.tile = DMCCTMakeTileForRole(self.role);
    UIView *v = [self.tile tileView];
    if (!v) return;
    v.backgroundColor = [UIColor clearColor];   // (Apple's container draws the platter)
    [self.view addSubview:v];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView *v = [self.tile tileView];
    if (!v || CGRectIsEmpty(self.view.bounds)) return;
    v.frame = self.view.bounds;
    // (its state once, the first time it is on a window: a tile added from the gallery, the gallery's own preview -- Apple tells the modules Control Center is gone while its sheet shows,
    //  so no presentation tells these)
    if (!self.stateRead && self.view.window) { self.stateRead = YES; if (self.tile.old) [self.tile tileWillPresent]; }
    if ([self.tile respondsToSelector:@selector(tileLayoutInBounds:scale:)]) [(id<DMCCTile>)self.tile tileLayoutInBounds:v.bounds scale:1.0];   // (Apple's tiles keep their size: no Menu Bar Size scale here)
}
- (void)setGridSizeClass:(long long)c { _gridSizeClass = c; [self.view setNeedsLayout]; }
// (Control Center's content module view controller, its calls on 18.5 as for RAM & CPU: no expansion of its own -- a page opens in the panel)
- (CGFloat)preferredExpandedContentHeight { return 0.0; }
- (BOOL)shouldBeginTransitionToExpandedContentModule { return NO; }
- (BOOL)shouldExpandModuleOnTouch:(id)touch { return NO; }
- (BOOL)providesOwnPlatter { return NO; }
- (void)controlCenterWillPresent { DMCC18TilesWillPresent(); }
- (void)controlCenterDidDismiss { DMCC18TilesDidDismiss(); }
@end
__attribute__((visibility("default"))) UIViewController *MSBDCCMacTileHost(int kind) {   // (kMSBDCCMacTileHostFn: the bundles' order, MSBD_MAC_TILE_ROLE)
    static const int roles[] = { MSBDCCRoleTileConnectivity, MSBDCCRoleTileDisplay, MSBDCCRoleTileSound, MSBDCCRoleTileNowPlaying };
    if (kind < 0 || kind > 3 || [NSProcessInfo processInfo].operatingSystemVersion.majorVersion != 18) return nil;
    gCC18TilesMade = YES;
    DMCC18TileHost *h = [DMCC18TileHost new];
    h.role = roles[kind];
#if DEBUG
    DMLog([NSString stringWithFormat:@"[cc18tiles] a host for tile %d", kind]);
#endif
    return h;
}

// ---- Apple's module expanded (a hold, the Display tile's chevron) -------------------------------------------------------------------------------
// Its tile on the page shown: Apple's own expansion (Control Center expands only what it displays). On another page (a full page of the user's, as Connectivity's and
// Now Playing's are by default): that page shown. NO when the layout has no tile of it.
static id DMCC18ListOfModule(NSString *mid) {
    id root = DMCCGet(DMCCGet(DMCCGet(gCC18Main, @"pagingViewController"), @"iconModel"), @"rootFolder");
    for (id list in DMCCGet(root, @"lists"))
        for (id icon in DMCCGet(list, @"icons"))
            if ([DMCCGet(DMCCGet(icon, @"activeDataSource"), @"moduleIdentifier") isEqual:mid]) return list;
    return nil;
}
static BOOL DMCC18AppleModuleOpen(NSString *mid) {
    UIViewController *m = gCC18Main;
    if (!mid || !m.isViewLoaded || !DMCCTypes(m, @"expandModuleWithIdentifier:", "v24@0:8@16")) return NO;
    id paging = DMCCGet(m, @"pagingViewController"), list = DMCC18ListOfModule(mid);
    UIView *folder = DMCC18ViewOf(paging, @"currentIconlistView");
    while (folder && !DMCCTypes(folder, @"pageIndexForIconListModel:", "q24@0:8@16")) folder = folder.superview;
    BOOL opened = NO;
    if (list && folder && DMCCTypes(folder, @"currentPageIndex", "q16@0:8") && DMCCTypes(folder, @"setCurrentPageIndex:animated:", "B28@0:8q16B24")) {
        long long page = ((long long (*)(id, SEL, id))objc_msgSend)(folder, NSSelectorFromString(@"pageIndexForIconListModel:"), list);   // (its own numbering: not the list's place)
        if (page != ((long long (*)(id, SEL))objc_msgSend)(folder, NSSelectorFromString(@"currentPageIndex")))
            opened = ((BOOL (*)(id, SEL, long long, BOOL))objc_msgSend)(folder, NSSelectorFromString(@"setCurrentPageIndex:animated:"), page, YES);
        else {
            ((void (*)(id, SEL, id))objc_msgSend)(m, NSSelectorFromString(@"expandModuleWithIdentifier:"), mid);
            opened = DMCCTypes(paging, @"expandedModuleCount", "q16@0:8") && ((long long (*)(id, SEL))objc_msgSend)(paging, NSSelectorFromString(@"expandedModuleCount")) > 0;
        }
    }
#if DEBUG
    DMLog([NSString stringWithFormat:@"[cc18tiles] Apple's %@ %@", mid, opened ? @"shown" : list ? @"not opened" : @"not in the layout"]);
#endif
    return opened;
}

// ---- Display's page ---------------------------------------------------------------------------------------------------------------------------------
// 15-17's chevron opens Apple's Display module expanded (Dark Mode, Night Shift, True Tone) from the tile; on 18 Control Center expands only what it displays and Apple's module
// is no tile of the Mac layout. So these three rows, as macOS's Display page has them, each set as that module's own buttons set them (-[CCUIDisplayBackgroundViewController
// _toggleStyleMode / _setNightShiftEnabled: / _toggleTrueTone], 18.5: the arbiter's toggle, -setEnabled:withOption: 3, -setEnabled:), each only where its shape is as read here.
typedef struct { BOOL active, enabled, sunSchedulePermitted; int mode; struct { struct { int hour, minute; } from, to; } schedule; unsigned long long disableFlags; BOOL available; } DMCC18BlueLight;
static id DMCC18BrightnessClient(const char *cls) {   // (CoreBrightness: loaded with SpringBoard, its clients made once each, as Apple's module keeps its own)
    static NSMutableDictionary *made;
    if (!made) made = [NSMutableDictionary dictionary];
    NSString *k = @(cls);
    if (!made[k]) { Class c = objc_getClass(cls); id o = c ? [c new] : nil; if (o) made[k] = o; }
    return made[k];
}
static NSArray *DMCC18DisplayRows(void) {
    NSMutableArray *rows = [NSMutableArray array];
    Class arbiterClass = objc_getClass("UIUserInterfaceStyleArbiter");
    id arbiter = [(id)arbiterClass respondsToSelector:@selector(sharedInstance)] ? ((id (*)(id, SEL))objc_msgSend)((id)arbiterClass, @selector(sharedInstance)) : nil;
    if (DMCCTypes(arbiter, @"currentStyle", "q16@0:8") && DMCCTypes(arbiter, @"toggleCurrentStyle", "v16@0:8")) {
        BOOL dark = ((long long (*)(id, SEL))objc_msgSend)(arbiter, NSSelectorFromString(@"currentStyle")) == UIUserInterfaceStyleDark;
        [rows addObject:[[DMCCTSwitchRow alloc] initWithTitle:@"Dark Mode" on:dark enabled:YES onChange:^(BOOL on) {
            if ((((long long (*)(id, SEL))objc_msgSend)(arbiter, NSSelectorFromString(@"currentStyle")) == UIUserInterfaceStyleDark) != on) ((void (*)(id, SEL))objc_msgSend)(arbiter, NSSelectorFromString(@"toggleCurrentStyle"));
            DMLog([NSString stringWithFormat:@"[cc18tiles] Dark Mode %d", on]);
        }]];
    }
    id night = DMCC18BrightnessClient("CBBlueLightClient");
    if (DMCCTypes(night, @"supported", "B16@0:8") && ((BOOL (*)(id, SEL))objc_msgSend)(night, NSSelectorFromString(@"supported"))
        && DMCCTypes(night, @"getBlueLightStatus:", "B24@0:8^{?=BBBi{?={?=ii}{?=ii}}QB}16") && DMCCTypes(night, @"setEnabled:withOption:", "B24@0:8B16i20")) {
        DMCC18BlueLight st; memset(&st, 0, sizeof(st));
        if (((BOOL (*)(id, SEL, DMCC18BlueLight *))objc_msgSend)(night, NSSelectorFromString(@"getBlueLightStatus:"), &st))
            [rows addObject:[[DMCCTSwitchRow alloc] initWithTitle:@"Night Shift" on:st.enabled enabled:YES onChange:^(BOOL on) {
                BOOL ok = ((BOOL (*)(id, SEL, BOOL, int))objc_msgSend)(night, NSSelectorFromString(@"setEnabled:withOption:"), on, 3);
                DMLog([NSString stringWithFormat:@"[cc18tiles] Night Shift %d: %d", on, ok]);
            }]];
    }
    id tone = DMCC18BrightnessClient("CBAdaptationClient");
    if (DMCCTypes(tone, @"supported", "B16@0:8") && ((BOOL (*)(id, SEL))objc_msgSend)(tone, NSSelectorFromString(@"supported"))
        && DMCCTypes(tone, @"getEnabled", "B16@0:8") && DMCCTypes(tone, @"setEnabled:", "B20@0:8B16")) {
        BOOL on = ((BOOL (*)(id, SEL))objc_msgSend)(tone, NSSelectorFromString(@"getEnabled"));
        BOOL usable = !DMCCTypes(tone, @"available", "B16@0:8") || ((BOOL (*)(id, SEL))objc_msgSend)(tone, NSSelectorFromString(@"available"));
        [rows addObject:[[DMCCTSwitchRow alloc] initWithTitle:@"True Tone" on:on enabled:usable onChange:^(BOOL now) {
            BOOL ok = ((BOOL (*)(id, SEL, BOOL))objc_msgSend)(tone, NSSelectorFromString(@"setEnabled:"), now);
            DMLog([NSString stringWithFormat:@"[cc18tiles] True Tone %d: %d", now, ok]);
        }]];
    }
    if (rows.count) [rows addObject:[NSNull null]];
    [rows addObject:[[DMRow alloc] initWithTitle:@"Display Settings…" enabled:!DMRowsHostLocked() handler:DMCloseThen(^{ DMOpenURL(@"prefs:root=DISPLAY", @"display settings"); })]];
    return rows;
}

// ---- a page in the panel (CCPanel.h's DMCCPanelOpenDetail's look; gCCPDetail: the open page, as there) -------------------------------------------------
// In place of the tiles: Apple's list of the page hidden (the scroll view stays: its recognizers are Apple's tap outside), our row and the dots away, the
// panel at the page's height, a back row over the page's rows; closed by the back row, Esc, or Control Center closing.
static void DMCC18PageChrome(BOOL open, BOOL animated) {
    UIViewController *m = gCC18Main;
    id paging = DMCCGet(m, @"pagingViewController");
    UIView *list = DMCC18ViewOf(paging, @"currentIconlistView"), *dots = DMCC18ViewOf(m, @"overlayPageControl"), *header = DMCC18ViewOf(m, @"overlayHeaderView");
    UIScrollView *sv = [DMCCGet(paging, @"scrollView") isKindOfClass:[UIScrollView class]] ? DMCCGet(paging, @"scrollView") : nil;
    void (^go)(void) = ^{ CGFloat a = open ? 0.0 : 1.0; list.alpha = a; dots.alpha = a; gCC18DotsPill.alpha = a; gCC18Row.alpha = a; if (!header.hidden) header.alpha = a; };
    sv.scrollEnabled = !open;
    if (animated) go(); else [UIView performWithoutAnimation:go];
}
static CGFloat DMCC18PageHeight(CGFloat pageH, CGFloat headerH) {
    UIView *v = gCC18Main.viewIfLoaded;
    return MSBDCCDetailHeightAt(pageH, headerH, kMSBDCCPad, v.bounds.size.height - gCC18PanelTop - kMSBDCCBottomMargin, 66.0, 1.0);
}
static void DMCC18PageOpen(id<DMCCTile> tile) {
    UIViewController *m = gCC18Main;
    if (!tile || gCCPDetail || !gCC18On || !gCC18Shown || gCC18Editing || gCC18Expanded || !gCC18Material.superview || !m.isViewLoaded || ![(id)tile respondsToSelector:@selector(tileDetailViewForWidth:)]) return;
    if (gCCPLocked && [(id)tile respondsToSelector:@selector(tileDetailNeedsUnlock)] && [tile tileDetailNeedsUnlock]) return;
    CGRect f = gCC18Material.frame;
    CGFloat w = f.size.width, headerH = MSBDMenuRowScaled(gDMBarSize, 36.0), scale = DMCCPScale();
    UIView *page = [tile tileDetailViewForWidth:w - 2 * kMSBDCCPad];
    if (!page) return;
    CGFloat h = DMCC18PageHeight(page.frame.size.height, headerH);
    UIView *d = [[UIView alloc] initWithFrame:CGRectMake(f.origin.x, f.origin.y, w, h)];
    d.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    UIButton *back = [UIButton buttonWithType:UIButtonTypeSystem];
    back.frame = CGRectMake(kMSBDCCPad - 4, kMSBDCCPad, w - 2 * kMSBDCCPad, headerH);
    back.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    [back setImage:[UIImage systemImageNamed:@"chevron.left" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15.0 * scale weight:UIImageSymbolWeightSemibold]] forState:UIControlStateNormal];
    NSString *title = [(id)tile respondsToSelector:@selector(tileDetailTitle)] ? [tile tileDetailTitle] : nil;
    [back setTitle:[@" " stringByAppendingString:title ?: @""] forState:UIControlStateNormal];
    back.titleLabel.font = [UIFont systemFontOfSize:15.0 * scale weight:UIFontWeightSemibold];
    back.tintColor = [UIColor whiteColor];   // (the panel's material is dark on 18 in both appearances)
    back.accessibilityLabel = title.length ? [NSString stringWithFormat:@"Back from %@", title] : @"Back";
    [back addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { DMCC18PageClose(YES); }] forControlEvents:UIControlEventTouchUpInside];
    [d addSubview:back];
    UIScrollView *s = [[UIScrollView alloc] initWithFrame:CGRectMake(kMSBDCCPad, kMSBDCCPad + headerH, w - 2 * kMSBDCCPad, h - headerH - 2 * kMSBDCCPad)];
    s.contentSize = page.frame.size; s.alwaysBounceVertical = NO; s.scrollEnabled = page.frame.size.height > s.bounds.size.height + 0.5;
    [s addSubview:page];
    [d addSubview:s];
    d.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    d.alpha = 0.0;
    [m.view addSubview:d];
    gCCPDetail = d; gCCPDetailTile = tile; gCCPDetailScroll = s; gCCPDetailPage = page;
    [UIView animateWithDuration:MSBReduceMotion() ? 0.2 : 0.28 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        DMCC18PageChrome(YES, YES);
        d.alpha = 1.0;
        DMCC18SetMaterialFrame(CGRectMake(f.origin.x, f.origin.y, w, h));
    } completion:nil];
    DMCCPAXMoveTo(back, YES);
    DM_FEATURE_MARK("cc-mac-tile-page-18");
    DMLog([NSString stringWithFormat:@"[cc18tiles] %@'s page open (%.0f pt)", [tile tileID], h]);
}
static void DMCC18PageClose(BOOL animated) {
    UIView *d = gCCPDetail; id<DMCCTile> tile = gCCPDetailTile;
    if (!d) return;
    gCCPDetail = nil; gCCPDetailTile = nil; gCCPDetailScroll = nil; gCCPDetailPage = nil;
    CGRect f = MSBDCC18PanelFrame(gCC18Grid, gCC18PanelTop, DMCC18RowsHeight(gCC18Main));
    void (^go)(void) = ^{   // (the row and the dots with the panel's height and place, which may have moved under the page: DMCC18PageFollowsPanel)
        DMCC18PageChrome(NO, YES); d.alpha = 0.0;
        if (!CGRectIsEmpty(f)) { DMCC18SetMaterialFrame(f); DMCC18PlaceButtons(); DMCC18PlaceDots(gCC18Main); }
    };
    if (animated) [UIView animateWithDuration:MSBReduceMotion() ? 0.2 : 0.28 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:go completion:^(BOOL done) { [d removeFromSuperview]; }];
    else { [UIView performWithoutAnimation:go]; [d removeFromSuperview]; }
    if ([(id)tile respondsToSelector:@selector(tileDetailDidClose)]) [tile tileDetailDidClose];
    DMLog([NSString stringWithFormat:@"[cc18tiles] %@'s page closed", [tile tileID]]);
}
// The grid moved with a page open (the screen turned: Apple laid its grid out again, DMCC18Views): the page and the material go with the panel, at the page's height for the room there; no
// panel to follow, or one of another width: the page closes. From landscape to portrait the old frame lay past the screen's edge: an empty Control Center, the tiles' list at alpha 0, the page off screen.
static void DMCC18PageFollowsPanel(void) {
    UIView *d = gCCPDetail, *page = gCCPDetailPage; UIScrollView *s = gCCPDetailScroll;
    if (!d || !page || !s) return;
    CGFloat headerH = MSBDMenuRowScaled(gDMBarSize, 36.0), h = DMCC18PageHeight(page.frame.size.height, headerH);
    CGRect f;
    if (!MSBDCC18PageFrame(MSBDCC18PanelFrame(gCC18Grid, gCC18PanelTop, 0.0), d.bounds.size.width, h, &f)) {
        DMLog([NSString stringWithFormat:@"[cc18tiles] %@'s page: the panel has no place for it now (grid %@): closed", [gCCPDetailTile tileID], NSStringFromCGRect(gCC18Grid)]);
        DMCC18PageClose(NO);
        return;
    }
    if (CGRectEqualToRect(d.frame, f) && CGRectEqualToRect(gCC18Material.frame, f)) return;
    DMCC18SetMaterialFrame(f);
    d.frame = f;
    s.frame = CGRectMake(kMSBDCCPad, kMSBDCCPad + headerH, f.size.width - 2 * kMSBDCCPad, f.size.height - headerH - 2 * kMSBDCCPad);
    s.scrollEnabled = page.frame.size.height > s.bounds.size.height + 0.5;
    DMLog([NSString stringWithFormat:@"[cc18tiles] %@'s page goes with the panel: %@", [gCCPDetailTile tileID], NSStringFromCGRect(f)]);
}
// (Esc: DMCC18PanelEscape)
static BOOL DMCC18PagePanelEscape(void) { if (!gCCPDetail) return NO; DMCC18PageClose(YES); return YES; }
static void DMCC18PageResized(void) {
    UIView *d = gCCPDetail, *page = gCCPDetailPage; UIScrollView *s = gCCPDetailScroll;
    if (!d || !page || !s) return;
    CGFloat headerH = MSBDMenuRowScaled(gDMBarSize, 36.0), w = d.bounds.size.width, h = DMCC18PageHeight(page.frame.size.height, headerH);
    CGRect f = gCC18Material.frame;
    [UIView animateWithDuration:MSBReduceMotion() ? 0.2 : 0.25 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        DMCC18SetMaterialFrame(CGRectMake(f.origin.x, f.origin.y, f.size.width, h));
        d.frame = CGRectMake(f.origin.x, f.origin.y, w, h);
        s.frame = CGRectMake(kMSBDCCPad, kMSBDCCPad + headerH, w - 2 * kMSBDCCPad, h - headerH - 2 * kMSBDCCPad);
    } completion:nil];
    s.contentSize = page.frame.size; s.scrollEnabled = page.frame.size.height > s.bounds.size.height + 0.5;
}
