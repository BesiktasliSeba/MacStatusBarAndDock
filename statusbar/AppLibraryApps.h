// AppLibraryApps.h -- Activity Monitor in the App Library (1.7.2 item 1, KT 30 Oct: "an actual app, like Finder, inside the App Library": an icon in
// its Utilities category and in its search; a tap opens our Activity Monitor window). Included into StatusBar.x after ActivityMonitor.h.
// Finder is an app in the Dock only by our own drawing (dock/FinderIcon.m: a view of ours in the Dock's platter, not one of SpringBoard's icons). The
// App Library has no room for a view of ours: it shows SpringBoard's own icons (SBIcon). So Activity Monitor is one of those -- a leaf icon of a class
// made here at run time from SpringBoard's SBLeafIcon (DMALIconClass): its name, a picture drawn here as Finder's face is, and a launch that opens the
// window. It is never put in the icon model, so nothing of it is saved with the Home Screen's layout, and with the tweak off it is simply not there.
// How the App Library takes it (read on iPadOS 16.7.7 and 17.5.1, the same classes on 15.7.2 from its headers; 18 to check):
//  - categories: the App Library turns its category map (SBHLibraryCategoryMap: category -> app identifiers, iPadOS's own app categories) into its
//    category folders in -[SBHLibraryCategoriesFolderDataSource reloadDataSourceUsingIcons:categoryMap:], with the icon model's leaf icons. Our icon
//    joins that set and its identifier the Utilities category (prediction category 1010 or 6002, below) right after the three apps the category
//    shows large, so its tile shows it too (DMALReload);
//  - search: the search list (SBHIconLibraryTableViewController -iconLibrary:hasUpdatedQueryResult:, main thread) takes every result of iPadOS's
//    query engine (Spotlight). Ours is added to a result whose search text matches its name -- the query's own predicate decides, as for Apple's
//    apps --: in the A-Z list of the empty search under its letter (the result's own collation: main thread only, it asserts the main queue; never a
//    result made anew for the empty search: 18.5 hydrates that one off the main queue and asserts it), in a
//    search's list sorted by the query's own comparator, and to the "No Results" one (which comes without its query: the list's own current one)
//    (DMALResults); a new search text while ours is shown goes through the same rule at once (DMALExecute);
//  - its icon view: no Haptic Touch menu and no drag (nothing to delete, share or place on the Home Screen: it lives in the App Library only).
// Settings > Status Bar > Activity Monitor > Show in App Library (activityMonitorInLibrary, on unless switched off): DMALApplyPref.
#define kDMALActMonIdentifier @"com.besiktasliseba.macstatusbar.activitymonitor"
#define kDMALActMonName @"Activity Monitor"
// iPadOS's prediction category of "Utilities": the App Library's own group 1010 (16.7.7 and 17.5.1), or the App Store's genre 6002 where a
// category is the genre itself (17.5.1 lists Social as the genre 6005, 16.7.7 as the group 1001). Neither there: the category Clock is in.
static const unsigned long long kDMALUtilitiesGroup = 1010, kDMALUtilitiesGenre = 6002;
typedef struct { CGSize size; double scale; double continuousCornerRadius; } DMALIconImageInfo;   // (SpringBoard's SBIconImageInfo, by its encoding)
static BOOL gDMALOn = NO;
static Class gDMALIconClass;
static id gDMALIcon;
static __weak id gDMALDataSource;   // (the App Library's categories, last seen: reloaded when the switch changes)

// ---- the picture: an activity graph -- a dark tile, a faint grid, a green line with a soft glow over a light fill (drawn here, no image file) ----
static UIImage *DMALActMonImage(CGSize size, double scale, double radius) {
    if (!(size.width >= 4.0) || !(size.height >= 4.0) || !isfinite(size.width) || !isfinite(size.height)) return nil;
    static NSCache *cache; static dispatch_once_t once; dispatch_once(&once, ^{ cache = [NSCache new]; });
    NSString *key = [NSString stringWithFormat:@"%.1f %.1f %.1f %.2f", size.width, size.height, scale, radius];
    UIImage *hit = [cache objectForKey:key];
    if (hit) return hit;
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    fmt.scale = scale > 0.5 && scale < 5.0 ? scale : [UIScreen mainScreen].scale;
    fmt.opaque = NO;
    UIImage *img = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:fmt] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;
        CGFloat w = size.width, h = size.height, s = MIN(w, h);
        CGRect tile = CGRectMake((w - s) / 2.0, (h - s) / 2.0, s, s);
        CGPoint (^P)(CGFloat, CGFloat) = ^CGPoint(CGFloat x, CGFloat y) { return CGPointMake(CGRectGetMinX(tile) + s * x, CGRectGetMinY(tile) + s * y); };
        CGContextSaveGState(c);
        if (radius > 0.0) [[UIBezierPath bezierPathWithRoundedRect:tile cornerRadius:MIN(radius, s / 2.0)] addClip];
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGFloat back[] = { 0.20, 0.21, 0.23, 1,   0.04, 0.04, 0.05, 1 };
        CGGradientRef g = CGGradientCreateWithColorComponents(cs, back, NULL, 2);
        CGContextDrawLinearGradient(c, g, P(0, 0), P(0, 1), 0);
        CGGradientRelease(g);
        // the grid: three rows and five columns of hairlines
        CGContextSetLineWidth(c, MAX(0.5, s * 0.008));
        [[UIColor colorWithWhite:1.0 alpha:0.10] setStroke];
        for (int i = 1; i <= 3; i++) { CGContextMoveToPoint(c, P(0.08, 0).x, P(0, 0.2 + 0.2 * i).y); CGContextAddLineToPoint(c, P(0.92, 0).x, P(0, 0.2 + 0.2 * i).y); }
        for (int i = 1; i <= 4; i++) { CGContextMoveToPoint(c, P(0.08 + 0.168 * i, 0).x, P(0, 0.22).y); CGContextAddLineToPoint(c, P(0.08 + 0.168 * i, 0).x, P(0, 0.82).y); }
        CGContextStrokePath(c);
        // the line: a CPU graph, left to right
        static const CGFloat pts[][2] = { {0.08, 0.64}, {0.19, 0.64}, {0.26, 0.44}, {0.32, 0.70}, {0.40, 0.30}, {0.48, 0.60}, {0.55, 0.52}, {0.62, 0.67},
                                          {0.70, 0.38}, {0.78, 0.57}, {0.92, 0.57} };
        UIBezierPath *line = [UIBezierPath bezierPath];
        for (size_t i = 0; i < sizeof(pts) / sizeof(pts[0]); i++) { if (i == 0) [line moveToPoint:P(pts[i][0], pts[i][1])]; else [line addLineToPoint:P(pts[i][0], pts[i][1])]; }
        UIBezierPath *fill = [line copy];
        [fill addLineToPoint:P(0.92, 0.82)]; [fill addLineToPoint:P(0.08, 0.82)]; [fill closePath];
        CGContextSaveGState(c);
        [fill addClip];
        CGFloat green[] = { 0.20, 0.84, 0.36, 0.34,   0.20, 0.84, 0.36, 0.0 };
        g = CGGradientCreateWithColorComponents(cs, green, NULL, 2);
        CGContextDrawLinearGradient(c, g, P(0, 0.30), P(0, 0.82), 0);
        CGGradientRelease(g);
        CGContextRestoreGState(c);
        UIColor *lineColor = [UIColor colorWithRed:0.25 green:0.90 blue:0.40 alpha:1];
        line.lineWidth = MAX(1.0, s * 0.045); line.lineJoinStyle = kCGLineJoinRound; line.lineCapStyle = kCGLineCapRound;
        CGContextSetShadowWithColor(c, CGSizeZero, s * 0.05, [lineColor colorWithAlphaComponent:0.8].CGColor);
        [lineColor setStroke];
        [line stroke];
        CGColorSpaceRelease(cs);
        CGContextRestoreGState(c);
    }];
    if (img) [cache setObject:img forKey:key];
    return img;
}

// ---- the icon: SpringBoard's SBLeafIcon with our name, picture and launch (a class made at run time, each method only where SBLeafIcon has it in
// the shape it is written for) ----
static void DMALOpen(id location);
static id DMALName(id self, SEL _cmd, id location) { return kDMALActMonName; }
static id DMALName0(id self, SEL _cmd) { return kDMALActMonName; }
static id DMALImage(id self, SEL _cmd, DMALIconImageInfo info) { return DMALActMonImage(info.size, info.scale, info.continuousCornerRadius); }
static id DMALUnmasked(id self, SEL _cmd, DMALIconImageInfo info) { return DMALActMonImage(info.size, info.scale, 0.0); }
static BOOL DMALYes(id self, SEL _cmd) { return YES; }
static BOOL DMALNo(id self, SEL _cmd) { return NO; }
static id DMALNil(id self, SEL _cmd) { return nil; }
static long long DMALZero(id self, SEL _cmd) { return 0; }
static id DMALEmpty(id self, SEL _cmd) { return @[]; }
static id DMALIdent(id self, SEL _cmd) { return kDMALActMonIdentifier; }
static id DMALFilterStrings(id self, SEL _cmd) { return @[kDMALActMonName]; }
static void DMALLaunch(id self, SEL _cmd, id location, id context) { DMALOpen(location); }
static BOOL DMALPerformLaunch(id self, SEL _cmd, id location, id context) { DMALOpen(location); return YES; }
static BOOL DMALAddMethod(Class c, Class from, NSString *sel, NSString *types, IMP imp) {
    Method m = class_getInstanceMethod(from, NSSelectorFromString(sel));
    if (!m || ![DMMSWBareTypes(method_getTypeEncoding(m)) isEqualToString:types]) return NO;
    return class_addMethod(c, NSSelectorFromString(sel), imp, method_getTypeEncoding(m));
}
static Class DMALIconClass(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class leaf = objc_getClass("SBLeafIcon");
        if (!DMMSWHasMethod(leaf, @"initWithLeafIdentifier:applicationBundleID:", @"@@:@@") || !DMMSWHasMethod(leaf, @"displayNameForLocation:", @"@@:@")) {
            DMLog(@"[applib] SBLeafIcon is not as read here: Activity Monitor stays out of the App Library"); return;
        }
        Class c = objc_allocateClassPair(leaf, "DMALActivityMonitorIcon", 0);
        if (!c) return;
        NSString *img = @"@@:{SBIconImageInfo={CGSize=dd}dd}";
        int launches = 0, images = 0;
        DMALAddMethod(c, leaf, @"displayNameForLocation:", @"@@:@", (IMP)DMALName);
        DMALAddMethod(c, leaf, @"displayName", @"@@:", (IMP)DMALName0);
        DMALAddMethod(c, leaf, @"iconLibraryQueryingAlphaSortString", @"@@:", (IMP)DMALName0);
        DMALAddMethod(c, leaf, @"iconLibraryQueryingFilterStrings", @"@@:", (IMP)DMALFilterStrings);
        DMALAddMethod(c, leaf, @"_sbhIconLibraryCollationString", @"@@:", (IMP)DMALName0);
        images += DMALAddMethod(c, leaf, @"iconImageWithInfo:", img, (IMP)DMALImage);
        images += DMALAddMethod(c, leaf, @"generateIconImageWithInfo:", img, (IMP)DMALImage);
        DMALAddMethod(c, leaf, @"genericIconImageWithInfo:", img, (IMP)DMALImage);
        DMALAddMethod(c, leaf, @"unmaskedIconImageWithInfo:", img, (IMP)DMALUnmasked);
        DMALAddMethod(c, leaf, @"iconImageCacheIdentifier", @"@@:", (IMP)DMALIdent);
        launches += DMALAddMethod(c, leaf, @"launchFromLocation:context:", @"v@:@@", (IMP)DMALLaunch);   // (16; 17 still has it, 18: to check)
        launches += DMALAddMethod(c, leaf, @"performLaunchFromLocation:context:", @"B@:@@", (IMP)DMALPerformLaunch);   // (17)
        DMALAddMethod(c, leaf, @"isLaunchEnabled", @"B@:", (IMP)DMALYes);
        for (NSString *n in @[@"isUninstallSupported", @"canBeAddedToMultiItemDrag", @"canBeAddedToSubfolder", @"canReceiveGrabbedIcon", @"canBeReceivedByIcon", @"isTimedOut", @"isProgressPaused"])
            DMALAddMethod(c, leaf, n, @"B@:", (IMP)DMALNo);
        DMALAddMethod(c, leaf, @"badgeNumberOrString", @"@@:", (IMP)DMALNil);
        DMALAddMethod(c, leaf, @"labelAccessoryType", @"q@:", (IMP)DMALZero);
        DMALAddMethod(c, leaf, @"progressState", @"q@:", (IMP)DMALZero);
        DMALAddMethod(c, leaf, @"iTunesCategoriesOrderedByRelevancy", @"@@:", (IMP)DMALEmpty);
        if (!images || !launches) { DMLog([NSString stringWithFormat:@"[applib] SBLeafIcon has no picture (%d) or launch (%d) method as read here: Activity Monitor stays out of the App Library", images, launches]); return; }
        objc_registerClassPair(c);
        gDMALIconClass = c;
    });
    return gDMALIconClass;
}
static id DMALIcon(void) {
    if (gDMALIcon || !DMALIconClass()) return gDMALIcon;
    gDMALIcon = ((id (*)(id, SEL, id, id))objc_msgSend)([gDMALIconClass alloc], NSSelectorFromString(@"initWithLeafIdentifier:applicationBundleID:"), kDMALActMonIdentifier, nil);
    if (gDMALIcon) DM_FEATURE_MARK("actmon-app-library");
    return gDMALIcon;
}
static BOOL DMALIsOurs(id icon) { return gDMALIconClass && icon && [icon isKindOfClass:gDMALIconClass]; }

// A tap on it (the category's tile, its expanded list, a search result): the App Library goes, as when an app opens from it, then the window comes.
static void DMALOpen(id location) {
    if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(), ^{ DMALOpen(location); }); return; }
    DM_FEATURE_MARK("actmon-app-library-open");
    NSString *how = DMLibraryShowCall(NO);
    DMLog([NSString stringWithFormat:@"[applib] Activity Monitor opened from the App Library (%@): the App Library goes (%@), the window comes", location, how ?: @"no call"]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMActivityMonitorOpen(); });
}

// ---- the categories (DMALReload): our identifier in Utilities, our icon among the icons the folders are made from ----
static NSArray *DMALItems(id o) {
    if ([o isKindOfClass:[NSArray class]]) return o;
    if ([o isKindOfClass:[NSOrderedSet class]]) return [o array];
    if ([o respondsToSelector:@selector(allObjects)]) return [o allObjects];
    return @[];
}
static id DMALMapWithOurs(id map) {
    SEL sorted = NSSelectorFromString(@"sortedApplicationIdentifiersForCategoryIdentifier:"), set = NSSelectorFromString(@"setSortedApplicationIdentifiers:forCategoryIdentifier:");
    SEL pidSel = NSSelectorFromString(@"predictionCategoryID");
    if (![map respondsToSelector:sorted]) return nil;
    id utilities = nil, withClock = nil;
    for (id ci in DMALItems(DMCall(map, @"categoryIdentifiers"))) {
        unsigned long long pid = [ci respondsToSelector:pidSel] ? ((unsigned long long (*)(id, SEL))objc_msgSend)(ci, pidSel) : 0;
        if (pid == kDMALUtilitiesGroup || pid == kDMALUtilitiesGenre) { utilities = ci; break; }
        if (withClock || pid < 1000) continue;   // (an app category: not Suggestions (3), Recently Added (4) or the like)
        NSArray *its = ((id (*)(id, SEL, id))objc_msgSend)(map, sorted, ci);
        if ([its isKindOfClass:[NSArray class]] && [its containsObject:@"com.apple.mobiletimer"]) withClock = ci;
    }
    if (!utilities) utilities = withClock;
    if (!utilities) { static BOOL told; if (!told) { told = YES; DMLog(@"[applib] the App Library has no Utilities category in its map: Activity Monitor stays out of the categories"); } return nil; }
    NSArray *apps = ((id (*)(id, SEL, id))objc_msgSend)(map, sorted, utilities);
    if ([apps isKindOfClass:[NSArray class]] && [apps containsObject:kDMALActMonIdentifier]) return map;
    id m = [map respondsToSelector:@selector(mutableCopyWithZone:)] ? [map mutableCopy] : nil;
    if (![m respondsToSelector:set]) return nil;
    NSMutableArray *list = [apps isKindOfClass:[NSArray class]] ? [apps mutableCopy] : [NSMutableArray array];
    [list insertObject:kDMALActMonIdentifier atIndex:MIN((NSUInteger)3, list.count)];   // (after the three the category's tile shows large)
    ((void (*)(id, SEL, id, id))objc_msgSend)(m, set, [list copy], utilities);
    return m;
}
static id (*o_DMALReload)(id, SEL, id, id);
static id DMALReload(id self, SEL _cmd, id icons, id map) {
    gDMALDataSource = self;
    id icon = gDMALOn ? DMALIcon() : nil;
    id withOurs = icon ? DMALMapWithOurs(map) : nil;
    if (withOurs && ([icons isKindOfClass:[NSSet class]] || [icons isKindOfClass:[NSArray class]])) {
        id more = [icons isKindOfClass:[NSSet class]] ? (id)[(NSSet *)icons setByAddingObject:icon] : (id)([(NSArray *)icons containsObject:icon] ? icons : [(NSArray *)icons arrayByAddingObject:icon]);
        if ([icons isKindOfClass:[NSMutableSet class]] || [icons isKindOfClass:[NSMutableArray class]]) more = [more mutableCopy];   // (the same kind it came as)
        static BOOL told; if (!told) { told = YES; DMLog([NSString stringWithFormat:@"[applib] Activity Monitor joins the App Library's Utilities (%lu icons, a %@)", (unsigned long)[icons count], NSStringFromClass([icons class])]); }
        return o_DMALReload(self, _cmd, more, withOurs);
    }
    return o_DMALReload(self, _cmd, icons, map);
}

// ---- the search (DMALResults): ours in a result whose search text matches its name, in its place among the rest ----
static BOOL DMALQueryMatches(id query, id icon) {
    NSString *s = DMCall(query, @"searchString");
    if (![s isKindOfClass:[NSString class]]) s = @"";
    s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!s.length) return YES;   // (the empty search: the list of every app, A to Z)
    NSPredicate *p = DMCall(query, @"predicate");
    if ([p isKindOfClass:[NSPredicate class]]) {   // (the query's own test, as iPadOS applies it to its icons)
        @try { return [p evaluateWithObject:icon]; } @catch (id e) {}
    }
    // (no predicate to ask: each typed word starts a word of the name, any case and accents)
    NSArray *words = [kDMALActMonName componentsSeparatedByString:@" "];
    for (NSString *t in [s componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]) {
        if (!t.length) continue;
        BOOL hit = NO;
        for (NSString *w in words) if ([w rangeOfString:t options:NSAnchoredSearch | NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location == 0) { hit = YES; break; }
        if (!hit) return NO;
    }
    return YES;
}
// The A-Z list (a result with a collation, the empty search): the result's own snapshot with our item in its letter's section, in alphabetical
// place there, rebuilt with the same collation and sort -- as iPadOS lists its apps. nil when any part is not as read here.
static id DMALResultCollated(id result, id query, id icon) {
    Class rc = object_getClass(result);
    NSString *full = @"initWithQuery:icons:snapshot:collationStrategy:iconForitemIdentifier:sortMethodology:";
    id collation = DMCall(result, @"collationStrategy");
    NSDiffableDataSourceSnapshot *snap = DMCall(result, @"snapshot");
    Ivar mi = class_getInstanceVariable(rc, "_iconForItemIdentifier");   // (no getter: the result's own map, item -> icon)
    const char *mt = mi ? ivar_getTypeEncoding(mi) : NULL;
    NSDictionary *map = (mt && mt[0] == '@') ? object_getIvar(result, mi) : nil;
    SEL secSel = NSSelectorFromString(@"sectionForObject:collationStringSelector:"), titleSel = NSSelectorFromString(@"titleForSectionIdentifier:");
    if (!collation || ![snap isKindOfClass:[NSDiffableDataSourceSnapshot class]] || ![map isKindOfClass:[NSDictionary class]] || !DMMSWHasMethod(rc, full, @"@@:@@@@@Q")
        || ![collation respondsToSelector:secSel] || ![result respondsToSelector:titleSel]) return nil;
    SEL key = NSSelectorFromString(@"_sbhIconLibraryCollationString");
    if (![icon respondsToSelector:key] || ![NSThread isMainThread]) return nil;   // (the collation asserts the main queue: 16.7.7 crashed when asked on the engine's)
    NSInteger sec = ((NSInteger (*)(id, SEL, id, SEL))objc_msgSend)(collation, secSel, icon, key);
    NSArray *titles = DMCall(collation, @"sectionTitles");
    if (sec < 0 || ![titles isKindOfClass:[NSArray class]] || sec >= (NSInteger)titles.count) return nil;
    id section = nil;
    for (id sid in snap.sectionIdentifiers) if ([((id (*)(id, SEL, id))objc_msgSend)(result, titleSel, sid) isEqual:titles[sec]]) { section = sid; break; }
    if (!section) return nil;   // (no app under that letter yet: the plain way below)
    NSDiffableDataSourceSnapshot *s2 = [snap copy];
    id before = nil;
    for (id item in [s2 itemIdentifiersInSectionWithIdentifier:section]) {
        id other = map[item];
        NSString *name = [other respondsToSelector:key] ? ((id (*)(id, SEL))objc_msgSend)(other, key) : DMCall(other, @"displayName");
        if ([name isKindOfClass:[NSString class]] && [kDMALActMonName localizedStandardCompare:name] == NSOrderedAscending) { before = item; break; }
    }
    if (before) [s2 insertItemsWithIdentifiers:@[kDMALActMonIdentifier] beforeItemWithIdentifier:before];
    else [s2 appendItemsWithIdentifiers:@[kDMALActMonIdentifier] intoSectionWithIdentifier:section];
    NSMutableDictionary *m2 = [map mutableCopy]; m2[kDMALActMonIdentifier] = icon;
    unsigned long long how = [result respondsToSelector:NSSelectorFromString(@"sortMethodology")] ? ((unsigned long long (*)(id, SEL))objc_msgSend)(result, NSSelectorFromString(@"sortMethodology")) : 0;
    NSSet *icons = DMCall(result, @"icons") ?: [NSSet set];
    return ((id (*)(id, SEL, id, id, id, id, id, unsigned long long))objc_msgSend)([rc alloc], NSSelectorFromString(full), query, [icons setByAddingObject:icon], s2, collation, [m2 copy], how);
}
static id DMALResultWithOurs(id result, id current) {
    id icon = DMALIcon(), query = DMCall(result, @"query");
    SEL nq = NSSelectorFromString(@"isNullQueryResult");
    BOOL empty = [result respondsToSelector:nq] && ((BOOL (*)(id, SEL))objc_msgSend)(result, nq);
    if (!query || empty) query = current;   // (nothing found: no query with it -- the list's own current one)
    else if (current && ![DMCall(query, @"searchString") ?: @"" isEqual:DMCall(current, @"searchString") ?: @""]) return nil;   // (a late result of another text)
    NSSet *icons = DMCall(result, @"icons");
    if (![icons isKindOfClass:[NSSet class]]) icons = [NSSet set];
    if (!icon || !query || [icons containsObject:icon] || !DMALQueryMatches(query, icon)) return nil;
    id r = empty ? nil : DMALResultCollated(result, query, icon);
    // The empty search (the A-Z list) only ever gets ours in the engine's own result, in its letter's section (above): a result made anew for it
    // hydrates the A-Z collation, which 18.5 runs off the main queue and asserts so (+[SBHIconLibraryQueryResult _hydrateSnapshot:...]:
    // BSDispatchQueueAssertNotMain) -- SpringBoard crashed when the search field was cleared after a text that found nothing (A12Z, 31 Oct),
    // as the list's "nothing found" result then came back for the empty text. The engine's own A-Z result follows the clearing anyway.
    NSString *text = [DMCall(query, @"searchString") isKindOfClass:[NSString class]] ? DMCall(query, @"searchString") : @"";
    if (!r && ![text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length) return nil;
    if (!r) {   // (a search's own list: every icon sorted by the query's own comparator, ours among them)
        Class rc = objc_getClass("SBHIconLibraryQueryResult");
        if (!DMMSWHasMethod(rc, @"initWithQuery:icons:sortComparator:", @"@@:@@@?")) return nil;
        r = ((id (*)(id, SEL, id, id, id))objc_msgSend)([rc alloc], NSSelectorFromString(@"initWithQuery:icons:sortComparator:"), query, [icons setByAddingObject:icon], DMCall(query, @"comparator"));
    }
#if DEBUG
    if (DMTestFlag("/tmp/macstatusbar-debug")) {
        NSDiffableDataSourceSnapshot *sn = DMCall(r, @"snapshot");
        DMLog([NSString stringWithFormat:@"[applib] search '%@': Activity Monitor added (%@): %lu sections, %lu items, collation %@", DMCall(query, @"searchString"),
            empty ? @"to a result with nothing found" : (DMCall(result, @"collationStrategy") ? @"in its letter's section" : @"sorted by the query"),
            (unsigned long)sn.numberOfSections, (unsigned long)sn.numberOfItems, DMCall(r, @"collationStrategy") ? @"yes" : @"no"]);
    }
#endif
    return r;
}
// The search list (SBHIconLibraryTableViewController) takes each result on the main thread; it keeps the query it asked for (_currentQuery).
static id DMALIvarObj(id o, const char *name) {
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    const char *t = iv ? ivar_getTypeEncoding(iv) : NULL;
    return (t && t[0] == '@') ? object_getIvar(o, iv) : nil;
}
static BOOL gDMALShown = NO;   // (the list's last result had ours: DMALExecute)
static void (*o_DMALResults)(id, SEL, id, id);
static void DMALResults(id self, SEL _cmd, id library, id result) {
    id withOurs = nil;
    if (gDMALOn && [NSThread isMainThread]) @try { withOurs = DMALResultWithOurs(result, DMALIvarObj(self, "_currentQuery")); } @catch (id e) { withOurs = nil; }
    if ([NSThread isMainThread]) { id shownIcons = DMCall(withOurs ?: result, @"icons"); gDMALShown = gDMALIcon && [shownIcons isKindOfClass:[NSSet class]] && [shownIcons containsObject:gDMALIcon]; }
    o_DMALResults(self, _cmd, library, withOurs ?: result);
}
// A new search text: the engine tells the list only when ITS result changes -- nothing found, then nothing found again, is no change to it. So
// with nothing found the list kept what it showed: ours for a text that no longer matched ("act" -> "actx", 16.7.7), or no ours for one that
// matches again. Once the list has asked (the next turn of the main queue, never from inside its own call), the engine's "nothing found" result goes
// to the list again for the new text, through the same rule (DMALResults): ours is added when the text matches, else the list says "No Results".
// Only that result: one carrying another text's apps would be another query's list.
static BOOL (*o_DMALExecute)(id, SEL, id);
static BOOL DMALExecute(id self, SEL _cmd, id query) {
    BOOL r = o_DMALExecute(self, _cmd, query);
    if (!gDMALOn || ![NSThread isMainThread]) return r;
    __weak id ws = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        id me = ws, library = DMALIvarObj(me, "_library"), last = DMCall(library, @"lastQueryResults");
        SEL nq = NSSelectorFromString(@"isNullQueryResult");
        if (!me || !last || ![last respondsToSelector:nq] || !((BOOL (*)(id, SEL))objc_msgSend)(last, nq) || [DMCall(last, @"icons") count]) return;
        id current = DMALIvarObj(me, "_currentQuery"), icon = DMALIcon();
        if (!current || !icon || DMALQueryMatches(current, icon) == gDMALShown) return;   // (the list shows ours exactly when the text matches already)
        NSString *text = [DMCall(current, @"searchString") isKindOfClass:[NSString class]] ? DMCall(current, @"searchString") : @"";
        if (![text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length) return;   // (the empty text: the engine's A-Z list comes, with ours -- never "nothing found")
        DMALResults(me, NSSelectorFromString(@"iconLibrary:hasUpdatedQueryResult:"), library, last);
    });
    return r;
}

// ---- its icon view: no Haptic Touch menu, no drag ----
static id (*o_DMALMenuConfig)(id, SEL, id, CGPoint);
static id DMALMenuConfig(id self, SEL _cmd, id interaction, CGPoint p) {
    if (DMALIsOurs(DMCall(self, @"icon"))) return nil;
    return o_DMALMenuConfig(self, _cmd, interaction, p);
}
static BOOL (*o_DMALCanDrag)(id, SEL);
static BOOL DMALCanDrag(id self, SEL _cmd) {
    if (DMALIsOurs(DMCall(self, @"icon"))) return NO;
    return o_DMALCanDrag(self, _cmd);
}

static BOOL DMALHook(NSString *cls, NSString *sel, NSString *types, IMP repl, IMP *orig) {
    Class c = objc_getClass(cls.UTF8String);
    if (!DMMSWHasMethod(c, sel, types)) { DMLog([NSString stringWithFormat:@"[applib] -[%@ %@] is not as read here: not hooked", cls, sel]); return NO; }
    MSHookMessageEx(c, NSSelectorFromString(sel), repl, orig);
    return YES;
}
// Settings > Status Bar > Activity Monitor > Show in App Library (DMLoadPrefs). The hooks go in the first time it is on; a change reloads the App
// Library's categories (its search list asks again by itself).
static void DMALApplyPref(BOOL want) {
    static BOOL hooked = NO;
    if (want && !hooked && DMALIconClass()) {
        hooked = YES;
        BOOL a = DMALHook(@"SBHLibraryCategoriesFolderDataSource", @"reloadDataSourceUsingIcons:categoryMap:", @"@@:@@", (IMP)DMALReload, (IMP *)&o_DMALReload);
        BOOL b = DMALHook(@"SBHIconLibraryTableViewController", @"iconLibrary:hasUpdatedQueryResult:", @"v@:@@", (IMP)DMALResults, (IMP *)&o_DMALResults)
              && DMALHook(@"SBHIconLibraryTableViewController", @"_executeQuery:", @"B@:@", (IMP)DMALExecute, (IMP *)&o_DMALExecute);
        DMALHook(@"SBIconView", @"contextMenuInteraction:configurationForMenuAtLocation:", @"@@:@{CGPoint=dd}", (IMP)DMALMenuConfig, (IMP *)&o_DMALMenuConfig);
        DMALHook(@"SBIconView", @"canBeginDrags", @"B@:", (IMP)DMALCanDrag, (IMP *)&o_DMALCanDrag);
        DMLog([NSString stringWithFormat:@"[applib] Activity Monitor in the App Library: categories %@, search %@", a ? @"hooked" : @"NOT hooked", b ? @"hooked" : @"NOT hooked"]);
    }
    BOOL on = want && hooked;
    if (on == gDMALOn) return;
    gDMALOn = on;
    id ds = gDMALDataSource;
    if (ds && [ds respondsToSelector:NSSelectorFromString(@"reloadData")]) dispatch_async(dispatch_get_main_queue(), ^{ ((id (*)(id, SEL))objc_msgSend)(ds, NSSelectorFromString(@"reloadData")); });
    DMLog([NSString stringWithFormat:@"[applib] Activity Monitor in the App Library %@", on ? @"on" : @"off"]);
}
