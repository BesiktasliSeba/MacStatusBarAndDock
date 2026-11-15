// test-switcherwall.m -- see test-switcherwall.sh. Mac Catalyst: the Mac Switcher's wallpaper code (cut out of statusbar/MacSwitcher.h) and
// the Desktop Picture's view for it (statusbar/DesktopWallpaper.h) on stand-ins: our picture view as DesktopWallpaper.h makes it (a UIImageView
// in the Home Screen variant's view, its picture decoded) and iPadOS's wallpaper view under it (an image view holding iPadOS's picture).
// The views the switcher gives the picture besides its background (MacSwitcher.h DMMSWWallView: a desktop drawn from its parts, the strip's tile
// of a desktop showing only its wallpaper) are made here as the switcher makes them (1.8.7.5 SWTHUMBS).
// One scenario per process: `t list`, `t <scenario>`. Each check prints PASS / FAIL.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static int gFails = 0;
static void check(BOOL ok, NSString *what) { printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); if (!ok) gFails++; }

// ---- stand-ins for what the cut code uses from elsewhere ----
static NSMutableArray<NSString *> *gLog;
static void DMLog(NSString *s) { [gLog addObject:s]; }
static BOOL DMTestFlag(const char *path) { return NO; }
static BOOL DMMSWHasMethod(Class c, NSString *sel, NSString *types) { return c && class_getInstanceMethod(c, NSSelectorFromString(sel)) != NULL; }
static id DMCall(id o, NSString *sel) { return ((id (*)(id, SEL))objc_msgSend)(o, NSSelectorFromString(sel)); }
// DesktopWallpaper.h's state, as its tick leaves it: our picture view (there while a picture is set) in the Home Screen variant's view.
// gTLayerLate: UIKit as the M1 (15.6.1, 1.8.7.5~a01) showed it -- the view's layer takes a new picture only at the view's next layout, not in
// -setImage: (Mac Catalyst's UIKit fills it at once, so the gap did not show here before).
static BOOL gTLayerLate;
@interface DMWPPlane : UIImageView
@end
@implementation DMWPPlane
- (void)setImage:(UIImage *)image {
    id before = self.layer.contents;
    [super setImage:image];
    if (gTLayerLate && before) { self.layer.contents = before; [self setNeedsLayout]; }
}
- (void)layoutSubviews { [super layoutSubviews]; if (gTLayerLate) self.layer.contents = (__bridge id)self.image.CGImage; }
@end
static DMWPPlane *gWPPlane;
static __weak UIView *gWPHost;
#include "sw-wp.inc"          // (DesktopWallpaper.h: the desktop picture for the Mac Switcher -- not in the code before the fix)
// iPadOS's Home Screen wallpaper view (SBFWallpaperView / PosterBoard's, as DMMSWWallpaperView finds it): an image view holding iPadOS's picture
@interface TIPadOSWall : UIView
@property (nonatomic, strong) UIImage *picture;
@end
@implementation TIPadOSWall
- (UIImage *)wallpaperImage { return self.picture; }
@end
static TIPadOSWall *gTWall;
static UIView *DMMSWWallpaperView(void) { return gTWall; }
static NSInteger gTTurn = 1;
static UIView *gMSWRoot;   // (MacSwitcher.h: the open switcher's content, nil while closed)
static BOOL DMMSWIsMain(void) { return YES; }
#include "sw-compat.inc"      // (the code before the fix: what it does not have)
#include "sw-real.inc"        // (MacSwitcher.h: the wallpaper's state, DMMSWApplyWall, DMMSWWallView, DMMSWWallpaperImageView, DMMSWWallImage, DMMSWWallpaperBackground, DMMSWWallLazy)
#include "sw-compat2.inc"     // (the code before SWTHUMBS: DMMSWWallView as its places made the view, nothing remembered)
static NSInteger DMMSWTurnKey(void) { return gTTurn; }

static CGImageRef TPicture(CGFloat r, CGFloat g, CGFloat b, size_t w, size_t h) {   // (a one-colour picture)
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, 0, cs, kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(cs);
    CGContextSetRGBFillColor(ctx, r, g, b, 1); CGContextFillRect(ctx, CGRectMake(0, 0, w, h));
    CGImageRef img = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return img;
}
// ---- the world: the iPad's screen, the wallpaper window (iPadOS's wallpaper view and, over it, the Home Screen variant's view holding ours), the
// Mac Switcher's root ----
typedef struct { UIWindow *wall, *msw; UIView *host, *root; CGImageRef apple, ours; } TWorld;
static TWorld TMake(BOOL withOurs, BOOL decoded) {
    TWorld w;
    CGRect b = [UIScreen mainScreen].bounds;
    w.apple = TPicture(0.1, 0.4, 0.4, (size_t)b.size.width, (size_t)b.size.height);   // (iPadOS's: a dark teal)
    w.ours = TPicture(0.8, 0.85, 0.95, (size_t)b.size.width, (size_t)b.size.height);  // (ours: High Sierra's light sky)
    w.wall = [[UIWindow alloc] initWithFrame:b]; w.wall.hidden = NO;
    gTWall = [[TIPadOSWall alloc] initWithFrame:w.wall.bounds];
    gTWall.picture = [UIImage imageWithCGImage:w.apple];
    UIView *appleImage = [[UIView alloc] initWithFrame:gTWall.bounds];
    appleImage.layer.contents = (__bridge id)w.apple;
    [gTWall addSubview:appleImage];
    [w.wall addSubview:gTWall];
    w.host = [[UIView alloc] initWithFrame:w.wall.bounds];
    [w.wall addSubview:w.host];
    gWPHost = w.host;
    if (withOurs) {
        gWPPlane = [[DMWPPlane alloc] initWithFrame:w.host.bounds];
        gWPPlane.contentMode = UIViewContentModeScaleAspectFill;
        if (decoded) gWPPlane.image = [UIImage imageWithCGImage:w.ours];
        [w.host addSubview:gWPPlane];
    }
    w.msw = [[UIWindow alloc] initWithFrame:b]; w.msw.hidden = NO;
    w.root = [[UIView alloc] initWithFrame:w.msw.bounds];
    [w.msw addSubview:w.root];
    return w;
}
static id TBackground(TWorld w, NSString **why) { UIView *v = DMMSWWallpaperBackground(w.root, why); return v.layer.contents; }
static BOOL TLogHas(NSString *part) { for (NSString *l in gLog) if ([l containsString:part]) return YES; return NO; }
static NSString *TWhich(TWorld w, id c) { return c == (__bridge id)w.ours ? @"ours" : c == (__bridge id)w.apple ? @"iPadOS's" : c ? @"another" : @"none"; }

// The switcher opened: its background as DMMSWBuildRoot takes it (black, the picture, a dim over it), the picture kept as gMSWBackWall
static UIView *TOpen(TWorld w) {
    NSString *why = nil;
    UIView *back = [[UIView alloc] initWithFrame:w.root.bounds];
    UIView *wall = DMMSWWallpaperBackground(w.root, &why);
    if (wall) [back addSubview:wall];
    [back addSubview:[[UIView alloc] initWithFrame:w.root.bounds]];
    [w.root addSubview:back];
    gMSWRoot = w.root; gMSWBackWall = wall;
    return back;
}
// Our picture decoded anew (another picture, the screen's other shape, the dark version): as DesktopWallpaper.h's decode leaves it
static CGImageRef TDecodedAnew(TWorld w, CGFloat r, CGFloat g, CGFloat b) {
    CGImageRef other = TPicture(r, g, b, (size_t)w.root.bounds.size.width, (size_t)w.root.bounds.size.height);
    gWPPlane.image = [UIImage imageWithCGImage:other];
    DMMSWOurWallChanged();
    return other;
}

// ---- scenarios ----
static void SNone(void) {   // no Desktop Picture: iPadOS's wallpaper, as before
    TWorld w = TMake(NO, NO); NSString *why = nil;
    id c = TBackground(w, &why);
    check(c == (__bridge id)w.apple, [NSString stringWithFormat:@"no Desktop Picture: the background is iPadOS's wallpaper (is %@)", TWhich(w, c)]);
    check(!TLogHas(@"our Desktop Picture"), @"the log does not name ours");
}
static void SOurs(void) {   // KT's 17.5: our Desktop Picture on: the background and the desktops drawn from their parts show ours
    TWorld w = TMake(YES, YES); NSString *why = nil;
    id c = TBackground(w, &why);
    check(c == (__bridge id)w.ours, [NSString stringWithFormat:@"Desktop Picture on: the background is our picture (is %@)", TWhich(w, c)]);
    check(gMSWWallContents == (__bridge id)w.ours, @"... and the desktops drawn from their parts take it (gMSWWallContents)");
    check(TLogHas(@"wallpaper taken as shown") && TLogHas(@": our Desktop Picture"), @"taken as shown (upright, covering the screen), and the log says it is ours");
    check([gMSWWallGravity isEqual:gWPPlane.layer.contentsGravity], @"drawn as our view draws it (its gravity)");
}
static void SDecoding(void) {   // our view there, its picture not decoded yet: iPadOS's (what the desktop shows meanwhile); ours at the next opening
    TWorld w = TMake(YES, NO); NSString *why = nil;
    id c = TBackground(w, &why);
    check(c == (__bridge id)w.apple, [NSString stringWithFormat:@"not decoded yet: iPadOS's wallpaper (is %@)", TWhich(w, c)]);
    gWPPlane.image = [UIImage imageWithCGImage:w.ours];
    c = TBackground(w, &why);
    check(c == (__bridge id)w.ours, [NSString stringWithFormat:@"decoded: ours at the next opening (is %@)", TWhich(w, c)]);
}
static void SChanged(void) {   // another picture chosen (or the dark one at dark appearance): taken again
    TWorld w = TMake(YES, YES); NSString *why = nil;
    TBackground(w, &why);
    CGImageRef other = TPicture(0.2, 0.2, 0.25, (size_t)w.root.bounds.size.width, (size_t)w.root.bounds.size.height);
    gWPPlane.image = [UIImage imageWithCGImage:other];
    id c = TBackground(w, &why);
    check(c == (__bridge id)other, @"another picture of ours: taken again at the next opening");
}
static void SLazy(void) {   // a desktop drawn from its parts before the switcher ever opened (or after memory pressure): ours
    TWorld w = TMake(YES, YES);
    DMMSWWallLazy();
    check(gMSWWallContents == (__bridge id)w.ours, [NSString stringWithFormat:@"a desktop drawn from its parts first: our picture (is %@)", TWhich(w, gMSWWallContents)]);
    check(TLogHas(@"our Desktop Picture"), @"the log says it is ours");
}
static void SFill(void) {   // our view not upright in the switcher's view (a turn not followed yet): ours, filling the screen
    TWorld w = TMake(YES, YES); NSString *why = nil;
    gWPPlane.transform = CGAffineTransformMakeRotation(M_PI_2);
    id c = TBackground(w, &why);
    check(c == (__bridge id)w.ours && TLogHas(@"filling the screen"), [NSString stringWithFormat:@"not upright: our picture filling the screen (is %@)", TWhich(w, c)]);
}
static void SFullScreen(void) {   // an app in full screen: the wallpaper window hidden, the desktop's picture still ours
    TWorld w = TMake(YES, YES); NSString *why = nil;
    w.wall.hidden = YES;
    id c = TBackground(w, &why);
    check(c == (__bridge id)w.ours, [NSString stringWithFormat:@"the wallpaper window hidden: our picture (is %@)", TWhich(w, c)]);
}
static void SOff(void) {   // Desktop Picture set back to None (our view removed): iPadOS's again at the next opening
    TWorld w = TMake(YES, YES); NSString *why = nil;
    TBackground(w, &why);
    [gWPPlane removeFromSuperview]; gWPPlane = nil;   // (DMWPRemove)
    id c = TBackground(w, &why);
    check(c == (__bridge id)w.apple, [NSString stringWithFormat:@"None again: iPadOS's wallpaper (is %@)", TWhich(w, c)]);
}
static void SElsewhere(void) {   // our view not in its place (left over, not in the Home Screen variant's view any more): iPadOS's
    TWorld w = TMake(YES, YES); NSString *why = nil;
    UIView *other = [[UIView alloc] initWithFrame:w.host.bounds]; [w.wall addSubview:other]; [other addSubview:gWPPlane];
    id c = TBackground(w, &why);
    check(c == (__bridge id)w.apple, [NSString stringWithFormat:@"our view out of its place: iPadOS's wallpaper (is %@)", TWhich(w, c)]);
}

static void SPageTwo(void) {   // the Home Screen on another page (ours faded out there): the switcher's desktops are page 1, ours
    TWorld w = TMake(YES, YES); NSString *why = nil;
    gWPPlane.alpha = 0.0;
    id c = TBackground(w, &why);
    check(c == (__bridge id)w.ours, [NSString stringWithFormat:@"opened from page 2 (ours at alpha 0 there): the desktops' picture, ours (is %@)", TWhich(w, c)]);
}
static void SLazyChanged(void) {   // a desktop drawn from its parts, then another picture of ours (or its dark version) without an opening between
    TWorld w = TMake(YES, YES);
    DMMSWWallLazy();
    CGImageRef other = TDecodedAnew(w, 0.2, 0.2, 0.25);
    check(gMSWWallContents != (__bridge id)w.ours, @"our picture changed: the old copy let go at once (not kept in memory until the next opening)");
    DMMSWWallLazy();
    check(gMSWWallContents == (__bridge id)other, [NSString stringWithFormat:@"the next desktop drawn from its parts: the picture shown now (is %@)", gMSWWallContents == (__bridge id)w.ours ? @"the old one" : @"another"]);
}
static void SLazyNone(void) {   // a desktop drawn from its parts, then Desktop Picture None
    TWorld w = TMake(YES, YES);
    DMMSWWallLazy();
    [gWPPlane removeFromSuperview]; gWPPlane = nil; DMMSWOurWallChanged();   // (DMWPRemove)
    check(gMSWWallContents == nil, @"None: our picture's copy let go");
    DMMSWWallLazy();
    check(gMSWWallContents == (__bridge id)w.apple, [NSString stringWithFormat:@"the next desktop drawn from its parts: iPadOS's wallpaper (is %@)", TWhich(w, gMSWWallContents)]);
}
static void SOpenTurn(void) {   // the switcher open; the screen turns and our picture is decoded for the new shape afterwards
    TWorld w = TMake(YES, YES);
    UIView *back = TOpen(w);
    check(back.subviews.firstObject.layer.contents == (__bridge id)w.ours, @"open: the background is ours");
    CGImageRef turned = TDecodedAnew(w, 0.6, 0.7, 0.8);
    check(back.subviews.count == 2 && back.subviews.firstObject.layer.contents == (__bridge id)turned,
          [NSString stringWithFormat:@"our picture decoded anew while the switcher is open: its background taken again at once (%lu views, %@)", (unsigned long)back.subviews.count,
           back.subviews.firstObject.layer.contents == (__bridge id)w.ours ? @"the old picture" : @"the new picture"]);
    check(TLogHas(@"our Desktop Picture changed while shown: the background taken again"), @"the log says so");
}
static void SOpenChangedLate(void) {   // the M1's gap (1.8.7.5~a01, 15.6.1): the switcher open, another picture of ours chosen, then its dark version;
                                       // our view's layer takes each only at the view's next layout, after the switcher is told
    TWorld w = TMake(YES, YES); NSString *why = nil;
    UIView *back = TOpen(w);
    check(back.subviews.firstObject.layer.contents == (__bridge id)w.ours, @"open: the background is ours");
    gTLayerLate = YES;
    [gLog removeAllObjects];
    CGImageRef other = TDecodedAnew(w, 0.2, 0.2, 0.25);
    check(gWPPlane.layer.contents == (__bridge id)w.ours, @"(the stand-in, as on the M1: our view's layer still has the picture before when the switcher is told)");
    id c = back.subviews.firstObject.layer.contents;
    check(back.subviews.count == 2 && c == (__bridge id)other, [NSString stringWithFormat:@"another picture of ours chosen while the switcher is open: its background is the new picture at once (is %@)",
          c == (__bridge id)w.ours ? @"the picture before, as on the M1" : c == (__bridge id)other ? @"the new picture" : TWhich(w, c)]);
    check(TLogHas(@"wallpaper taken as shown") && TLogHas(@"its view's layer still has the one before"), @"taken as shown (not the fill), and the log says the view's layer still had the picture before");
    [gWPPlane setNeedsLayout]; [gWPPlane layoutIfNeeded];   // (UIKit's layout: the layer gets it)
    check(gWPPlane.layer.contents == (__bridge id)other, @"(the stand-in: after its layout our view's layer has the new picture)");
    [gLog removeAllObjects];
    c = TBackground(w, &why);
    check(c == (__bridge id)other && !TLogHas(@"wallpaper taken"), [NSString stringWithFormat:@"opened again: the same picture, kept (%@)", TLogHas(@"wallpaper taken") ? @"taken again" : @"not taken again"]);
    CGImageRef dark = TDecodedAnew(w, 0.05, 0.05, 0.1);   // (KT's Dark appearance: the picture's dark version)
    c = back.subviews.firstObject.layer.contents;
    check(back.subviews.count == 2 && c == (__bridge id)dark, [NSString stringWithFormat:@"its dark version decoded while the switcher is open: the background is the dark one at once (is %@)",
          c == (__bridge id)other ? @"the picture before" : c == (__bridge id)dark ? @"the dark one" : TWhich(w, c)]);
}
static void SNotOurs(void) {   // iPadOS's wallpaper taken (no Desktop Picture): a change of ours has nothing to let go
    TWorld w = TMake(NO, NO); NSString *why = nil;
    TBackground(w, &why);
    DMMSWOurWallChanged();
    check(gMSWWallContents == (__bridge id)w.apple, @"iPadOS's wallpaper taken: kept");
}

// ---- 1.8.7.5 SWTHUMBS (the iPad 2's check of a01, 16.7.7, and the M1): the other desktops' thumbnails and None -> a picture while open ----
static NSString *TPlace(UIView *v) { return [NSString stringWithFormat:@"%@ at %@ x%.3f", NSStringFromCGRect(v.bounds), NSStringFromCGPoint(v.center), v.transform.a]; }
static BOOL TClose(CGFloat a, CGFloat b) { return fabs(a - b) < 0.01; }
static BOOL TSamePlace(UIView *a, UIView *b) {   // (placed alike: the background and a desktop of the screen's size drawn from its parts)
    return TClose(a.bounds.size.width, b.bounds.size.width) && TClose(a.bounds.size.height, b.bounds.size.height) && TClose(a.center.x, b.center.x) && TClose(a.center.y, b.center.y)
        && TClose(a.transform.a, b.transform.a) && TClose(a.transform.d, b.transform.d) && TClose(a.transform.b, 0) && TClose(a.transform.c, 0);
}
static NSMutableArray<UIView *> *gTKeep;   // (the pictures the views are in: kept, as the strip, a slide or gMSWShots keeps them)
static UIView *TDrawn(TWorld w, CGSize s) {   // (a desktop drawn from its parts, s big: DMMSWComposedDesktop / DMMSWSMComposedDesktop / DMMSWDeskPicture's view)
    UIView *c = [[UIView alloc] initWithFrame:CGRectMake(0, 0, s.width, s.height)];
    c.clipsToBounds = YES;
    if (!gTKeep) gTKeep = [NSMutableArray array];
    [gTKeep addObject:c];
    DMMSWWallLazy();   // (as each of them asks first)
    return DMMSWWallView(c, NO);
}
static UIView *TTile(void) {   // (the strip's tile of a desktop not seen since the respring: DMMSWBuildStrip)
    UIView *clip = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 120, 90)];
    clip.clipsToBounds = YES;
    if (!gTKeep) gTKeep = [NSMutableArray array];
    [gTKeep addObject:clip];
    if (!gMSWWallContents) DMMSWWallLazy();
    return DMMSWWallView(clip, YES);
}
static id TTransformOf(UIView *v) { id t = nil; @try { t = [v.layer valueForKey:@"contentsTransform"]; } @catch (NSException *e) {} return t; }
static void SOpenThumbs(void) {   // the switcher open over ours, KT's 3 desktops: Desktop 1 drawn from its parts, Desktop 3 not seen since the respring
    TWorld w = TMake(YES, YES);
    UIView *back = TOpen(w);
    UIView *d1 = TDrawn(w, w.root.bounds.size), *d3 = TTile();
    UIView *bg = back.subviews.firstObject;
    check(d1.layer.contents == (__bridge id)w.ours && d3.layer.contents == (__bridge id)w.ours, @"open: Desktop 1 (drawn from its parts) and Desktop 3 (its wallpaper only) show ours");
    check(TSamePlace(d1, bg), [NSString stringWithFormat:@"Desktop 1's picture placed as the background (%@; the background %@)", TPlace(d1), TPlace(bg)]);
    check(CGRectEqualToRect(d3.frame, d3.superview.bounds) && [d3.layer.contentsGravity isEqualToString:kCAGravityResizeAspectFill], @"Desktop 3's tile: the picture fills the tile");
    gTLayerLate = YES;   // (as on the M1: our view's layer takes the picture at its next layout)
    [gLog removeAllObjects];
    CGImageRef other = TDecodedAnew(w, 0.2, 0.2, 0.25);
    bg = back.subviews.firstObject;
    check(bg.layer.contents == (__bridge id)other, @"another picture of ours chosen while open: the background is the new picture at once");
    check(d1.layer.contents == (__bridge id)other, [NSString stringWithFormat:@"... Desktop 1's thumbnail too, at once (is %@)", d1.layer.contents == (__bridge id)w.ours ? @"the picture before, as on the iPad 2" : TWhich(w, d1.layer.contents)]);
    check(d3.layer.contents == (__bridge id)other, [NSString stringWithFormat:@"... Desktop 3's thumbnail too, at once (is %@)", d3.layer.contents == (__bridge id)w.ours ? @"the picture before, as on the iPad 2" : TWhich(w, d3.layer.contents)]);
    check(TSamePlace(d1, bg) && CGRectEqualToRect(d3.frame, d3.superview.bounds) && [d3.layer.contentsGravity isEqualToString:kCAGravityResizeAspectFill], @"... placed as they were made: Desktop 1 as the background, Desktop 3 filling its tile");
    check(TLogHas(@"our Desktop Picture changed while shown: the background taken again (our picture as decoded") && TLogHas(@"and 2 desktop thumbnail(s) or picture(s) drawn from their parts with it"), @"the log says the background and 2 desktop pictures took it");
    [gWPPlane removeFromSuperview]; gWPPlane = nil; DMMSWOurWallChanged();   // (Desktop Picture None while open: DMWPRemove)
    bg = back.subviews.firstObject;
    check(bg.layer.contents == (__bridge id)w.apple, [NSString stringWithFormat:@"None while open: the background is iPadOS's wallpaper at once (is %@)", TWhich(w, bg.layer.contents)]);
    check(d1.layer.contents == (__bridge id)w.apple && d3.layer.contents == (__bridge id)w.apple, [NSString stringWithFormat:@"... and both other desktops' thumbnails, at once (Desktop 1 %@, Desktop 3 %@; the iPad 2 kept ours in both)",
          d1.layer.contents == (__bridge id)other ? @"ours before" : TWhich(w, d1.layer.contents), d3.layer.contents == (__bridge id)other ? @"ours before" : TWhich(w, d3.layer.contents)]);
}
static void SOpenFromNone(void) {   // no Desktop Picture, the switcher open (iPadOS 17's poster: turned by its layer's contentsTransform), a picture chosen
    TWorld w = TMake(NO, NO);
    UIView *appleImage = gTWall.subviews.firstObject;
    NSValue *turn = [NSValue valueWithCGAffineTransform:CGAffineTransformMakeRotation(M_PI_2)];
    @try { [appleImage.layer setValue:turn forKey:@"contentsTransform"]; } @catch (NSException *e) {}
    UIView *back = TOpen(w);
    UIView *d1 = TDrawn(w, w.root.bounds.size), *d3 = TTile();
    check(back.subviews.firstObject.layer.contents == (__bridge id)w.apple && d1.layer.contents == (__bridge id)w.apple && d3.layer.contents == (__bridge id)w.apple, @"open with None: the background and the other desktops show iPadOS's wallpaper");
    id t = TTransformOf(d1);
    check([t isKindOfClass:[NSValue class]] && !CGAffineTransformIsIdentity([t CGAffineTransformValue]), @"(iPadOS's poster in Desktop 1 turned as shown, its contentsTransform)");
    [gLog removeAllObjects];
    gWPPlane = [[DMWPPlane alloc] initWithFrame:w.host.bounds];   // (Settings > Desktop Picture: our view placed, then its picture decoded and the switcher told)
    gWPPlane.contentMode = UIViewContentModeScaleAspectFill;
    [w.host addSubview:gWPPlane];
    gWPPlane.image = [UIImage imageWithCGImage:w.ours];
    DMMSWOurWallChanged();
    id c = back.subviews.firstObject.layer.contents;
    check(c == (__bridge id)w.ours, [NSString stringWithFormat:@"a picture chosen from None while open: the background is ours at once (is %@)", c == (__bridge id)w.apple ? @"iPadOS's, as on the iPad 2 and the M1" : TWhich(w, c)]);
    check(d1.layer.contents == (__bridge id)w.ours && d3.layer.contents == (__bridge id)w.ours, [NSString stringWithFormat:@"... and the other desktops' thumbnails (Desktop 1 %@, Desktop 3 %@)", TWhich(w, d1.layer.contents), TWhich(w, d3.layer.contents)]);
    t = TTransformOf(d1);
    check(!t || ([t isKindOfClass:[NSValue class]] && CGAffineTransformIsIdentity([t CGAffineTransformValue])), @"... Desktop 1's picture not turned by iPadOS's poster's contentsTransform any more (ours has none)");
    check(TLogHas(@"our Desktop Picture chosen over iPadOS's wallpaper while shown: the background taken again (our picture as decoded"), @"the log says ours came over iPadOS's wallpaper");
    [gLog removeAllObjects];
    NSString *why = nil;
    c = TBackground(w, &why);
    check(c == (__bridge id)w.ours && !TLogHas(@"wallpaper taken"), @"opened again: ours, kept (not taken again)");
}
static void SClosedThumbs(void) {   // the switcher closed: a desktop kept drawn from its parts (a window landed on it: DMMSWDeskTakesWindow), then changes of ours
    TWorld w = TMake(YES, YES);
    UIView *d2 = TDrawn(w, w.root.bounds.size);
    check(d2.layer.contents == (__bridge id)w.ours, @"a desktop kept drawn from its parts: ours");
    [gLog removeAllObjects];
    CGImageRef dark = TDecodedAnew(w, 0.05, 0.05, 0.1);   // (KT's Dark appearance: the picture's dark version)
    check(d2.layer.contents == (__bridge id)dark, [NSString stringWithFormat:@"its dark version decoded with the switcher closed: the kept desktop picture shows it at once (is %@)", d2.layer.contents == (__bridge id)w.ours ? @"the picture before" : TWhich(w, d2.layer.contents)]);
    check(TLogHas(@"our Desktop Picture changed: 1 desktop thumbnail(s) or picture(s) drawn from their parts given the picture shown now (ours)"), @"the log says so");
    [gWPPlane removeFromSuperview]; gWPPlane = nil; DMMSWOurWallChanged();   // (None: DMWPRemove)
    check(d2.layer.contents == (__bridge id)w.apple, [NSString stringWithFormat:@"None with the switcher closed: the kept desktop picture shows iPadOS's wallpaper (is %@)", d2.layer.contents == (__bridge id)dark ? @"ours before" : TWhich(w, d2.layer.contents)]);
    gWPPlane = [[DMWPPlane alloc] initWithFrame:w.host.bounds]; [w.host addSubview:gWPPlane];
    gWPPlane.image = [UIImage imageWithCGImage:w.ours]; DMMSWOurWallChanged();   // (a picture chosen again, from None)
    check(d2.layer.contents == (__bridge id)w.ours, [NSString stringWithFormat:@"a picture chosen from None with the switcher closed: the kept desktop picture shows it (is %@)", TWhich(w, d2.layer.contents)]);
}
static void SClosedNoViews(void) {   // the switcher closed, no view showing the picture: nothing is taken for nothing; from None the copy of iPadOS's goes
    TWorld w = TMake(YES, YES);
    DMMSWWallLazy();
    [gLog removeAllObjects];
    TDecodedAnew(w, 0.2, 0.2, 0.25);
    check(gMSWWallContents == nil && !TLogHas(@"wallpaper taken"), @"another picture of ours, nothing showing it: the copy let go, nothing taken");
    [gWPPlane removeFromSuperview]; gWPPlane = nil; DMMSWOurWallChanged();   // (None)
    DMMSWWallLazy();   // (a desktop drawn from its parts for a slide, the switcher closed)
    check(gMSWWallContents == (__bridge id)w.apple, @"None: a desktop drawn from its parts takes iPadOS's wallpaper");
    gWPPlane = [[DMWPPlane alloc] initWithFrame:w.host.bounds]; [w.host addSubview:gWPPlane];
    gWPPlane.image = [UIImage imageWithCGImage:w.ours]; DMMSWOurWallChanged();   // (a picture chosen from None)
    DMMSWWallLazy();
    check(gMSWWallContents == (__bridge id)w.ours, [NSString stringWithFormat:@"a picture chosen from None: the next desktop drawn from its parts takes ours (is %@)", gMSWWallContents == (__bridge id)w.apple ? @"iPadOS's copy, kept" : TWhich(w, gMSWWallContents)]);
}
static void SOtherShape(void) {   // a desktop kept drawn from its parts in the screen's other shape (left before a turn), then another picture of ours
    TWorld w = TMake(YES, YES);
    UIView *open = TOpen(w); (void)open;
    CGSize s = w.root.bounds.size, o = CGSizeMake(s.height, s.width);
    UIView *d2 = TDrawn(w, o);
    CGImageRef other = TDecodedAnew(w, 0.2, 0.2, 0.25);
    CGRect f = d2.frame, box = d2.superview.bounds;
    check(d2.layer.contents == (__bridge id)other && CGRectContainsRect(CGRectInset(f, -1, -1), box),
          [NSString stringWithFormat:@"a desktop picture of the other shape: the new picture covers it (%@ in %@)", NSStringFromCGRect(f), NSStringFromCGRect(box)]);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        gLog = [NSMutableArray array];
        NSDictionary<NSString *, void (^)(void)> *all = @{ @"none": ^{ SNone(); }, @"ours": ^{ SOurs(); }, @"decoding": ^{ SDecoding(); }, @"changed": ^{ SChanged(); },
            @"lazy": ^{ SLazy(); }, @"fill": ^{ SFill(); }, @"fullscreen": ^{ SFullScreen(); }, @"off": ^{ SOff(); }, @"elsewhere": ^{ SElsewhere(); },
            @"pagetwo": ^{ SPageTwo(); }, @"lazychanged": ^{ SLazyChanged(); }, @"lazynone": ^{ SLazyNone(); }, @"openturn": ^{ SOpenTurn(); }, @"notours": ^{ SNotOurs(); },
            @"openchangedlate": ^{ SOpenChangedLate(); }, @"openthumbs": ^{ SOpenThumbs(); }, @"openfromnone": ^{ SOpenFromNone(); },
            @"closedthumbs": ^{ SClosedThumbs(); }, @"closednoviews": ^{ SClosedNoViews(); }, @"othershape": ^{ SOtherShape(); } };
        if (argc < 2 || !strcmp(argv[1], "list")) { for (NSString *k in [all.allKeys sortedArrayUsingSelector:@selector(compare:)]) printf("%s\n", k.UTF8String); return 0; }
        void (^s)(void) = all[@(argv[1])];
        if (!s) { printf("FAIL  no scenario %s\n", argv[1]); return 1; }
        s();
    }
    return gFails ? 1 : 0;
}
