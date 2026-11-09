// DockStyle.m -- Settings > Dock > Dock Style (MacStatusBar&Dock 1.8.4 item 3): the Dock as Mac OS X drew it before today's -- Glass Shelf (10.5 to
// 10.9, a flat dark panel at a side as in those years) and Frosted (10.10 to 10.15) --, drawn by us (common/DockStyle.h, plain CoreGraphics, rendered
// to PNG by tools/test-dockstyle.sh). Default leaves iPadOS's own Dock exactly as it is.
//
// Our look is one view at the back of the Dock's platter (SBFloatingDockPlatterView, under its icon lists), laid out with the platter (Dock.x's
// -layoutSubviews hook); iPadOS's own background and shadow (the platter's -backgroundView and -shadowView, read in their shapes) are hidden while it
// shows and given back with Default. The icons, their lists, the dividers, Finder, Downloads, the Trash, magnification, the side positions, the
// menus, Edit Home Screen and the launch bounce are Apple's and ours as ever: nothing of them is moved. The shelf's reflections are snapshots of the
// icons' pictures (taken again when a picture changed, confirmed a run-loop turn later), flipped and faded in the shelf, following the
// magnification frame by frame; the open apps' lights are the running dots (RunningIndicator.m, FinderIcon.m) drawn as each style's light
// (DMDockStyleDot).
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <notify.h>
#import "DMLog.h"
#include "../common/DockStyle.h"
#include "../common/DockSide.h"
#define DM_FEATURE_MARK(name) do { static const char *const dmFeatureMark = "msbd-feature:" name; __asm__ volatile("" :: "r"(dmFeatureMark)); } while (0)   // (release-build feature marker, see statusbar/StatusBar.x)

extern int DMDockStylePlatterSide(UIView *platter);   // (Dock.x: the side this platter's Dock stands on -- in the turned view; 0 the bottom or a TV's Dock)
@interface UIWindow (DMDockStylePrivate)
+ (NSArray *)allWindowsIncludingInternalWindows:(BOOL)internal onlyVisibleWindows:(BOOL)visible;
@end
extern int MSBDDockSideIconTurnSide(UIView *icon);   // (Dock.x: the side an icon's content is turned for, 0 none)
static int gDockStyle = MSBDDockStyleDefault;   // the choice (Dock.x DMLoadPrefs: DMDockStyleSetChoice)
static const void *kStyleViewKey = &kStyleViewKey, *kStyleHidKey = &kStyleHidKey;

static BOOL DMStyleShape(id o, const char *sel, const char *enc) {
    Method m = o ? class_getInstanceMethod(object_getClass(o), sel_registerName(sel)) : NULL;
    const char *e = m ? method_getTypeEncoding(m) : NULL;
    return e && !strcmp(e, enc);
}
static UIView *DMStyleGet(id o, const char *sel) {   // (a view getter of the platter, in its shape only)
    if (!DMStyleShape(o, sel, "@16@0:8")) return nil;
    id v = ((id (*)(id, SEL))objc_msgSend)(o, sel_registerName(sel));
    return [v isKindOfClass:[UIView class]] ? v : nil;
}
static int DMStyleLookFor(UIView *platter) { return MSBDDockStyleLook(gDockStyle, DMDockStylePlatterSide(platter)); }

// ---- the look's views ----
@interface DMDockStyleDraw : UIView
@property (nonatomic) int look;
@property (nonatomic) double picture;
@end
@implementation DMDockStyleDraw
- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGRect b = self.bounds;
    BOOL dark = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    if (self.look == MSBDDockLookShelf) MSBDDrawGlassShelf(c, b, MSBDShelfGeometry(b, self.picture));
    else if (self.look == MSBDDockLookDarkPanel) MSBDDrawDarkPanel(c, b);
    else if (self.look == MSBDDockLookFrosted) MSBDDrawFrostedTint(c, b, dark);
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous { [super traitCollectionDidChange:previous]; [self setNeedsDisplay]; }   // (Frosted's tint: light or dark)
@end
@interface DMDockStyleView : UIView
@property (nonatomic) int look;
@property (nonatomic) double picture;
@property (nonatomic) MSBDShelf shelf;
@property (nonatomic, strong) UIVisualEffectView *blur;        // (Frosted)
@property (nonatomic, strong) DMDockStyleDraw *draw;
@property (nonatomic, strong) UIView *reflections;             // (Glass Shelf: masked to the shelf's top)
@property (nonatomic, strong) NSMapTable<UIView *, UIView *> *reflectionOf;   // icon view -> its reflection's holder
@property (nonatomic) unsigned confirmGen;                     // (the reflections' confirm last asked: an older one does nothing)
@end
@implementation DMDockStyleView
- (instancetype)init {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    self.userInteractionEnabled = NO;
    _draw = [DMDockStyleDraw new]; _draw.backgroundColor = [UIColor clearColor]; _draw.contentMode = UIViewContentModeRedraw; _draw.userInteractionEnabled = NO;
    _reflections = [UIView new]; _reflections.userInteractionEnabled = NO;
    _reflectionOf = [NSMapTable weakToStrongObjectsMapTable];
    [self addSubview:_draw]; [self addSubview:_reflections];
    return self;
}
@end

// The icons' picture height as drawn (the first app icon's picture view in the platter's space, its transforms included), for the shelf's depth.
static NSArray<UIView *> *DMStyleIcons(UIView *platter) {
    NSMutableArray *out = [NSMutableArray array];
    Class ic = objc_getClass("SBIconView");
    Class own[3] = { objc_getClass("DMFinderIconView"), objc_getClass("DMDownloadsIconView"), objc_getClass("DMTrashIconView") };
    NSMutableArray<UIView *> *todo = [NSMutableArray arrayWithArray:platter.subviews];
    while (todo.count) {
        UIView *v = todo.lastObject; [todo removeLastObject];
        if ([v isKindOfClass:[DMDockStyleView class]]) continue;
        BOOL mine = NO;
        for (int i = 0; i < 3; i++) if (own[i] && [v isKindOfClass:own[i]]) mine = YES;
        if ((ic && [v isKindOfClass:ic]) || mine) { if (!v.hidden && v.alpha > 0.01) [out addObject:v]; continue; }
        [todo addObjectsFromArray:v.subviews];
    }
    return out;
}
// An icon's picture view. An app icon's: SpringBoard's icon image view (SBIconImageView, or a folder's, the Clock's, the Calendar's), shown and of a
// picture's size. 15 to 17 have it among the icon view's own subviews. 18 puts it in a container under the icon view (an SBHTouchPassThroughView):
// there it is the icon view's own -_iconImageView (in that shape only), taken while it lies under the icon view with nothing on the way hidden (1.8.4
// device pass, A12Z 18.5: no reflection under any app icon). The App Library icon (Launchpad's place in the Dock) has no icon image view on any
// version: its picture is the view of its own icon image view controller (_customIconImageViewController, a plain UIView -- our Launchpad picture
// is drawn in it, Launchpad.m; 17.5 and 18.5: the only Dock icon without a reflection). Our own icons (Finder, Downloads, Trash) are their picture.
static BOOL DMStyleIsPicture(UIView *v) {
    return v && !v.hidden && v.bounds.size.height > 8.0 && [NSStringFromClass([v class]) rangeOfString:@"IconImageView"].location != NSNotFound;
}
static BOOL DMStyleShownUnder(id v, UIView *icon) {   // (a view of a picture's size under the icon view, nothing on the way hidden)
    if (![v isKindOfClass:[UIView class]] || ((UIView *)v).bounds.size.height <= 8.0) return NO;
    UIView *up = v;
    while (up && up != icon) { if (up.hidden) return NO; up = up.superview; }
    return up == icon;
}
static UIView *DMStylePicture(UIView *icon) {
    if (![icon isKindOfClass:objc_getClass("SBIconView")]) return icon;
    for (UIView *sub in icon.subviews) if (DMStyleIsPicture(sub)) return sub;
    static Class asked = Nil; static BOOL has = NO; static Ivar custom = NULL;   // (the accessor's shape and the controller's ivar, asked once per class)
    SEL get = NSSelectorFromString(@"_iconImageView");
    if (object_getClass(icon) != asked) {
        Method m = class_getInstanceMethod(object_getClass(icon), get);
        const char *e = m ? method_getTypeEncoding(m) : NULL;
        has = e && !strcmp(e, "@16@0:8");
        Ivar iv = class_getInstanceVariable(object_getClass(icon), "_customIconImageViewController");
        const char *t = iv ? ivar_getTypeEncoding(iv) : NULL;
        custom = t && t[0] == '@' ? iv : NULL;
        asked = object_getClass(icon);
    }
    id pic = has ? ((id (*)(id, SEL))objc_msgSend)(icon, get) : nil;
    if ([pic isKindOfClass:[UIView class]] && DMStyleIsPicture(pic) && DMStyleShownUnder(pic, icon)) return pic;
    id ctl = custom ? object_getIvar(icon, custom) : nil;
    if ([ctl isKindOfClass:[UIViewController class]] && [(UIViewController *)ctl isViewLoaded] && DMStyleShownUnder([(UIViewController *)ctl view], icon))
        return [(UIViewController *)ctl view];
    return nil;
}
static double DMStylePictureHeight(UIView *platter, NSArray<UIView *> *icons) {
    for (UIView *icon in icons) {
        UIView *p = DMStylePicture(icon);
        if (!p || ![icon isKindOfClass:objc_getClass("SBIconView")]) continue;
        CGRect r = [p convertRect:p.bounds toView:platter];
        if (r.size.height > 8.0 && isfinite(r.size.height)) return r.size.height;
    }
    return platter.bounds.size.height * 0.7;
}

// ---- the reflections (Glass Shelf) ----
// One holder per icon while the icon is in the Dock (its fade, its place), holding a snapshot of the icon's picture: taken again only for a new or
// changed picture (review 1.8.4 L10), its check value recorded only by the confirm a turn of the main run loop later, from a snapshot of a picture
// that has been drawn; a picture missing at one layout keeps its holder, hidden (review 1.8.4 P2-M1: the rules are common/DockStyle.h's).
static const void *kStylePicSigKey = &kStylePicSigKey;     // (on a holder: the picture its snapshot shows -- recorded only by the confirm)
static const void *kStylePicWantKey = &kStylePicWantKey;   // (on a holder: the picture a snapshot is wanted of, until its confirm)
// A layer and the layers under it (two levels) as committed: each has its presentation copy, holding the contents its model holds. A snapshot shows
// the layer tree as committed; a picture whose new image is set but not committed yet is still drawn with the one before.
static BOOL DMStyleLayerSettled(CALayer *l, int depth) {
    CALayer *p = l.presentationLayer;
    if (!p || p.contents != l.contents) return NO;
    if (depth > 0) for (CALayer *sub in l.sublayers) if (!sub.hidden && !DMStyleLayerSettled(sub, depth - 1)) return NO;
    return YES;
}
static BOOL DMStylePictureCommitted(UIView *pic) {   // (as it shows: in a window, its layer committed -- it has a presentation copy then -- and nothing of it pending)
    return pic.window != nil && pic.layer.presentationLayer != nil && DMStyleLayerSettled(pic.layer, 2);
}
static BOOL DMStylePictureDrawn(UIView *pic) {   // (drawn: committed, and showing the icon's own image)
    // (an icon image view that still shows its placeholder -- the grid drawn while the icon's own image loads -- is not drawn yet, nor one whose
    //  image came in and is not committed yet: on 18.5, after a respring with Glass Shelf on, every app icon's reflection was that grid for good.
    //  The getter is asked only in its own shape. A folder's or an installing app's picture may answer no for good: the confirm's last round
    //  records it as it shows -- MSBDReflectionAtConfirm, review 1.8.4 P3-L2.)
    if (DMStyleShape(pic, "isShowingRealContentsImage", "B16@0:8") && !((BOOL (*)(id, SEL))objc_msgSend)(pic, sel_registerName("isShowingRealContentsImage"))) return NO;
    return DMStylePictureCommitted(pic);
}
#if DEBUG
static NSString *DMStylePicDebug(UIView *icon, UIView *pic) {   // (debug: an icon's picture as the reflections see it)
    id ic = nil, bid = nil; @try { ic = [icon valueForKey:@"icon"]; bid = [ic valueForKey:@"applicationBundleID"]; } @catch (id e) {}
    BOOL real = DMStyleShape(pic, "isShowingRealContentsImage", "B16@0:8") ? ((BOOL (*)(id, SEL))objc_msgSend)(pic, sel_registerName("isShowingRealContentsImage")) : -1;
    CALayer *cl = DMStyleShape(pic, "contentsLayer", "@16@0:8") ? ((id (*)(id, SEL))objc_msgSend)(pic, sel_registerName("contentsLayer")) : nil;
    return [NSString stringWithFormat:@"%@ (%@): real %d settled %d, layer %p/%p, contents layer %p: %p/%p, sublayers %lu", bid ?: NSStringFromClass([icon class]),
            NSStringFromClass([pic class]), real, pic ? DMStyleLayerSettled(pic.layer, 2) : 0, (__bridge void *)pic.layer.contents, (__bridge void *)pic.layer.presentationLayer.contents,
            cl, [cl isKindOfClass:[CALayer class]] ? (__bridge void *)cl.contents : NULL, [cl isKindOfClass:[CALayer class]] ? (__bridge void *)cl.presentationLayer.contents : NULL,
            (unsigned long)pic.layer.sublayers.count];
}
#endif
static UIView *DMStyleReflectionHolder(void) {
    UIView *holder = [UIView new];
    holder.userInteractionEnabled = NO;
    holder.alpha = MSBD_REFLECTION_ALPHA;
    holder.hidden = YES;   // (until it holds a snapshot, placed)
    CAGradientLayer *fade = [CAGradientLayer layer];   // (strongest at the picture's bottom, gone at the lip)
    fade.colors = @[(id)[UIColor colorWithWhite:0 alpha:1].CGColor, (id)[UIColor colorWithWhite:0 alpha:0].CGColor];
    holder.layer.mask = fade;
    return holder;
}
// A snapshot of the picture into the holder, the one before out; NO: none to be had. Always of the screen as it is: asked to wait for the screen's updates
// (-snapshotViewAfterScreenUpdates:YES, a confirm's first one until 1.8.4's regression) it put a black band on the TV for one frame -- x 0..1024, at the
// bottom, 76 pt tall, about a second after a Dock picture changed -- and forced an update of the screen. What it can miss, a change committed a moment ago and
// not on the screen yet (18.5 right after a respring: the placeholder grid the icon's image had just replaced), is caught by taking it again: DMStyleRetake.
static BOOL DMStyleReflectionTake(UIView *holder, UIView *pic) {
    UIView *snap = [pic snapshotViewAfterScreenUpdates:NO];
    if (!snap) return NO;
    for (UIView *old in [holder.subviews copy]) [old removeFromSuperview];
    [holder addSubview:snap];
    return YES;
}
// Which picture a reflection shows: the picture's view, its size and what it draws (its layer's contents -- an icon image view's image, 16 to 18;
// our own icons: their first image's picture) -- taken again only when one of these changed (review 1.8.4 L10). (Not -[SBIconImageView
// displayedImage]: 16.7.7 gives a new image object at each call, so the value never matched and every layout took every snapshot again.)
static NSString *DMStylePictureSignature(UIView *pic) {
    const void *img = NULL;
    if (![pic isKindOfClass:objc_getClass("SBIconView")]) {
        NSMutableArray<UIView *> *todo = [NSMutableArray arrayWithObject:pic];
        for (NSUInteger i = 0; i < todo.count && i < 12 && !img; i++) {
            UIView *v = todo[i];
            if ([v isKindOfClass:[UIImageView class]] && ((UIImageView *)v).image) img = (__bridge const void *)((UIImageView *)v).image;
            [todo addObjectsFromArray:v.subviews];
        }
    }
    return [NSString stringWithFormat:@"%p|%.1fx%.1f|%p|%p", pic, pic.bounds.size.width, pic.bounds.size.height, (__bridge const void *)pic.layer.contents, img];
}
// One reflection where its picture is now (its frame in the platter, with the magnification's scale): flipped below the picture, squashed to the
// room down to the lip, faded. NO: no room (hidden).
static BOOL DMStylePlaceReflection(DMDockStyleView *sv, UIView *icon, UIView *refl) {
    UIView *pic = DMStylePicture(icon);
    if (!pic || !refl || !refl.subviews.count) { refl.hidden = YES; return NO; }   // (no picture now, or no snapshot yet)
    CGRect r = [pic convertRect:pic.bounds toView:sv];
    CGRect f = MSBDReflectionFrame(r, sv.shelf);
    if (f.size.height <= 0 || !isfinite(r.origin.x)) { refl.hidden = YES; return NO; }
    refl.hidden = NO;
    refl.frame = f;
    // (the picture flipped -- its bottom row at the reflection's top -- at the size it shows now, its lower half squashed into the room down
    //  to the lip: in the snapshot's own units y -> -sy * y + k * h, so its bottom row lands on 0 and its top row on k * h, clipped at f's height)
    UIView *snap = refl.subviews.firstObject;
    CGSize bz = snap.bounds.size;
    CGFloat k = f.size.height / MAX(1.0, r.size.height * 0.5);
    CGFloat sx = r.size.width / MAX(1.0, bz.width), sy = k * r.size.height / MAX(1.0, bz.height);
    snap.layer.anchorPoint = CGPointMake(0.5, 0.0);
    snap.layer.position = CGPointMake(f.size.width / 2.0, 0);
    snap.transform = CGAffineTransformMake(sx, 0, 0, -sy, 0, k * r.size.height);
    refl.clipsToBounds = YES;
    refl.layer.mask.frame = refl.bounds;
    return YES;
}
// The confirm (MSBDReflectionAtConfirm): on the main run loop's next turn after a layout wanted a snapshot or hid a reflection -- that layout's
// commit has drawn the icons then --, and again a little later while one waits. A wanted snapshot of a picture that shows and has been drawn is
// taken again and its check value recorded; a hidden reflection whose picture is back shows again. The last one asked runs (confirmGen).
static void DMStyleConfirmReflections(DMDockStyleView *sv, int tries);
static void DMStyleConfirmSoon(DMDockStyleView *sv, int tries) {
    unsigned gen = ++sv.confirmGen;
    __weak DMDockStyleView *weakSv = sv;
    dispatch_block_t run = ^{ DMDockStyleView *s = weakSv; if (s && s.confirmGen == gen) DMStyleConfirmReflections(s, tries); };
    if (tries <= 0) dispatch_async(dispatch_get_main_queue(), run);
    else dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MSBDReflectionRetryDelay(tries) * NSEC_PER_SEC)), dispatch_get_main_queue(), run);
}
// The screen asleep: no snapshot is taken of it (one taken then may be blank, and would be recorded for good: an App Store update changing an
// icon overnight). The confirm waits for the screen to come on and runs then (review 1.8.4 P3-L1).
static int gStyleBlankToken = 0;
static NSHashTable<DMDockStyleView *> *gStyleAtWake;
static BOOL DMStyleScreenOff(DMDockStyleView *waiter) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gStyleAtWake = [NSHashTable weakObjectsHashTable];
        notify_register_dispatch("com.apple.springboard.hasBlankedScreen", &gStyleBlankToken, dispatch_get_main_queue(), ^(int t) {
            uint64_t blank = 0;
            notify_get_state(t, &blank);
            if (blank) return;
            NSArray<DMDockStyleView *> *waiting = gStyleAtWake.allObjects;
            [gStyleAtWake removeAllObjects];
            for (DMDockStyleView *v in waiting) DMStyleConfirmSoon(v, 0);
        });
    });
    uint64_t blank = 0;
    if (gStyleBlankToken) notify_get_state(gStyleBlankToken, &blank);
    if (blank && waiter) [gStyleAtWake addObject:waiter];
    return blank != 0;
}
// A reflection just recorded, taken again a moment later, twice (at +0.25 s and +1 s): its snapshot is of the screen as it was, and what was committed a moment
// before reaches the screen a few frames later. The same picture, the same way (no update forced), its place set again; one that changed meanwhile, or does not
// show, is its next layout's. Never while the screen is asleep (a blank snapshot).
static void DMStyleRetake(DMDockStyleView *sv, NSArray<UIView *> *icons, double delay, double thenDelay) {
    if (!icons.count || delay <= 0) return;
    __weak DMDockStyleView *weakSv = sv;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        DMDockStyleView *s = weakSv;
        UIView *platter = s.superview;
        if (!s || s.look != MSBDDockLookShelf || !platter.window || DMStyleScreenOff(nil)) return;
        [UIView performWithoutAnimation:^{
            for (UIView *icon in icons) {
                UIView *holder = [s.reflectionOf objectForKey:icon];
                UIView *pic = holder && [icon isDescendantOfView:platter] ? DMStylePicture(icon) : nil;
                NSString *rec = holder ? objc_getAssociatedObject(holder, kStylePicSigKey) : nil;
                if (!pic || !rec || ![rec isEqualToString:DMStylePictureSignature(pic)] || !DMStylePictureDrawn(pic)) continue;
                if (DMStyleReflectionTake(holder, pic)) DMStylePlaceReflection(s, icon, holder);
            }
        }];
        DMStyleRetake(s, icons, thenDelay, 0);
    });
}
static void DMStyleConfirmReflections(DMDockStyleView *sv, int tries) {
    UIView *platter = sv.superview;
    if (sv.look != MSBDDockLookShelf || !platter.window) return;
    if (DMStyleScreenOff(sv)) return;   // (asleep: again when the screen comes on)
    __block BOOL waiting = NO;
    NSMutableArray<UIView *> *recorded = [NSMutableArray array];
    [UIView performWithoutAnimation:^{
        for (UIView *icon in [[sv.reflectionOf keyEnumerator] allObjects]) {
            UIView *holder = [sv.reflectionOf objectForKey:icon];
            UIView *pic = [icon isDescendantOfView:platter] ? DMStylePicture(icon) : nil;
            if (objc_getAssociatedObject(holder, kStylePicWantKey)) {
                int act = MSBDReflectionAtConfirm(pic != nil, pic && DMStylePictureDrawn(pic), tries, pic && DMStylePictureCommitted(pic));
                if (act == MSBDReflRecord && !DMStyleReflectionTake(holder, pic)) act = MSBDReflectionAtConfirm(0, 0, tries, 0);   // (no snapshot to be had)
                if (act == MSBDReflRecord) {   // (recorded from this snapshot, of a drawn picture)
                    [recorded addObject:icon];
#if DEBUG
                    if (access("/tmp/dockmag-debug", F_OK) == 0) DMLog([NSString stringWithFormat:@"[dockstyle] reflection recorded at round %d: %@", tries, DMStylePicDebug(icon, pic)]);
#endif
                    objc_setAssociatedObject(holder, kStylePicSigKey, DMStylePictureSignature(pic), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    objc_setAssociatedObject(holder, kStylePicWantKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                } else if (act == MSBDReflGiveUp) objc_setAssociatedObject(holder, kStylePicWantKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);   // (the next layout wants it again)
                else waiting = YES;
            } else if (!pic) waiting = YES;   // (its picture not back yet)
            if (pic) DMStylePlaceReflection(sv, icon, holder);
            else holder.hidden = YES;
        }
    }];
    if (waiting && tries + 1 < MSBD_REFLECTION_TRIES) DMStyleConfirmSoon(sv, tries + 1);
    DMStyleRetake(sv, recorded, 0.25, 0.75);
}
// At a layout (MSBDReflectionAtLayout): each icon keeps its holder -- put back in the shelf if it left it --, a picture missing now keeps it hidden,
// a new or changed picture is wanted (its snapshot now if it has been drawn, recorded by the confirm); icons that went lose theirs.
static void DMStyleSyncReflections(UIView *platter, DMDockStyleView *sv, NSArray<UIView *> *icons) {
    if (sv.look != MSBDDockLookShelf) {
        if (sv.reflections.subviews.count) { for (UIView *v in sv.reflections.subviews) [v removeFromSuperview]; [sv.reflectionOf removeAllObjects]; }
        sv.confirmGen++;   // (a confirm under way does nothing)
        return;
    }
    NSMutableSet *kept = [NSMutableSet set];
    NSMutableSet<UIView *> *iconSet = [NSMutableSet setWithArray:icons];
    __block BOOL confirm = NO;
    [UIView performWithoutAnimation:^{
        for (UIView *icon in icons) {
            UIView *pic = DMStylePicture(icon);
            UIView *holder = [sv.reflectionOf objectForKey:icon];
            if (!holder && !pic) continue;
            if (!holder) { holder = DMStyleReflectionHolder(); [sv.reflectionOf setObject:holder forKey:icon]; }
            if (holder.superview != sv.reflections) [sv.reflections addSubview:holder];   // (reused: back in the shelf)
            [kept addObject:holder];
            NSString *sig = pic ? DMStylePictureSignature(pic) : nil;
            BOOL recordedSame = [objc_getAssociatedObject(holder, kStylePicSigKey) isEqualToString:sig], wantedSame = [objc_getAssociatedObject(holder, kStylePicWantKey) isEqualToString:sig];
            BOOL drawn = pic && !recordedSame && !wantedSame && DMStylePictureDrawn(pic);   // (asked only of a new or changed picture)
            int act = MSBDReflectionAtLayout(pic != nil, recordedSame, wantedSame, drawn);
            if (act & MSBDReflHide) { holder.hidden = YES; confirm = YES; continue; }   // (kept: it shows again with its picture)
            if (act & MSBDReflWant) {
                objc_setAssociatedObject(holder, kStylePicSigKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);   // (nothing recorded until the confirm)
                objc_setAssociatedObject(holder, kStylePicWantKey, sig, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                if (act & MSBDReflTakeNow) DMStyleReflectionTake(holder, pic);   // (shown at once)
                confirm = YES;
            }
            DMStylePlaceReflection(sv, icon, holder);
        }
    }];
    for (UIView *icon in [[sv.reflectionOf keyEnumerator] allObjects]) if (![iconSet containsObject:icon]) [sv.reflectionOf removeObjectForKey:icon];
    for (UIView *v in [sv.reflections.subviews copy]) if (![kept containsObject:v]) [v removeFromSuperview];
    if (confirm) DMStyleConfirmSoon(sv, 0);
}
// At a magnification frame: only the reflections there are, moved (the icons are the map's own, kept by the last layout -- no walk of the views).
static void DMStylePlaceReflections(DMDockStyleView *sv) {
    [UIView performWithoutAnimation:^{
        for (UIView *icon in sv.reflectionOf) DMStylePlaceReflection(sv, icon, [sv.reflectionOf objectForKey:icon]);
    }];
}

// ---- the platter: our look in, iPadOS's background and shadow out (and back) ----
// They are hidden by an empty mask of ours on their layer -- never by their alpha, which stays iPadOS's own: an alpha read during one of its fades
// and put back with Default could leave the Dock without its material (review 1.8.4 L3). The mask they had (normally none) is kept and is what
// Default gives back; one iPadOS sets meanwhile is kept instead, and ours goes over it again.
static const void *kStyleMaskKey = &kStyleMaskKey;   // (on an Apple view: our empty mask while it is hidden)
static void DMStyleHideApple(UIView *platter, BOOL hide) {
    NSArray *views = @[DMStyleGet(platter, "backgroundView") ?: [NSNull null], DMStyleGet(platter, "shadowView") ?: [NSNull null]];
    NSMutableDictionary *was = objc_getAssociatedObject(platter, kStyleHidKey);   // (the view, not retained -> its own mask, NSNull for none)
    for (id v in views) {
        if (v == [NSNull null]) continue;
        UIView *view = v;
        NSValue *key = [NSValue valueWithNonretainedObject:view];
        CALayer *ours = objc_getAssociatedObject(view, kStyleMaskKey);
        if (hide) {
            if (!ours) { ours = [CALayer layer]; objc_setAssociatedObject(view, kStyleMaskKey, ours, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }   // (empty: nothing shows through it)
            if (view.layer.mask == ours) continue;
            if (!was) { was = [NSMutableDictionary dictionary]; objc_setAssociatedObject(platter, kStyleHidKey, was, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
            was[key] = view.layer.mask ?: [NSNull null];   // (its own, or the one iPadOS set since)
            view.layer.mask = ours;
        } else if (was[key]) {
            id own = was[key];
            if (view.layer.mask == ours) view.layer.mask = own == [NSNull null] ? nil : own;
            objc_setAssociatedObject(view, kStyleMaskKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    // (all given back: the record goes -- also any entry of a view iPadOS replaced meanwhile --, so Default asks nothing again)
    if (!hide && was) objc_setAssociatedObject(platter, kStyleHidKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
void DMDockStyleApply(UIView *platter) {
    // (Default, and nothing of ours ever put on this platter: nothing is asked, every layout -- review 1.8.4 L2)
    if (gDockStyle == MSBDDockStyleDefault && !objc_getAssociatedObject(platter, kStyleViewKey) && !objc_getAssociatedObject(platter, kStyleHidKey)) return;
    if (!platter.window) return;
    int look = DMStyleLookFor(platter);
    DMDockStyleView *sv = objc_getAssociatedObject(platter, kStyleViewKey);
    if (!MSBDDockStyleHidesApple(look)) {   // (Default: everything iPadOS's again)
        if (sv) { [sv removeFromSuperview]; objc_setAssociatedObject(platter, kStyleViewKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        DMStyleHideApple(platter, NO);
        return;
    }
    DM_FEATURE_MARK("dock-style");
    if (!sv) { sv = [DMDockStyleView new]; objc_setAssociatedObject(platter, kStyleViewKey, sv, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    if (sv.superview != platter) [platter insertSubview:sv atIndex:0];
    else if (platter.subviews.firstObject != sv) [platter sendSubviewToBack:sv];
    DMStyleHideApple(platter, YES);
    NSArray<UIView *> *icons = DMStyleIcons(platter);
    double picture = DMStylePictureHeight(platter, icons);
    BOOL changed = !CGRectEqualToRect(sv.frame, platter.bounds) || sv.look != look || fabs(sv.picture - picture) > 0.5;
    [UIView performWithoutAnimation:^{ sv.frame = platter.bounds; sv.draw.frame = sv.bounds; }];
    if (changed) {
        sv.look = look; sv.picture = picture; sv.draw.look = look; sv.draw.picture = picture;
        sv.shelf = MSBDShelfGeometry(sv.bounds, picture);
        [sv.draw setNeedsDisplay];
        if (look == MSBDDockLookFrosted) {
            if (!sv.blur) { sv.blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]]; sv.blur.userInteractionEnabled = NO; sv.blur.clipsToBounds = YES; sv.blur.layer.cornerCurve = kCACornerCurveContinuous; }
            if (sv.blur.superview != sv) [sv insertSubview:sv.blur atIndex:0];
            sv.blur.frame = sv.bounds; sv.blur.layer.cornerRadius = MSBD_FROSTED_CORNER;
        } else [sv.blur removeFromSuperview];
        CAShapeLayer *mask = [CAShapeLayer layer];   // (the reflections show on the shelf's top only)
        CGPathRef top = MSBDShelfTopPath(sv.bounds, sv.shelf);
        mask.path = top; CGPathRelease(top);
        sv.reflections.frame = sv.bounds; sv.reflections.layer.mask = mask;
        DMLog([NSString stringWithFormat:@"[dockstyle] look %d on a platter %@ (pictures %.1f pt)", look, NSStringFromCGRect(platter.bounds), picture]);
    }
    DMStyleSyncReflections(platter, sv, icons);
}
// Every magnification frame (Dock.x dm_apply): the reflections follow the icons' scale.
void DMDockStyleFollow(UIView *platter) {
    DMDockStyleView *sv = platter ? objc_getAssociatedObject(platter, kStyleViewKey) : nil;
    if (!sv || sv.look != MSBDDockLookShelf) return;
    DMStylePlaceReflections(sv);   // (review 1.8.4 L10: no walk of the Dock's views, no snapshot, per frame)
}

// ---- the open apps' lights: the running dot as each style draws it ----
static UIImage *DMStyleGlowImage(BOOL blue) {
    static UIImage *img[2];
    if (!img[blue]) {
        CGSize z = blue ? CGSizeMake(64, 38) : CGSizeMake(44, 44);
        img[blue] = [[[UIGraphicsImageRenderer alloc] initWithSize:z] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            MSBDDrawGlowDot(ctx.CGContext, CGRectMake(0, 0, z.width, z.height), blue);
        }];
    }
    return img[blue];
}
// dot: an icon's running dot as RunningIndicator.m / FinderIcon.m just placed it (d: its size); the icon's Dock look decides how it shows.
void DMDockStyleDot(UIView *dot, UIView *iconView, CGFloat d) {
    if (!dot || !iconView) return;
    UIView *platter = nil;
    for (UIView *v = iconView.superview; v; v = v.superview) if ([v isKindOfClass:objc_getClass("SBFloatingDockPlatterView")]) { platter = v; break; }
    DMDockStyleView *sv = platter ? objc_getAssociatedObject(platter, kStyleViewKey) : nil;
    int look = sv.superview ? sv.look : MSBDDockLookDefault;
    if (look == MSBDDockLookShelf || look == MSBDDockLookDarkPanel) {
        BOOL blue = look == MSBDDockLookShelf;
        CGRect f = dot.frame;
        if (blue) {
            CGFloat lip = [sv convertPoint:CGPointMake(0, sv.shelf.front) toView:iconView].y;   // (the lip, in the icon's own space)
            CGSize z = MSBDGlassLightSize(d);
            f = CGRectMake(round(iconView.bounds.size.width / 2.0 - z.width / 2.0), round(lip - z.height / 2.0 + 0.5), z.width, z.height);
            // (15/16: nothing of an icon view shows past its bottom -- RunningIndicator.m's dot, iPad 2: the light stays on the shelf above the lip then)
            if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion < 17 && CGRectGetMaxY(f) > iconView.bounds.size.height) f.origin.y = MAX(0.0, iconView.bounds.size.height - z.height);
        } else {
            CGSize z = MSBDPanelLightSize(d);
            f = CGRectMake(round(CGRectGetMidX(dot.frame) - z.width / 2.0), round(CGRectGetMidY(dot.frame) - z.height / 2.0), z.width, z.height);
        }
        dot.frame = f;
        dot.backgroundColor = [UIColor clearColor];
        dot.layer.cornerRadius = 0;
        id want = (__bridge id)DMStyleGlowImage(blue).CGImage;
        if (dot.layer.contents != want) { dot.layer.contents = want; dot.layer.contentsGravity = kCAGravityResize; }
        return;
    }
    if (dot.layer.contents) { dot.layer.contents = nil; dot.backgroundColor = [UIColor labelColor]; }   // (Default and Frosted: today's dot)
}

// Settings changed: every Dock's platter takes the look now (its own layout may not come by itself).
extern void DMRunningIndicatorResyncAll(void);   // (RunningIndicator.m: every app icon's dot placed and drawn again)
#if DEBUG
// debug ("stylepics" in /tmp/dockmag-escape): every Dock icon's picture as Glass Shelf's reflections see it -- shown, real, settled (its layers as
// committed), its contents and the committed ones, and whether the value recorded for its reflection is the picture's now.
void DMDockStylePicsDebug(void) {
    Class pc = objc_getClass("SBFloatingDockPlatterView");
    for (UIWindow *w in [UIWindow allWindowsIncludingInternalWindows:YES onlyVisibleWindows:NO]) {
        NSMutableArray<UIView *> *todo = [NSMutableArray arrayWithObject:w];
        while (todo.count) {
            UIView *v = todo.lastObject; [todo removeLastObject];
            if (pc && [v isKindOfClass:pc]) {
                DMDockStyleView *sv = objc_getAssociatedObject(v, kStyleViewKey);
                NSMutableString *o = [NSMutableString stringWithFormat:@"[stylepics] platter %p look %d", v, sv ? sv.look : -1];
                for (UIView *icon in DMStyleIcons(v)) {
                    UIView *pic = DMStylePicture(icon), *holder = [sv.reflectionOf objectForKey:icon];
                    NSString *rec = holder ? objc_getAssociatedObject(holder, kStylePicSigKey) : nil;
                    [o appendFormat:@"\n  %@; holder %d hidden %d, recorded %@", pic ? DMStylePicDebug(icon, pic) : [NSString stringWithFormat:@"%@: no picture", NSStringFromClass([icon class])],
                     holder != nil, holder.hidden, !rec ? @"none" : [rec isEqualToString:DMStylePictureSignature(pic)] ? @"= now" : @"OLD"];
                }
                DMLog(o);
                continue;
            }
            [todo addObjectsFromArray:v.subviews];
        }
    }
}
#endif
void DMDockStyleRefreshAll(void) {
    Class pc = objc_getClass("SBFloatingDockPlatterView"), finder = objc_getClass("DMFinderIconView");
    if (!pc) return;
    NSMutableArray<UIView *> *finders = [NSMutableArray array];
    for (UIWindow *w in [UIWindow allWindowsIncludingInternalWindows:YES onlyVisibleWindows:NO]) {
        NSMutableArray<UIView *> *todo = [NSMutableArray arrayWithObject:w];
        while (todo.count) {
            UIView *v = todo.lastObject; [todo removeLastObject];
            if ([v isKindOfClass:pc]) {
                DMDockStyleApply(v);
                for (UIView *sub in v.subviews) if (finder && [sub isKindOfClass:finder]) [finders addObject:sub];
                continue;
            }
            [todo addObjectsFromArray:v.subviews];
        }
    }
    // (the running dots take the new look now -- the apps' and Finder's --, not at the next change of the running apps: review 1.8.4 L4)
    DMRunningIndicatorResyncAll();
    SEL updateDot = NSSelectorFromString(@"updateDot");
    for (UIView *f in finders) if ([f respondsToSelector:updateDot]) ((void (*)(id, SEL))objc_msgSend)(f, updateDot);
}
// Glass Shelf's reflections on that platter now (Dock.x DMDockItemPictureChanged: one of our items' new picture lays the platter out again for them).
BOOL DMDockStyleReflects(UIView *platter) {
    DMDockStyleView *sv = platter ? objc_getAssociatedObject(platter, kStyleViewKey) : nil;
    return sv && sv.look == MSBDDockLookShelf;
}
// One of our items has a new picture (Dock.x DMDockItemPictureChanged): its reflection is taken again at the platter's next layout whatever the
// picture's value says -- the value records the first image of the picture's views, and on the App Library tile SpringBoard's own image view can come
// before our Launchpad picture, the value then the same for the grid and the rocket (the review of the fixes, M2). Nothing recorded or wanted: the
// layout wants a snapshot of it (MSBDReflectionAtLayout), the confirm records it.
void DMDockStylePictureDirty(UIView *platter, UIView *icon) {
    DMDockStyleView *sv = platter ? objc_getAssociatedObject(platter, kStyleViewKey) : nil;
    UIView *holder = icon ? [sv.reflectionOf objectForKey:icon] : nil;
    if (!holder) return;
    objc_setAssociatedObject(holder, kStylePicSigKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(holder, kStylePicWantKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
void DMDockStyleSetChoice(int style) {
    if (style == gDockStyle) return;
    gDockStyle = style;
    DMLog([NSString stringWithFormat:@"[dockstyle] Dock Style: %s", style == MSBDDockStyleGlass ? "Glass Shelf" : style == MSBDDockStyleFrosted ? "Frosted" : "Default"]);
}
