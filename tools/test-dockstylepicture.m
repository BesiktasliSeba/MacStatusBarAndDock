// test-dockstylepicture.m -- Mac test of which view is an icon's picture for Glass Shelf's reflections (1.8.4 device pass, A12Z 18.5: no reflection
// under any app icon): the code as built. test-dockstyle.sh cuts DMStyleIsPicture and DMStylePicture out of dock/DockStyle.m into
// dockstylepicture-gen.h, and this file gives them stand-ins for UIKit and SpringBoard's icon views. 15 to 17 keep the picture among the icon view's
// own subviews; 18 puts it in a container (SBHTouchPassThroughView) under the icon view. The App Library icon (Launchpad's place) has no icon image
// view on any version: its picture is its own icon image view controller's view (17.5 and 18.5: the one Dock icon without a reflection).
// Also DMStylePictureDrawn and DMStylePictureSignature (with DMStyleShape): an icon image view still showing its placeholder grid, or with a new
// image not committed yet, is not drawn yet (18.5 after a respring with Glass Shelf on: every reflection was the grid for good); the picture's value
// is its layer's contents, the same however often it is asked (16.7.7's -displayedImage is a new object at each call: never the same value).
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/message.h>
#import <objc/runtime.h>
static int fails = 0, checks = 0;
static void Expect(BOOL ok, NSString *what) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }

// ---- UIKit's parts the lookup reads ---------------------------------------------------------------------------------------------------------------------
@interface DMTLayer : NSObject
@property (nonatomic, strong) id contents;
@property (nonatomic, strong) DMTLayer *presentationLayer;   // (nil until committed; then a copy holding the committed contents)
@property (nonatomic, strong) NSMutableArray<DMTLayer *> *sublayers;
@property (nonatomic) BOOL hidden;
@end
@implementation DMTLayer - (instancetype)init { if ((self = [super init])) _sublayers = [NSMutableArray array]; return self; } @end
static void Commit(DMTLayer *l) {   // (a transaction commits: every layer's presentation copy holds what its model holds)
    DMTLayer *p = [DMTLayer new]; p.contents = l.contents; l.presentationLayer = p;
    for (DMTLayer *s in l.sublayers) Commit(s);
}
#define CALayer DMTLayer
@interface UIView : NSObject
@property (nonatomic, strong) id window;
@property (nonatomic, strong) DMTLayer *layer;
@property (nonatomic, weak) UIView *superview;
@property (nonatomic, strong) NSMutableArray<UIView *> *kids;
@property (nonatomic) BOOL hidden;
@property (nonatomic) CGRect bounds;
- (NSArray<UIView *> *)subviews;
- (void)addSubview:(UIView *)v;
@end
@implementation UIView
- (instancetype)init { if ((self = [super init])) { _kids = [NSMutableArray array]; _bounds = CGRectMake(0, 0, 60, 60); _layer = [DMTLayer new]; } return self; }
- (NSArray<UIView *> *)subviews { return [_kids copy]; }
- (void)addSubview:(UIView *)v { [v.superview.kids removeObjectIdenticalTo:v]; [_kids addObject:v]; v.superview = self; }
@end
// ---- SpringBoard's icon views ----------------------------------------------------------------------------------------------------------------------------
@interface SBIconImageView : UIView { @public BOOL _real; id _shown; } - (id)displayedImage; @end
@implementation SBIconImageView - (id)displayedImage { return [NSString stringWithFormat:@"%@", _shown]; } @end   // (16.7.7's: a new image at each call)
static BOOL RealIMP(id self, SEL _cmd) { return ((SBIconImageView *)self)->_real; }   // (added as B16@0:8, its shape on the iPad)
static id OddRealIMP(id self, SEL _cmd) { return @"not a BOOL"; }
@interface SBOddIconImageView : SBIconImageView @end @implementation SBOddIconImageView @end
@interface SBFolderIconImageView : SBIconImageView @end @implementation SBFolderIconImageView @end
@interface SBIconLabelView : UIView @end @implementation SBIconLabelView @end
@interface SBHTouchPassThroughView : UIView @end @implementation SBHTouchPassThroughView @end
@interface UIViewController : NSObject @property (nonatomic, strong) UIView *ownView; @property (nonatomic) BOOL loaded; - (BOOL)isViewLoaded; - (UIView *)view; @end
@implementation UIViewController - (BOOL)isViewLoaded { return self.loaded; } - (UIView *)view { return self.ownView; } @end
@interface UIImageView : UIView @property (nonatomic, strong) id image; @end @implementation UIImageView @end
@interface SBIconView : UIView { @public id _picture; id _customIconImageViewController; } - (id)_iconImageView; @end
@implementation SBIconView - (id)_iconImageView { return _picture; } @end
@interface SBOddIconView : SBIconView @end @implementation SBOddIconView @end   // (its -_iconImageView of another shape, added below)
@interface DMFinderIconView : UIView @end @implementation DMFinderIconView @end
static BOOL OddAccessor(id self, SEL _cmd) { return YES; }

#include "../common/DockStyle.h"   // (MSBDReflectionAtLayout: what a layout does with a reflection -- the review of the fixes, M2)
@interface DMDockStyleView : UIView
@property (nonatomic) int look;
@property (nonatomic, strong) UIView *reflections;
@property (nonatomic, strong) NSMapTable<UIView *, UIView *> *reflectionOf;
@property (nonatomic) unsigned confirmGen;
@end
@implementation DMDockStyleView @end
// (Glass Shelf's layout as built, DMStyleSyncReflections -- the re-review's L3: its snapshot, its place and its confirm stood in for, counted)
@interface UIView (DMTSync) + (void)performWithoutAnimation:(void (^)(void))b; - (void)removeFromSuperview; - (BOOL)isDescendantOfView:(UIView *)v; @end
@implementation UIView (DMTSync)
+ (void)performWithoutAnimation:(void (^)(void))b { b(); }
- (void)removeFromSuperview { [self.superview.kids removeObjectIdenticalTo:self]; self.superview = nil; }
- (BOOL)isDescendantOfView:(UIView *)v { for (UIView *u = self; u; u = u.superview) if (u == v) return YES; return NO; }
@end
static int gTakes = 0, gConfirms = 0, gForced = 0, gPlaces = 0;
static BOOL gScreenOff = NO;
static UIView *DMStyleReflectionHolder(void) { UIView *h = [UIView new]; h.hidden = YES; return h; }
static BOOL DMStyleTakeRec(UIView *holder, UIView *pic, int afterUpdates) { (void)holder; (void)pic; gTakes++; if (afterUpdates) gForced++; return YES; }
// (the snapshot as built takes the holder and the picture; an older source passed whether it waits for the screen's updates too: counted, gForced)
#define DMStyleReflectionTake(holder, pic, ...) DMStyleTakeRec(holder, pic, sizeof((int[]){0, ##__VA_ARGS__}) / sizeof(int) > 1 ? ((int[]){0, ##__VA_ARGS__, 0})[1] : 0)
static BOOL DMStylePlaceReflection(DMDockStyleView *sv, UIView *icon, UIView *refl) { (void)sv; (void)icon; (void)refl; gPlaces++; return YES; }
static BOOL DMStyleScreenOff(DMDockStyleView *waiter) { (void)waiter; return gScreenOff; }
static void DMStyleConfirmSoon(DMDockStyleView *sv, int tries) { (void)sv; (void)tries; gConfirms++; }
#include "dockstylepicture-gen.h"

static SBIconImageView *Pic(CGFloat h) { SBIconImageView *p = [SBIconImageView new]; p.bounds = CGRectMake(0, 0, h, h); return p; }

int main(void) { @autoreleasepool {
    class_addMethod([SBOddIconView class], NSSelectorFromString(@"_iconImageView"), (IMP)OddAccessor, "B16@0:8");
    class_addMethod([SBIconImageView class], NSSelectorFromString(@"isShowingRealContentsImage"), (IMP)RealIMP, "B16@0:8");
    class_addMethod([SBOddIconImageView class], NSSelectorFromString(@"isShowingRealContentsImage"), (IMP)OddRealIMP, "@16@0:8");

    // 15 to 17: the picture is one of the icon view's own subviews.
    SBIconView *i17 = [SBIconView new];
    SBIconImageView *p17 = Pic(60);
    [i17 addSubview:[SBIconLabelView new]]; [i17 addSubview:p17]; i17->_picture = p17;
    Expect(DMStylePicture((id)i17) == (id)p17, @"15 to 17: the icon image view among the icon view's own subviews");
    i17->_picture = nil;
    Expect(DMStylePicture((id)i17) == (id)p17, @"  ... found there without asking the icon view");
    p17.hidden = YES;
    Expect(DMStylePicture((id)i17) == nil, @"  ... not while it is hidden");
    p17.hidden = NO; p17.bounds = CGRectMake(0, 0, 8, 8);
    Expect(DMStylePicture((id)i17) == nil, @"  ... nor when it is no picture's size (8 pt)");
    SBFolderIconImageView *fp = [SBFolderIconImageView new]; SBIconView *folder = [SBIconView new]; [folder addSubview:fp];
    Expect(DMStylePicture((id)folder) == (id)fp, @"  ... a folder's kind of icon image view counts");

    // 18: the picture lies in a container under the icon view (A12Z 18.5: SBHTouchPassThroughView).
    SBIconView *i18 = [SBIconView new];
    SBHTouchPassThroughView *box = [SBHTouchPassThroughView new];
    SBIconImageView *p18 = Pic(60);
    [i18 addSubview:box]; [box addSubview:p18]; i18->_picture = p18;
    Expect(DMStylePicture((id)i18) == (id)p18, @"18: the icon view's own image view, in a container under it");
    box.hidden = YES;
    Expect(DMStylePicture((id)i18) == nil, @"  ... not while the container is hidden (nothing on the way hidden)");
    box.hidden = NO; p18.hidden = YES;
    Expect(DMStylePicture((id)i18) == nil, @"  ... not while the picture is hidden");
    p18.hidden = NO; p18.bounds = CGRectMake(0, 0, 6, 6);
    Expect(DMStylePicture((id)i18) == nil, @"  ... nor when it is no picture's size");
    p18.bounds = CGRectMake(0, 0, 60, 60);
    UIView *elsewhere = [UIView new]; [elsewhere addSubview:p18];
    Expect(DMStylePicture((id)i18) == nil, @"  ... nor when it lies under another view (a drag's preview): only under the icon view");
    [box addSubview:p18];
    i18->_picture = [NSObject new];
    Expect(DMStylePicture((id)i18) == nil, @"  ... an answer that is no view is no picture");
    i18->_picture = [SBHTouchPassThroughView new];
    Expect(DMStylePicture((id)i18) == nil, @"  ... nor a view that is no icon image view");
    i18->_picture = p18;
    Expect(DMStylePicture((id)i18) == (id)p18, @"  ... and the picture again when it is back");

    // The accessor is asked only in its own shape (@16@0:8): another shape is not called.
    SBOddIconView *odd = [SBOddIconView new];
    SBHTouchPassThroughView *box2 = [SBHTouchPassThroughView new]; SBIconImageView *p2 = Pic(60);
    [odd addSubview:box2]; [box2 addSubview:p2]; odd->_picture = p2;
    Expect(DMStylePicture((id)odd) == nil, @"an icon view whose -_iconImageView has another shape: not asked, no picture");
    Expect(DMStylePicture((id)i18) == (id)p18, @"  ... and the next icon view of the usual class is asked again");

    // The App Library icon: no icon image view; its picture is its own icon image view controller's view (our Launchpad picture drawn in it).
    SBIconView *lib = [SBIconView new];
    SBHTouchPassThroughView *lbox = [SBHTouchPassThroughView new];
    UIView *lpic = [UIView new]; lpic.bounds = CGRectMake(0, 0, 68, 68);
    SBIconImageView *orig = Pic(68); orig.hidden = YES; UIImageView *ours = [UIImageView new];
    [lib addSubview:lbox]; [lbox addSubview:lpic]; [lpic addSubview:orig]; [lpic addSubview:ours];
    UIViewController *ctl = [UIViewController new]; ctl.ownView = lpic; ctl.loaded = YES; lib->_customIconImageViewController = ctl;
    Expect(DMStylePicture((id)lib) == lpic, @"the App Library icon (18's shape): its own icon image view controller's view");
    lib->_picture = orig;
    Expect(DMStylePicture((id)lib) == lpic, @"  ... also when its -_iconImageView answers a hidden one");
    ctl.loaded = NO;
    Expect(DMStylePicture((id)lib) == nil, @"  ... not before the controller's view is loaded");
    ctl.loaded = YES; lbox.hidden = YES;
    Expect(DMStylePicture((id)lib) == nil, @"  ... not while a view on the way is hidden");
    lbox.hidden = NO; lpic.hidden = YES;
    Expect(DMStylePicture((id)lib) == nil, @"  ... nor while the picture is");
    lpic.hidden = NO; [elsewhere addSubview:lpic];
    Expect(DMStylePicture((id)lib) == nil, @"  ... nor when the view lies under another view");
    [lbox addSubview:lpic];
    lib->_customIconImageViewController = [NSObject new];
    Expect(DMStylePicture((id)lib) == nil, @"  ... an ivar that holds no view controller is no picture");
    SBIconView *lib17 = [SBIconView new]; UIView *lpic17 = [UIView new]; lpic17.bounds = CGRectMake(0, 0, 60, 60); [lib17 addSubview:lpic17];
    UIViewController *ctl17 = [UIViewController new]; ctl17.ownView = lpic17; ctl17.loaded = YES; lib17->_customIconImageViewController = ctl17;
    Expect(DMStylePicture((id)lib17) == lpic17, @"  ... 15 to 17's shape: the controller's view right under the icon view");
    i18->_customIconImageViewController = ctl17;
    Expect(DMStylePicture((id)i18) == (id)p18, @"an app icon's own image view comes before any such controller");
    i18->_customIconImageViewController = nil;

    // Drawn: in a window, its layer committed once (a presentation copy) -- and an icon image view showing the icon's own image, not its placeholder.
    SBIconImageView *d = Pic(60); d.window = @"window"; Commit(d.layer); d->_real = YES;
    Expect(DMStylePictureDrawn((id)d), @"drawn: an icon image view in a window, committed, showing the icon's own image");
    d->_real = NO;
    Expect(!DMStylePictureDrawn((id)d), @"  ... not while it shows its placeholder (the grid while the image loads: 18.5 after a respring)");
    d->_real = YES; d.window = nil;
    Expect(!DMStylePictureDrawn((id)d), @"  ... nor out of a window");
    d.window = @"window"; d.layer.presentationLayer = nil;
    Expect(!DMStylePictureDrawn((id)d), @"  ... nor before its layer's first commit");
    // a new image on one of its layers that is not committed yet is not drawn (a snapshot shows the layer tree as committed)
    DMTLayer *cl = [DMTLayer new]; cl.contents = @"placeholder grid"; [d.layer.sublayers addObject:cl]; Commit(d.layer);
    Expect(DMStylePictureDrawn((id)d), @"  ... with its contents sublayer committed: drawn");
    cl.contents = [NSString stringWithFormat:@"%@", @"the app's own image"];
    Expect(!DMStylePictureDrawn((id)d), @"  ... not while the sublayer's new image waits for its commit");
    Commit(d.layer);
    Expect(DMStylePictureDrawn((id)d), @"  ... and drawn once it is committed");
    DMTLayer *fresh = [DMTLayer new]; fresh.contents = @"new layer"; [cl.sublayers addObject:fresh];
    Expect(!DMStylePictureDrawn((id)d), @"  ... a sublayer added and not committed yet: not drawn");
    fresh.hidden = YES;
    Expect(DMStylePictureDrawn((id)d), @"  ... unless it is hidden");
    fresh.hidden = NO; Commit(d.layer);
    DMTLayer *deep = [DMTLayer new]; [fresh.sublayers addObject:deep];
    Expect(DMStylePictureDrawn((id)d), @"  ... three levels down is not looked at");
    [fresh.sublayers removeAllObjects]; [cl.sublayers removeAllObjects]; [d.layer.sublayers removeAllObjects]; Commit(d.layer);
    UIView *plain = [UIView new]; plain.window = @"window"; Commit(plain.layer);
    Expect(DMStylePictureDrawn((id)plain), @"  ... a view without that getter (the App Library's picture, our own icons): drawn once committed, as before");
    SBOddIconImageView *oddv = [SBOddIconImageView new]; oddv.window = @"window"; Commit(oddv.layer); oddv->_real = NO;
    Expect(DMStylePictureDrawn((id)oddv), @"  ... a getter of another shape is not asked");
    // What it draws: an icon image view's image is its layer's contents (16 to 18); the value is the same however often it is asked.
    SBIconImageView *g = Pic(60); g->_shown = @"the app's own image"; g.layer.contents = @"placeholder grid";
    NSString *s1 = DMStylePictureSignature((id)g); g.layer.contents = [NSString stringWithFormat:@"%@", @"the app's own image"];
    NSString *s2 = DMStylePictureSignature((id)g);
    Expect(![s1 isEqualToString:s2], @"the picture's value changes when its layer's image does (the placeholder made way for the icon's image)");
    Expect([s2 isEqualToString:DMStylePictureSignature((id)g)], @"  ... and stays the same while nothing changes, though -displayedImage is a new object at each call (16.7.7)");
    g.bounds = CGRectMake(0, 0, 50, 50);
    Expect(![s2 isEqualToString:DMStylePictureSignature((id)g)], @"  ... a new size is a new value, as before");
    UIImageView *ownImg = [UIImageView new]; ownImg.image = @"Finder's picture"; DMFinderIconView *fi = [DMFinderIconView new]; [fi addSubview:ownImg];
    NSString *f1 = DMStylePictureSignature((id)fi); ownImg.image = [NSString stringWithFormat:@"%@", @"Finder's other picture"];
    Expect(![f1 isEqualToString:DMStylePictureSignature((id)fi)], @"  ... our own icons: their first image, as before");

    // Our own icons (Finder, Downloads, the Trash) are their picture.
    DMFinderIconView *finder = [DMFinderIconView new];
    Expect(DMStylePicture((id)finder) == (id)finder, @"our own icons are their picture");

    // The review of the fixes, M2: the App Library tile with SpringBoard's own image view before our Launchpad picture. The picture's value records the
    // first image of its views, so our grid and our rocket give the same value, and a layout alone kept the old reflection. Our item's change marks its
    // reflection itself (Dock.x DMDockItemPictureChanged -> DMDockStylePictureDirty): the next layout wants a new snapshot whatever the value says.
    UIView *tilePic = [UIView new]; UIImageView *sbOwn = [UIImageView new]; sbOwn.image = @"the App Library's own picture"; [tilePic addSubview:sbOwn];
    UIImageView *ourPic = [UIImageView new]; ourPic.image = @"our Launchpad grid"; [tilePic addSubview:ourPic];
    NSString *grid = DMStylePictureSignature((id)tilePic); ourPic.image = @"our Launchpad rocket";
    NSString *rocket = DMStylePictureSignature((id)tilePic);
    Expect([grid isEqualToString:rocket], @"M2: SpringBoard's own image view first: the picture's value is the same for our grid and our rocket (what the review found)");
    UIView *platter = [UIView new], *tile = [UIView new], *holder = [UIView new];
    DMDockStyleView *sv = [DMDockStyleView new]; sv.reflectionOf = [NSMapTable weakToStrongObjectsMapTable]; [sv.reflectionOf setObject:holder forKey:tile];
    objc_setAssociatedObject(platter, kStyleViewKey, sv, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(holder, kStylePicSigKey, grid, OBJC_ASSOCIATION_RETAIN_NONATOMIC);   // (the grid's reflection, recorded at its confirm)
    int act = MSBDReflectionAtLayout(1, [objc_getAssociatedObject(holder, kStylePicSigKey) isEqualToString:rocket], [objc_getAssociatedObject(holder, kStylePicWantKey) isEqualToString:rocket], 1);
    Expect(act == MSBDReflShow, @"  ... so a layout alone keeps the grid's reflection under the rocket");
    DMDockStylePictureDirty((id)platter, (id)tile);
    act = MSBDReflectionAtLayout(1, [objc_getAssociatedObject(holder, kStylePicSigKey) isEqualToString:rocket], [objc_getAssociatedObject(holder, kStylePicWantKey) isEqualToString:rocket], 1);
    Expect((act & MSBDReflWant) && (act & MSBDReflTakeNow), @"  ... the item's change marks its reflection: the next layout wants a new snapshot (shown at once, recorded at its confirm)");
    UIView *other = [UIView new], *otherHolder = [UIView new]; [sv.reflectionOf setObject:otherHolder forKey:other];
    objc_setAssociatedObject(otherHolder, kStylePicSigKey, @"Safari's", OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DMDockStylePictureDirty((id)platter, (id)tile); DMDockStylePictureDirty(nil, (id)tile); DMDockStylePictureDirty((id)platter, [UIView new]);
    Expect([objc_getAssociatedObject(otherHolder, kStylePicSigKey) isEqualToString:@"Safari's"], @"  ... only that item's: the other reflections keep theirs (no platter, or an icon with none: nothing)");

    // The re-review's L3: the same through Glass Shelf's layout as built (DMStyleSyncReflections). The App Library tile as 18 has it, SpringBoard's own
    // image view first in its picture and our Launchpad picture after it.
    SBIconView *syncTile = [SBIconView new]; SBHTouchPassThroughView *syncBox = [SBHTouchPassThroughView new];
    UIView *syncPic = [UIView new]; syncPic.bounds = CGRectMake(0, 0, 68, 68); syncPic.window = @"window";
    UIImageView *syncOwn = [UIImageView new]; syncOwn.image = @"the App Library's own picture"; UIImageView *lpic3 = [UIImageView new]; lpic3.image = @"our Launchpad grid";
    [syncTile addSubview:syncBox]; [syncBox addSubview:syncPic]; [syncPic addSubview:syncOwn]; [syncPic addSubview:lpic3];
    UIViewController *syncCtl = [UIViewController new]; syncCtl.ownView = syncPic; syncCtl.loaded = YES; syncTile->_customIconImageViewController = syncCtl;
    Commit(syncPic.layer);
    UIView *syncPlatter = [UIView new]; DMDockStyleView *syncSv = [DMDockStyleView new];
    syncSv.look = MSBDDockLookShelf; syncSv.reflections = [UIView new]; syncSv.reflectionOf = [NSMapTable weakToStrongObjectsMapTable];
    objc_setAssociatedObject(syncPlatter, kStyleViewKey, syncSv, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    gTakes = gConfirms = 0;
    DMStyleSyncReflections(syncPlatter, syncSv, @[syncTile]);
    UIView *syncHolder = [syncSv.reflectionOf objectForKey:syncTile];
    Expect(syncHolder && syncHolder.superview == syncSv.reflections && gTakes == 1 && gConfirms == 1, @"L3: Glass Shelf's first layout as built: the App Library tile's reflection taken, its confirm asked");
    objc_setAssociatedObject(syncHolder, kStylePicSigKey, objc_getAssociatedObject(syncHolder, kStylePicWantKey), OBJC_ASSOCIATION_RETAIN_NONATOMIC);   // (its confirm records it,
    objc_setAssociatedObject(syncHolder, kStylePicWantKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);                                               //  as DMStyleConfirmReflections does)
    lpic3.image = @"our Launchpad rocket";   // (Settings > Dock: the classic rocket)
    gTakes = gConfirms = 0;
    DMStyleSyncReflections(syncPlatter, syncSv, @[syncTile]);
    Expect(gTakes == 0 && gConfirms == 0, @"  ... our rocket in place of the grid: a layout alone takes nothing again (what the review found: the grid's reflection stayed)");
    DMDockStylePictureDirty((id)syncPlatter, (id)syncTile);
    DMStyleSyncReflections(syncPlatter, syncSv, @[syncTile]);
    Expect(gTakes == 1 && gConfirms == 1 && [objc_getAssociatedObject(syncHolder, kStylePicWantKey) isEqualToString:DMStylePictureSignature(syncPic)],
           @"  ... marked by the item's change (Dock.x DMDockItemPictureChanged), the next layout takes it again and asks its confirm to record it");

    // The regression's black band on the TV (A12Z, 9 Nov): the confirm as built, and what follows it. It records from a snapshot of the screen as it is: none forces the
    // screen's updates. What was committed a moment before is caught by taking the reflection again, twice, with its place set.
    [syncPlatter addSubview:syncSv]; [syncPlatter addSubview:syncTile]; syncPlatter.window = @"window";
    objc_setAssociatedObject(syncHolder, kStylePicSigKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(syncHolder, kStylePicWantKey, DMStylePictureSignature(syncPic), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    gTakes = gForced = gPlaces = 0;
    DMStyleConfirmReflections(syncSv, 0);
    NSString *recorded = objc_getAssociatedObject(syncHolder, kStylePicSigKey);
    Expect(gTakes == 1 && recorded && [recorded isEqualToString:DMStylePictureSignature(syncPic)], @"the confirm as built: the reflection taken and its value recorded");
    Expect(gForced == 0, @"  ... from a snapshot of the screen as it is: none forces the screen's updates (the black band on the TV)");
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.25, false);
    Expect(gTakes == 3 && gForced == 0 && gPlaces >= 2, [NSString stringWithFormat:@"  ... and taken again twice a moment later, its place set, for what reaches the screen a few frames after its commit (%d taken, %d forced)", gTakes, gForced]);
    objc_setAssociatedObject(syncHolder, kStylePicWantKey, DMStylePictureSignature(syncPic), OBJC_ASSOCIATION_RETAIN_NONATOMIC); objc_setAssociatedObject(syncHolder, kStylePicSigKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    gTakes = 0; DMStyleConfirmReflections(syncSv, 0);
    syncPic.layer.contents = @"another picture";   // (changed meanwhile: its next layout's)
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.4, false);
    Expect(gTakes == 1, @"  ... not when the picture changed meanwhile: that is its next layout's");
    objc_setAssociatedObject(syncHolder, kStylePicWantKey, DMStylePictureSignature(syncPic), OBJC_ASSOCIATION_RETAIN_NONATOMIC); objc_setAssociatedObject(syncHolder, kStylePicSigKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    Commit(syncPic.layer); gTakes = 0; DMStyleConfirmReflections(syncSv, 0);
    gScreenOff = YES;
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.4, false);
    Expect(gTakes == 1, @"  ... nor while the screen is asleep (a blank snapshot)");
    gScreenOff = NO;

    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
} }
