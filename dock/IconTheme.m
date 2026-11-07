// IconTheme.m -- the Dock's own items (Finder, Launchpad, Downloads, the Trash) as app icons an icon theme can change, like any app's (1.7.5 item 7):
// the views' side of common/IconTheme.h (the classes, the probe, the identifiers' order). Declared for the views in DMIconTheme.h.
#import "DMLog.h"
#import "../common/IconTheme.h"
#import "DMIconTheme.h"

extern CGFloat gDMIconCornerRatio;   // (FinderIcon.m: SpringBoard's app icon corner as a share of the icon's width, read from the Dock at each layout)
NSString *const DMIconThemeChangedNotification = kMSBDIconThemeChanged;

void DMIconThemeSetDrawer(MSBDIconItem item, DMIconDrawer drawer) { MSBDIconThemeSetDrawer(item, (MSBDIconDrawer)drawer); }
BOOL DMIconThemeOn(void) {
    BOOL on = MSBDIconThemeReady();
    if (on) MSBDIconThemeWatch();
    return on;
}
UIImage *DMIconThemePicture(MSBDIconItem item, CGSize size, BOOL *themed) {
    if (!DMIconThemeOn()) { if (themed) *themed = NO; return nil; }
    CGFloat side = MIN(size.width, size.height);
    return MSBDIconThemePicture(item, size, [UIScreen mainScreen].scale, gDMIconCornerRatio * side, themed);
}
NSUInteger DMIconThemeGeneration(void) { return gMSBDIconGeneration; }
// Ask every item's picture again (a theme engine changed one icon's picture without telling: SnowBoard's per-icon menu, EditProxy.m).
void DMIconThemeAskAgain(NSString *why) {
    gMSBDIconGeneration++;
    DMLog([NSString stringWithFormat:@"[icontheme] %@: the Dock's items ask again (%lu)", why, (unsigned long)gMSBDIconGeneration]);
    [[NSNotificationCenter defaultCenter] postNotificationName:kMSBDIconThemeChanged object:nil];
}
id DMIconThemeIcon(MSBDIconItem item) {
    if (![NSThread isMainThread] || !DMIconThemeOn()) return nil;
    NSString *ident = MSBDIconID(item);
    return ident ? [MSBDIconFor(ident) firstObject] : nil;
}

#if DEBUG
// ---- debug ("ithm" in /tmp/dockmag-escape): what each item's app-icon chain gives now and what is on screen -- for each identifier its picture's
// size and its opaque pixels' average colour (a test theme's solid colours tell whose picture it is), themed or ours; then the Dock's views and
// Activity Monitor's icon views as drawn (their layers rendered), with the same numbers. Read-only.
static NSString *DMIconThemeAvg(UIImage *img, CALayer *layer, CGSize size) {
    const int n = 24; uint8_t px[n * n * 4]; memset(px, 0, sizeof px);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(px, n, n, 8, n * 4, cs, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);
    if (!c) return @"?";
    if (img.CGImage) CGContextDrawImage(c, CGRectMake(0, 0, n, n), img.CGImage);
    else if (layer && size.width > 1) { CGContextTranslateCTM(c, 0, n); CGContextScaleCTM(c, n / size.width, -n / size.height); [layer renderInContext:c]; }
    CGContextRelease(c);
    double r = 0, g = 0, b = 0; int opaque = 0, corner = px[3];
    for (int i = 0; i < n * n; i++) { double al = px[i * 4 + 3]; if (al < 128) continue; opaque++; r += px[i * 4] * 255.0 / al; g += px[i * 4 + 1] * 255.0 / al; b += px[i * 4 + 2] * 255.0 / al; }
    if (!opaque) return [NSString stringWithFormat:@"no opaque pixels (corner alpha %d)", corner];
    return [NSString stringWithFormat:@"avg rgb %.0f,%.0f,%.0f over %d%% (corner alpha %d)", r / opaque, g / opaque, b / opaque, opaque * 100 / (n * n), corner];
}
void DMIconThemeDebug(void) {
    BOOL on = DMIconThemeOn();
    DMLog([NSString stringWithFormat:@"[ithm] chain %@, generation %lu", on ? @"on" : @"off", (unsigned long)DMIconThemeGeneration()]);
    if (on) for (NSInteger i = 0; i < MSBDIconItemCount; i++) {
        if (i == MSBDIconActivityMonitor) continue;   // (its icon is MacStatusBar's: read on screen below)
        BOOL themed = NO;
        UIImage *p = DMIconThemePicture((MSBDIconItem)i, CGSizeMake(60, 60), &themed);
        DMLog([NSString stringWithFormat:@"[ithm] %@: %@ %@, %@", MSBDIconID((MSBDIconItem)i), p ? (themed ? @"THEMED" : @"ours") : @"none", p ? NSStringFromCGSize(p.size) : @"-", p ? DMIconThemeAvg(p, nil, CGSizeZero) : @"-"]);
    }
    NSMutableArray *todo = [NSMutableArray array];
    SEL all = NSSelectorFromString(@"allWindowsIncludingInternalWindows:onlyVisibleWindows:");
    NSArray *wins = [UIWindow respondsToSelector:all] ? ((NSArray *(*)(id, SEL, BOOL, BOOL))objc_msgSend)([UIWindow class], all, YES, NO) : @[];
    for (UIWindow *w in wins) [todo addObject:w];
    while (todo.count) {
        UIView *v = todo.lastObject; [todo removeLastObject]; [todo addObjectsFromArray:v.subviews];
        NSString *cn = NSStringFromClass([v class]);
        UIView *pic = nil; NSString *what = nil;
        if ([cn isEqualToString:@"DMFinderIconView"] || [cn isEqualToString:@"DMDownloadsIconView"] || [cn isEqualToString:@"DMTrashIconView"]) {
            @try { pic = [v valueForKey:@"image"]; } @catch (id e) {}
            what = cn;
        } else if ([v isKindOfClass:(Class)objc_getClass("SBIconView")]) {   // (the App Library icon's view is a subclass)
            id icon = nil; @try { icon = [v valueForKey:@"icon"]; } @catch (id e) {}
            NSString *ic = NSStringFromClass([icon class]);
            if ([ic isEqualToString:@"SBHLibraryPodIndicatorIcon"] || [ic isEqualToString:@"DMALActivityMonitorIcon"]) {
                @try { pic = [v valueForKey:@"_iconImageView"]; } @catch (id e) {}
                if (!pic) for (UIView *s in v.subviews) if ([NSStringFromClass([s class]) containsString:@"ImageView"]) pic = s;
                if ([ic isEqualToString:@"SBHLibraryPodIndicatorIcon"]) { for (UIView *s in pic.subviews) if ([s isKindOfClass:[UIImageView class]]) pic = s; }   // (our overlay)
                id loc = nil; @try { loc = [v valueForKey:@"location"]; } @catch (id e) {}
                what = [NSString stringWithFormat:@"%@ at %@ (%@ : %@)", ic, loc, NSStringFromClass(class_getSuperclass([icon class])), [icon respondsToSelector:@selector(applicationBundleID)] ? [icon valueForKey:@"applicationBundleID"] : @"-"];
            }
        }
        if (!what || !pic) continue;
        CGRect f = [pic convertRect:pic.bounds toCoordinateSpace:pic.window.screen.coordinateSpace];
        UIImage *shown = [pic isKindOfClass:[UIImageView class]] ? ((UIImageView *)pic).image : nil;
        DMLog([NSString stringWithFormat:@"[ithm] %@: %@ on screen at %@ (window %d, hidden %d): %@", what, NSStringFromClass([pic class]), NSStringFromCGRect(f), pic.window != nil, pic.hidden || v.hidden,
               DMIconThemeAvg(shown, shown ? nil : pic.layer, pic.bounds.size)]);
    }
}
#endif
