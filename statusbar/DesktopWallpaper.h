// DesktopWallpaper.h -- Settings > Desktop > Desktop Picture in SpringBoard (1.8.6, KT 9-10 Nov), included into StatusBar.x after Desktop.h.
// The rules (which paths, which part of the picture, which of iPadOS's wallpapers are stills) are common/DesktopWallpaper.h's, tested on the Mac.
//
// Where iPadOS draws the Home Screen's wallpaper (iPad 17.5.1, 10 Nov, read in SpringBoard): SBWallpaperController's window (_wallpaperWindow,
// _SBWallpaperSecureWindow, level -3, right under SBHomeScreenWindow at -2) holds PosterBoard's wallpaper view controller, and in it one view per
// variant: PBUIPosterLockViewController's (the Lock Screen's) and PBUIPosterHomeViewController's (the Home Screen's), each the full screen, each with
// its own snapshot, live poster and blur/dim views. iPadOS fades, scales and blurs these as the Lock Screen, the Home Screen, an app's launch, the
// App Switcher and Stage Manager's floor want (the floor's wallpaper scale, SMDesktop.h).
// iPadOS 15/16 (read from their headers, not yet on a device): the same controller, its window _SBWallpaperWindow, the variants as SBFWallpaperView
// views (_homescreenWallpaperView, _lockscreenWallpaperView), or ONE shared view (_sharedWallpaperView) when both variants show the same picture.
//
// Pictures: a Mac Wallpapers file (On My iPad > MacStatusBar&Dock > Wallpapers), iPadOS's own still wallpaper (read from /Library/Wallpaper),
// or the copy of a picture from Photos -- whichever path Settings stored (common/DesktopWallpaper.h says which places are allowed).
// Ours: one picture view (DMWPPlane) put in as the LAST subview of the Home Screen variant's own view, so it is above Apple's Home Screen wallpaper
// and below everything else, and every effect iPadOS gives that wallpaper is given to ours with it (the Lock Screen's fade, an app's zoom, blurs).
// The wallpaper's window does not turn with the iPad (17.5.1: it stays in the screen's portrait bounds; PosterBoard turns its poster inside it).
// Ours is laid out each tick as the interface is (DMWPFollowTurn: the screen's interface space mapped into the host), so it is upright and of the
// interface's shape -- seen on the 17.5 (w01: in landscape the picture stayed portrait, on its side).
// Only page 1 shows it: its alpha follows the icon scroll view's position against page 1's place (1 on page 1, 0 one page away; a page turn
// crossfades into iPadOS's own wallpaper, which the next pages keep). With the shared view (15/16), it also shows only while the Home Screen is the
// active variant (SBWallpaperController -activeVariant 1).
// Nothing of Apple's is changed: no wallpaper file, setting or view property is written; ours is added and removed, nothing else.
// Memory: one decoded picture per screen, at the screen's own pixels, only of the part shown (MSBDWallpaperPart); decoded again off the main
// thread when the screen turns (a portrait and a landscape part differ) or the appearance changes and the picture has a dark version. None set: no
// view, no picture, nothing watched.
// Per screen: the iPad's own screen (gWPPlane, page 1 only) and an external display (gWPTVPlane, KT 10 Nov: the picture on every display, as a
// Mac does). 18.5 draws a TV's wallpaper in its own view controller, SBExternalDisplayWallpaperViewController (SpringBoard, its wallpaperContainerView),
// in a window on the TV's screen: ours goes in as its container's last subview, so it is above iPadOS's picture there and below the TV's windows.
// The TV has no Home Screen pages: shown whenever a picture is chosen. Decoded once at the TV's own pixels (its mode, not the larger render size of
// a 4K TV at @2x); gone with the TV, picture and all. Where no such controller exists (15/16 without Stage Manager's TV desktop), nothing is drawn.
#include "../common/DesktopWallpaper.h"
#import <ImageIO/ImageIO.h>

@interface DMWPPlane : UIImageView
@property (nonatomic, copy) NSString *shownPath;   // (the file decoded now)
@property (nonatomic) CGSize shownFor;             // (the screen size in points it was decoded for)
@property (nonatomic) BOOL decoding;
@property (nonatomic, copy) NSString *failedPath;  // (a picture that could not be read, for failedFor's shape: not tried again until the choice,
@property (nonatomic) CGSize failedFor;            //  the file or the screen's shape changes -- review 1.8.6 M2)
@property (nonatomic) BOOL sharedVariant;          // (15/16's shared view: also gated by the active variant)
@end
static void DMWPPlaneLaidOut(DMWPPlane *p);
@implementation DMWPPlane
- (void)layoutSubviews { [super layoutSubviews]; DMWPPlaneLaidOut(self); }
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e { return nil; }   // (a picture: touches go where they went before)
@end

static NSString *gWPLight, *gWPDark;   // (the paths in force: nil = None)
static NSString *gWPSig;               // (the files in force as they are: path, size and date of each -- a file replaced under the same name is
                                       //  shown anew when the choice is made again, review 1.8.6 L8)
static BOOL gWPRead = NO;
static DMWPPlane *gWPPlane;            // (the iPad's own screen)
static DMWPPlane *gWPTVPlane;          // (an external display's desktop: KT 10 Nov)
static __weak UIView *gWPTVHost;        // (the TV wallpaper view controller's container it is in)
static NSString *gWPTVNote;             // (where it went on the TV, or why not: logged once per change)
static __weak UIView *gWPHost;          // (the Home Screen variant's view it is in)
static __weak id gWPVariantOwner;       // (15/16's shared view: the object whose ivar held it, asked for the active variant too -- review 1.8.6 M1)
static __weak UIScrollView *gWPScroll;  // (the Home Screen's icon scroll view, watched)
static __weak UIView *gWPPageOne;       // (page 1's icon list in it)
static NSString *gWPHostNote;           // (where it went, or why not: the log says it once per change)

static NSString *DMWPReadPath(const char *key) {
    CFPropertyListRef v = CFPreferencesCopyValue((__bridge CFStringRef)@(key), MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSString *s = v && CFGetTypeID(v) == CFStringGetTypeID() ? [(__bridge NSString *)v copy] : nil;
    if (v) CFRelease(v);
    return MSBDWallpaperPathAllowed(s) ? s : nil;   // (anything else -- the crash guard's "none", a path outside our three places -- is None)
}
static void DMWPRemoveTV(NSString *why) {
    if (!gWPTVPlane) return;
    [gWPTVPlane removeFromSuperview];
    gWPTVPlane.image = nil;
    gWPTVPlane = nil;
    gWPTVNote = nil;
    DMLog([NSString stringWithFormat:@"[wallpaper] desktop picture on the external display removed (%@)", why]);
}
static void DMWPRemove(NSString *why) {
    DMWPRemoveTV(why);
    if (!gWPPlane) return;
    [gWPPlane removeFromSuperview];
    gWPPlane.image = nil;
    gWPPlane = nil;
    gWPHostNote = nil;
    DMLog([NSString stringWithFormat:@"[wallpaper] desktop picture removed (%@)", why]);
}
static NSString *DMWPFileSig(NSString *p) {
    if (!p) return @"-";
    NSDictionary *a = [[NSFileManager defaultManager] attributesOfItemAtPath:p error:nil];
    return [NSString stringWithFormat:@"%@|%llu|%.0f", p, [a fileSize], [[a fileModificationDate] timeIntervalSince1970]];
}
static void DMWPApplyPref(void) {
    CFPreferencesAppSynchronize(MSB_DOMAIN);
    NSString *light = DMWPReadPath(kMSBDWallpaperPathKey), *dark = light ? DMWPReadPath(kMSBDWallpaperDarkKey) : nil;
    NSString *sig = light ? [NSString stringWithFormat:@"%@ %@", DMWPFileSig(light), DMWPFileSig(dark)] : nil;
    BOOL changed = !gWPRead || !((sig == gWPSig) || [sig isEqualToString:gWPSig]);
    gWPRead = YES;
    if (!changed) return;
    gWPLight = light; gWPDark = dark; gWPSig = sig;
    DMLog([NSString stringWithFormat:@"[wallpaper] Desktop Picture: %@%@", light ? light.lastPathComponent : @"None", dark ? [NSString stringWithFormat:@" (dark: %@)", dark.lastPathComponent] : @""]);
    if (!light) { DMWPRemove(@"None"); return; }
    DM_FEATURE_MARK("desktop-picture");
    gWPPlane.shownPath = nil; gWPPlane.failedPath = nil;   // (a new picture, or the same file changed: decoded at the next tick)
    gWPTVPlane.shownPath = nil; gWPTVPlane.failedPath = nil;
}

// ---- where: the Home Screen variant's view ----
static UIWindow *DMWPWallpaperWindow(id *controllerOut) {
    Class wc = objc_getClass("SBWallpaperController");
    id c = [wc respondsToSelector:@selector(sharedInstance)] ? ((id (*)(id, SEL))objc_msgSend)((id)wc, @selector(sharedInstance)) : nil;
    if (controllerOut) *controllerOut = c;
    Ivar iv = c ? class_getInstanceVariable([c class], "_wallpaperWindow") : NULL;
    id w = iv ? object_getIvar(c, iv) : nil;
    return [w isKindOfClass:[UIWindow class]] ? w : nil;
}
// The view of a view controller of this class name in the window (17+: PBUIPosterHomeViewController), breadth first, a few levels down.
static UIView *DMWPViewOfController(UIView *root, NSString *name) {
    NSMutableArray *todo = [NSMutableArray arrayWithObject:root];
    for (int depth = 0; depth < 8 && todo.count; depth++) {
        NSMutableArray *next = [NSMutableArray array];
        for (UIView *v in todo) {
            UIResponder *r = v.nextResponder;
            if ([r isKindOfClass:[UIViewController class]] && [NSStringFromClass([r class]) isEqualToString:name] && ((UIViewController *)r).view == v) return v;
            if (v != gWPPlane) [next addObjectsFromArray:v.subviews];
        }
        todo = next;
    }
    return nil;
}
static UIView *DMWPFindHost(BOOL *shared, NSString **note) {
    *shared = NO;
    id c = nil;
    UIWindow *w = DMWPWallpaperWindow(&c);
    if (!w) { *note = @"no wallpaper window (SBWallpaperController _wallpaperWindow)"; return nil; }
    if (w.screen && w.screen != [UIScreen mainScreen]) { *note = @"the wallpaper window is not on the iPad's own screen: not drawn"; return nil; }   // (page 1 is the iPad's: review 1.8.6 L11)
    UIView *home = DMWPViewOfController(w, @"PBUIPosterHomeViewController");   // (17+: PosterBoard's Home Screen variant)
    if (home) { *note = [NSString stringWithFormat:@"in the Home Screen variant's view (%@ > PBUIPosterHomeViewController)", NSStringFromClass([w class])]; return home; }
    for (id owner in @[c ?: [NSNull null], w.rootViewController ?: [NSNull null]]) {   // (15/16: the controller's or its view controller's variant views)
        if (owner == [NSNull null]) continue;
        for (NSString *name in @[@"_homescreenWallpaperView", @"_sharedWallpaperView"]) {
            Ivar iv = class_getInstanceVariable([owner class], name.UTF8String);
            const char *ty = iv ? ivar_getTypeEncoding(iv) : NULL;
            id v = iv && ty && ty[0] == '@' ? object_getIvar(owner, iv) : nil;
            if (![v isKindOfClass:[UIView class]] || !((UIView *)v).window) continue;
            *shared = [name isEqualToString:@"_sharedWallpaperView"];
            gWPVariantOwner = owner;
            *note = [NSString stringWithFormat:@"in %@ (%@ of %@)%@", NSStringFromClass([v class]), name, NSStringFromClass([owner class]), *shared ? @", shown only while the Home Screen is the active variant" : @""];
            return v;
        }
    }
    *note = [NSString stringWithFormat:@"no Home Screen variant view found in %@ (nothing drawn)", NSStringFromClass([w class])];
    return nil;
}

// ---- the interface's shape and turn ----
// The interface's shape and turn in the host: UIKit's own mapping of the screen's interface space (UIScreen.coordinateSpace: the screen as the
// interface is turned now) into the host view -- the identity where the host's window turns with the interface, a quarter or half turn where it
// does not (17.5.1). Ours gets the interface's size, centred on the screen's centre, turned by that mapping.
static void DMWPFollowTurn(DMWPPlane *p, UIView *host) {
    UIScreen *sc = host.window.screen ?: [UIScreen mainScreen];
    id<UICoordinateSpace> ui = sc.coordinateSpace;
    CGSize size = ui.bounds.size;
    CGPoint o = [host convertPoint:CGPointZero fromCoordinateSpace:ui];
    CGPoint ex = [host convertPoint:CGPointMake(1, 0) fromCoordinateSpace:ui], ey = [host convertPoint:CGPointMake(0, 1) fromCoordinateSpace:ui];
    CGAffineTransform t = CGAffineTransformMake(round(ex.x - o.x), round(ex.y - o.y), round(ey.x - o.x), round(ey.y - o.y), 0, 0);   // (quarter turns: whole numbers)
    if (fabs(t.a * t.d - t.b * t.c) != 1.0) t = CGAffineTransformIdentity;   // (not a turn: the host as it is)
    CGPoint c = [host convertPoint:CGPointMake(size.width / 2.0, size.height / 2.0) fromCoordinateSpace:ui];
    NSString *src = @"UIKit's mapping";
    BOOL hostTall = host.bounds.size.height > host.bounds.size.width, uiTall = size.height > size.width;
    if (CGAffineTransformIsIdentity(t) && hostTall != uiTall) {
        // (UIKit maps the screen as if the host's window turned, but its shape says it did not: PosterBoard's turned poster view says the turn --
        //  its layer's transform --, else the interface's orientation does)
        src = nil;
        Class tc = objc_getClass("_BSUIOrientationTransformedContentView");
        NSMutableArray *todo = [NSMutableArray arrayWithObject:host];
        for (int depth = 0; depth < 5 && todo.count && !src; depth++) {
            NSMutableArray *next = [NSMutableArray array];
            for (UIView *v in todo) {
                if (tc && [v isKindOfClass:tc]) {
                    CGAffineTransform lt = CATransform3DGetAffineTransform(v.layer.transform);
                    lt = CGAffineTransformMake(round(lt.a), round(lt.b), round(lt.c), round(lt.d), 0, 0);
                    if (fabs(lt.a * lt.d - lt.b * lt.c) == 1.0 && !CGAffineTransformIsIdentity(lt)) { t = lt; src = @"PosterBoard's turned poster"; }
                    break;
                }
                if (v != p) [next addObjectsFromArray:v.subviews];
            }
            todo = next;
        }
        if (!src) {
            SEL aio = NSSelectorFromString(@"activeInterfaceOrientation");   // (SpringBoard's, as StatusBar.x reads it)
            long io = [[UIApplication sharedApplication] respondsToSelector:aio] ? ((long (*)(id, SEL))objc_msgSend)([UIApplication sharedApplication], aio) : UIInterfaceOrientationPortrait;
            double ang = io == UIInterfaceOrientationLandscapeLeft ? M_PI_2 : io == UIInterfaceOrientationLandscapeRight ? -M_PI_2 : io == UIInterfaceOrientationPortraitUpsideDown ? M_PI : 0;
#if DEBUG
            if (DMTestFlag("/tmp/msb-wp-flip")) ang = -ang;
#endif
            t = CGAffineTransformMakeRotation(ang);
            t = CGAffineTransformMake(round(t.a), round(t.b), round(t.c), round(t.d), 0, 0);
            src = [NSString stringWithFormat:@"the interface's orientation %ld", io];
        }
        c = CGPointMake(CGRectGetMidX(host.bounds), CGRectGetMidY(host.bounds));
    }
    if (CGSizeEqualToSize(p.bounds.size, size) && CGAffineTransformEqualToTransform(p.transform, t) && fabs(p.center.x - c.x) < 0.5 && fabs(p.center.y - c.y) < 0.5) return;
    p.transform = CGAffineTransformIdentity;
    p.bounds = CGRectMake(0, 0, size.width, size.height);
    p.center = c;
    p.transform = t;
    DMLog([NSString stringWithFormat:@"[wallpaper] desktop picture laid out as the interface is: %.0fx%.0f pt, turn [%.0f %.0f %.0f %.0f] (%@), centre %.0f,%.0f in the host %@",
           size.width, size.height, t.a, t.b, t.c, t.d, src, c.x, c.y, NSStringFromCGRect(host.bounds)]);
#if DEBUG
    if (DMTestFlag("/tmp/msb-wp-tree")) {   // (debug: the host's views, for the turn's study)
        NSMutableString *o2 = [NSMutableString stringWithString:@"[wallpaper] host tree:"];
        NSMutableArray *todo = [NSMutableArray arrayWithObject:@[host, @0]];
        while (todo.count && o2.length < 20000) {
            NSArray *e = todo.lastObject; [todo removeLastObject];
            UIView *v = e[0]; int d = [e[1] intValue];
            CATransform3D lt = v.layer.transform, st = v.layer.sublayerTransform;
            [o2 appendFormat:@"\n%*s%@ b%@ c%@ t[%.2f %.2f %.2f %.2f] lt[%.2f %.2f] st[%.2f %.2f] h%d a%.2f", d * 2, "", NSStringFromClass([v class]), NSStringFromCGRect(v.bounds), NSStringFromCGPoint(v.center),
                v.transform.a, v.transform.b, v.transform.c, v.transform.d, lt.m11, lt.m12, st.m11, st.m12, v.hidden, v.alpha];
            if (d < 6 && v != p) for (UIView *s2 in v.subviews.reverseObjectEnumerator) [todo addObject:@[s2, @(d + 1)]];
        }
        DMLog(o2);
    }
#endif
}

// ---- page 1 ----
@interface DMWPScrollWatch : NSObject
@end
static void DMWPUpdateAlpha(void);
@implementation DMWPScrollWatch
- (void)observeValueForKeyPath:(NSString *)k ofObject:(id)o change:(NSDictionary *)c context:(void *)ctx { DMWPUpdateAlpha(); }
@end
static DMWPScrollWatch *gWPWatch;
static void DMWPWatchScroll(UIScrollView *sc) {
    UIScrollView *old = gWPScroll;
    if (old == sc) return;
    if (!gWPWatch) gWPWatch = [DMWPScrollWatch new];
    if (old) @try { [old removeObserver:gWPWatch forKeyPath:@"contentOffset"]; } @catch (NSException *e) {}
    gWPScroll = sc;
    if (sc) [sc addObserver:gWPWatch forKeyPath:@"contentOffset" options:0 context:NULL];
}
// How much of page 1 is on screen: 1 on it, 0 a page (or more) away; the scroll view's own position, as the page turn moves it.
static double DMWPPageOneShown(void) {
    UIView *list = gWPPageOne;
    UIScrollView *sc = gWPScroll;
    if (!list || !sc || list.superview != sc) return 1.0;   // (not found yet: page 1, where the Home Screen opens)
    CGFloat pw = sc.bounds.size.width;
    if (pw < 100.0) return 1.0;
    CGFloat pageX = round(list.frame.origin.x / pw) * pw;
    double away = fabs(sc.contentOffset.x - pageX) / pw;
    return MAX(0.0, MIN(1.0, 1.0 - away));
}
// 15/16's shared view (one view for the Lock Screen and the Home Screen): ours shows only while the Home Screen is the active variant. Asked of the
// wallpaper controller, then of the object that held the view, as -activeVariant or -variant; nothing answers, or the iPad is locked or its
// screen blank: not shown (review 1.8.6 M1: fail closed -- the Lock Screen must never show our picture).
static BOOL DMWPSharedHomeNow(void) {
    static int lockTok = 0, blankTok = 0;
    if (!lockTok) notify_register_check("com.apple.springboard.lockstate", &lockTok);
    if (!blankTok) notify_register_check("com.apple.springboard.hasBlankedScreen", &blankTok);
    uint64_t locked = 0, blank = 0;
    if (lockTok) notify_get_state(lockTok, &locked);
    if (blankTok) notify_get_state(blankTok, &blank);
    if (locked || blank) return NO;
    id c = nil; DMWPWallpaperWindow(&c);
    for (id o in @[c ?: [NSNull null], gWPVariantOwner ?: [NSNull null]]) {
        if (o == [NSNull null]) continue;
        for (NSString *name in @[@"activeVariant", @"variant"]) {
            SEL sel = NSSelectorFromString(name);
            if ([o respondsToSelector:sel]) return ((long long (*)(id, SEL))objc_msgSend)(o, sel) == 1;
        }
    }
    static BOOL said; if (!said) { said = YES; DMLog(@"[wallpaper] the shared wallpaper view's active variant can't be read here: the desktop picture is not shown (the Lock Screen shares that view)"); }
    return NO;
}
static void DMWPUpdateAlpha(void) {
    if (gWPTVPlane) { double ta = gWPTVPlane.image ? 1.0 : 0.0; if (fabs(gWPTVPlane.alpha - ta) > 0.001) gWPTVPlane.alpha = ta; }   // (no pages on a TV)
    DMWPPlane *p = gWPPlane;
    if (!p) return;
    double a = p.image ? DMWPPageOneShown() : 0.0;
    if (p.sharedVariant && !DMWPSharedHomeNow()) a = 0.0;   // (15/16, one view for both variants: the Lock Screen keeps its own picture)
    if (fabs(p.alpha - a) <= 0.001) return;
    if (p.sharedVariant && p.alpha < 0.01 && a > 0.5) [UIView animateWithDuration:0.3 animations:^{ p.alpha = a; }];   // (back after an unlock: faded in, M1)
    else p.alpha = a;
}
// The lock and the screen going blank hide it at once in the shared view, not at the next tick (the tick is parked while the screen is blank, so a
// wake would show the Lock Screen with ours until it ran: M1).
static void DMWPWatchLock(void) {
    static BOOL on; if (on) return; on = YES;
    int t1 = 0, t2 = 0;
    notify_register_dispatch("com.apple.springboard.lockstate", &t1, dispatch_get_main_queue(), ^(int t) { DMWPUpdateAlpha(); });
    notify_register_dispatch("com.apple.springboard.hasBlankedScreen", &t2, dispatch_get_main_queue(), ^(int t) { DMWPUpdateAlpha(); });
}

// ---- the picture: decoded off the main thread, the part this screen shows, at its pixels ----
static CGImageRef DMWPDecode(NSString *path, CGSize points, CGFloat scale) CF_RETURNS_RETAINED {
    NSURL *url = [NSURL fileURLWithPath:path];
    CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!src) return NULL;
    size_t at = CGImageSourceGetPrimaryImageIndex(src);   // (a Mac's dynamic wallpaper (HEIC) holds several pictures: its primary one)
    NSDictionary *props = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(src, at, NULL));
    double iw = [props[(id)kCGImagePropertyPixelWidth] doubleValue], ih = [props[(id)kCGImagePropertyPixelHeight] doubleValue];
    int orient = [props[(id)kCGImagePropertyOrientation] intValue];
    if (orient >= 5 && orient <= 8) { double t = iw; iw = ih; ih = t; }   // (the picture as it is seen: its orientation applied below too)
    double spw = points.width * scale, sph = points.height * scale;
    CGRect part = MSBDWallpaperPart(path, iw, ih, spw, sph);   // (Fill Screen, or inside iPadOS's turnable circle)
    CGSize out = MSBDWallpaperDecodeSize(part, spw, sph);
    if (iw <= 0 || ih <= 0 || out.width < 1 || out.height < 1) { CFRelease(src); return NULL; }
    double k = out.width / part.size.width;   // (the whole picture at this factor: the part then comes out at the screen's pixels)
    double budget = 2.0 * spw * sph;          // (but never more than twice the screen's pixels decoded: a panorama on a portrait screen would be decoded
    if (iw * k * ih * k > budget) k = sqrt(budget / (iw * ih));   //  nearly whole, ~120 MB in SpringBoard -- its slice is then a little softer, review 1.8.6 M3)
    NSDictionary *opt = @{(id)kCGImageSourceCreateThumbnailFromImageAlways: @YES, (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
                          (id)kCGImageSourceThumbnailMaxPixelSize: @(ceil(MAX(iw, ih) * k)), (id)kCGImageSourceShouldCacheImmediately: @YES};
    CGImageRef whole = CGImageSourceCreateThumbnailAtIndex(src, at, (__bridge CFDictionaryRef)opt);
    CFRelease(src);
    if (!whole) return NULL;
    double fx = CGImageGetWidth(whole) / iw, fy = CGImageGetHeight(whole) / ih;   // (the factor ImageIO really used)
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, (size_t)out.width, (size_t)out.height, 8, 0, cs, kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(cs);
    if (!ctx) { CGImageRelease(whole); return NULL; }
    CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
    // (the part's top-left at the context's top-left; Core Graphics counts y from the bottom)
    CGFloat wx = part.origin.x * fx, wy = part.origin.y * fy, ww = CGImageGetWidth(whole), wh = CGImageGetHeight(whole);
    double sx = out.width / (part.size.width * fx), sy = out.height / (part.size.height * fy);
    CGContextDrawImage(ctx, CGRectMake(-wx * sx, -(wh - wy - part.size.height * fy) * sy, ww * sx, wh * sy), whole);
    CGImageRelease(whole);
    CGImageRef img = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return img;
}
static BOOL DMWPDarkNow(UIView *v) {   // (the iPad's Light / Dark appearance: its own screen's, which every window follows -- a TV's picture too)
    return [UIScreen mainScreen].traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
}
static BOOL DMWPSameShape(CGSize a, CGSize b) { return a.width > 0 && b.width > 0 && b.height > 0 && fabs(a.width / a.height - b.width / b.height) < 0.02; }
// The picture to show now: the dark one in Dark appearance when there is one and it could be read, else the light one.
static NSString *DMWPWantedPath(DMWPPlane *p) {
    if (gWPDark && DMWPDarkNow(p) && !([p.failedPath isEqualToString:gWPDark] && DMWPSameShape(p.bounds.size, p.failedFor))) return gWPDark;
    return gWPLight;
}
static void DMWPDecodeIfNeeded(DMWPPlane *p) {
    if (!p || p.decoding || !gWPLight) return;
    CGSize pts = p.bounds.size;
    if (pts.width < 100.0 || pts.height < 100.0) return;
    NSString *path = DMWPWantedPath(p);
    if ([p.failedPath isEqualToString:path] && DMWPSameShape(pts, p.failedFor)) return;   // (could not be read: not again at every tick, M2)
    if ([p.shownPath isEqualToString:path] && DMWPSameShape(pts, p.shownFor) && p.image) return;
    p.decoding = YES;
    UIScreen *scr = p.window.screen ?: [UIScreen mainScreen];
    CGFloat scale = scr.scale ?: [UIScreen mainScreen].scale;
    if (scr != [UIScreen mainScreen]) {   // (a TV: its own pixels, not the render size -- a 4K TV at 2560x1440 pt is drawn at 2x, 5120 px, and sent out at
        //  its 3840 x 2160 mode; UIScreen's currentMode says the render size there, the display's own mode the TV's -- A12Z, 10 Nov, d01)
        CGFloat px = 0;
        id disp = [scr respondsToSelector:NSSelectorFromString(@"_display")] ? DMCall(scr, @"_display") : nil;
        id mode = disp ? DMCall(disp, @"currentMode") : nil;
        SEL ws = NSSelectorFromString(@"width"), hs = NSSelectorFromString(@"height");
        if ([mode respondsToSelector:ws] && [mode respondsToSelector:hs]) px = MAX(((long (*)(id, SEL))objc_msgSend)(mode, ws), ((long (*)(id, SEL))objc_msgSend)(mode, hs));
        if (px <= 0 && scr.currentMode) px = MAX(scr.currentMode.size.width, scr.currentMode.size.height);
        CGFloat pt = MAX(scr.bounds.size.width, scr.bounds.size.height);
        if (pt > 0 && px > 0 && px / pt > 0.5 && px / pt < scale) scale = px / pt;
    }
    __weak DMWPPlane *wp = p;
    CFTimeInterval t0 = CACurrentMediaTime();
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        CGImageRef img = DMWPDecode(path, pts, scale);
        dispatch_async(dispatch_get_main_queue(), ^{
            DMWPPlane *q = wp;
            if (q) {
                q.decoding = NO;
                if (img && (q == gWPPlane || q == gWPTVPlane) && [path isEqualToString:DMWPWantedPath(q)]) {
                    q.image = [UIImage imageWithCGImage:img scale:scale orientation:UIImageOrientationUp];
                    q.shownPath = path; q.shownFor = pts;
                    DMLog([NSString stringWithFormat:@"[wallpaper] %@ decoded for %@%.0fx%.0f pt at @%.2gx: %zux%zu px (%.0f ms)", path.lastPathComponent, q == gWPTVPlane ? @"the external display, " : @"", pts.width, pts.height, scale,
                           CGImageGetWidth(img), CGImageGetHeight(img), (CACurrentMediaTime() - t0) * 1000.0]);
                    DMWPUpdateAlpha();
                } else if (!img && (q == gWPPlane || q == gWPTVPlane)) {
                    q.failedPath = path; q.failedFor = pts;   // (not tried again until the choice, the file or the screen's shape changes: M2)
                    BOOL darkFails = [path isEqualToString:gWPDark];
                    if (!darkFails) { q.image = nil; q.shownPath = nil; DMWPUpdateAlpha(); }   // (no picture before it left on screen: iPadOS's shows, L1)
                    DMLog([NSString stringWithFormat:@"[wallpaper] %@ could not be read: %@", path.lastPathComponent, darkFails ? @"the light picture is shown in Dark appearance" : @"nothing drawn"]);
                }
            }
            if (img) CGImageRelease(img);
        });
    });
}
static void DMWPPlaneLaidOut(DMWPPlane *p) { if (p == gWPPlane || p == gWPTVPlane) DMWPDecodeIfNeeded(p); }

// ---- an external display's desktop (18.5: SBExternalDisplayWallpaperViewController in a window on the TV's screen) ----
static UIView *DMWPFindTVHost(NSString **note) {
    NSMutableArray *seen = [NSMutableArray array];
    for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
        if (![sc isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)sc).windows) {
            if (!w.screen || w.screen == [UIScreen mainScreen]) continue;
            UIView *v = DMWPViewOfController(w, @"SBExternalDisplayWallpaperViewController");
            if (!v) { if (seen.count < 12) [seen addObject:NSStringFromClass([w class])]; continue; }
            UIResponder *vc = v.nextResponder;
            SEL cs = NSSelectorFromString(@"wallpaperContainerView");
            id c = [vc respondsToSelector:cs] ? ((id (*)(id, SEL))objc_msgSend)(vc, cs) : nil;
            UIView *host = [c isKindOfClass:[UIView class]] && ((UIView *)c).window == w ? c : v;
            *note = [NSString stringWithFormat:@"on the external display: in %@ (%@ > SBExternalDisplayWallpaperViewController%@)", NSStringFromClass([host class]), NSStringFromClass([w class]), host == v ? @"" : @" > wallpaperContainerView"];
            return host;
        }
    }
    *note = seen.count ? [NSString stringWithFormat:@"on the external display: no wallpaper view controller in its windows (%@): not drawn there", [seen componentsJoinedByString:@", "]] : nil;
    return nil;
}
static void DMWPTVTick(void) {
    UIView *host = gWPTVHost;
    if (!gWPTVPlane || gWPTVPlane.superview != host || !host || !host.window) {
        static CFTimeInterval tried; if (CACurrentMediaTime() - tried < 1.0) return; tried = CACurrentMediaTime();
        NSString *note = nil;
        host = DMWPFindTVHost(&note);
        if (note && ![note isEqualToString:gWPTVNote]) { gWPTVNote = note; DMLog([NSString stringWithFormat:@"[wallpaper] desktop picture %@", note]); }
        if (!host) { if (gWPTVPlane) DMWPRemoveTV(@"no external display desktop now"); return; }   // (the TV gone: its picture freed)
        if (!gWPTVPlane) {
            gWPTVPlane = [[DMWPPlane alloc] initWithFrame:host.bounds];
            gWPTVPlane.contentMode = UIViewContentModeScaleAspectFill;
            gWPTVPlane.clipsToBounds = YES;
            gWPTVPlane.userInteractionEnabled = NO;
            gWPTVPlane.accessibilityIgnoresInvertColors = YES;
            gWPTVPlane.alpha = 0.0;
        }
        gWPTVHost = host;
        [host addSubview:gWPTVPlane];
    }
    if (host.subviews.lastObject != gWPTVPlane) [host bringSubviewToFront:gWPTVPlane];
    if (!CGAffineTransformIsIdentity(gWPTVPlane.transform)) gWPTVPlane.transform = CGAffineTransformIdentity;
    if (!CGRectEqualToRect(gWPTVPlane.frame, host.bounds)) gWPTVPlane.frame = host.bounds;   // (a TV doesn't turn: its desktop's own bounds)
    DMWPDecodeIfNeeded(gWPTVPlane);
}

// ---- every tick (DMNativeTick, 0.2 s): in place while set, gone when not ----
static void DMWPTick(void) {
    if (!gWPRead) DMWPApplyPref();
    if (!gWPLight || DMCtorSkip("wallpaper")) { if (gWPPlane || gWPTVPlane) DMWPRemove(@"off"); DMWPWatchScroll(nil); return; }
    DMWPTVTick();      // (an external display's desktop: the same picture, KT 10 Nov)
    UIView *host = gWPHost;
    if (!gWPPlane || gWPPlane.superview != host || !host || !host.window) {
        static CFTimeInterval tried; if (CACurrentMediaTime() - tried < 1.0) return; tried = CACurrentMediaTime();
        BOOL shared = NO; NSString *note = nil;
        host = DMWPFindHost(&shared, &note);
        if (![note isEqualToString:gWPHostNote]) { gWPHostNote = note; DMLog([NSString stringWithFormat:@"[wallpaper] desktop picture %@", note]); }
        if (!host) return;
        if (!gWPPlane) {
            gWPPlane = [[DMWPPlane alloc] initWithFrame:host.bounds];
            gWPPlane.contentMode = UIViewContentModeScaleAspectFill;   // (while a turned screen's part is decoded, the last one fills the screen)
            gWPPlane.clipsToBounds = YES;
            gWPPlane.userInteractionEnabled = NO;
            gWPPlane.accessibilityIgnoresInvertColors = YES;   // (a picture: Smart Invert leaves it, as it leaves the wallpaper)
            gWPPlane.alpha = 0.0;
        }
        gWPPlane.sharedVariant = shared;
        if (shared) DMWPWatchLock();
        gWPHost = host;
        [host addSubview:gWPPlane];
    }
    if (host.subviews.lastObject != gWPPlane) [host bringSubviewToFront:gWPPlane];   // (a view iPadOS adds to its variant later goes under ours)
    DMWPFollowTurn(gWPPlane, host);   // (the interface's shape and turn, as PosterBoard's poster has them)
    {   // (page 1's list and its scroll view: kept, looked for again when gone, as the desktop does -- Desktop.h DMDesktopFindPageOne)
        UIView *list = gWPPageOne;
        static CFTimeInterval checked;
        if (!list || !list.window || ![list.superview isKindOfClass:[UIScrollView class]] || CACurrentMediaTime() - checked > 2.0) {
            checked = CACurrentMediaTime();
            UIView *found = DMDesktopFindPageOne();
            if (found) { gWPPageOne = found; DMWPWatchScroll((UIScrollView *)found.superview); }
        }
    }
    DMWPDecodeIfNeeded(gWPPlane);
    DMWPUpdateAlpha();
}
