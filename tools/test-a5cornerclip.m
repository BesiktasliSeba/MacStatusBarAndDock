// test-a5cornerclip.m -- see test-a5cornerclip.sh. Aerial 5's app corners (square on top, the window's 12 pt continuous corners at the bottom):
// since 1.8.8.4 the app's picture in Aerial's holder -- its scene host view, laid out at the holder's bounds -- is clipped to those corners by its
// own layer and draws the holder's fill, and the holder carries no mask (a mask made the render server draw the live app offscreen on every
// frame it changed). Only a holder with no picture yet keeps the mask. The real code, cut out of statusbar/StatusBar.x: DMStageInnerView and
// everything from kA5MaskKey to the end of DMA5SyncHostMaskFor (in a DEBUG build the [a5mask] trace too), and DMA5MaskStale (what the pass before
// every commit asks). Stand-ins: Aerial's stage (a UIView),
// its app holder (6 pt side margins, 13 pt top, 12 pt bottom, autoresizing; filled with the base colour, clipped, Aerial's 30 pt radius
// disarmed as theme 3b does), and a scene host view in it (laid out at the holder's bounds: it autoresizes) holding an opaque picture; the windows
// in a UIWindow whose layer is attached to +[CAContext localContext], so a commit really runs, and a post-commit handler reads what it carried.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ---- what the cut code needs ---------------------------------------------------------------------------------------------------------------
static NSMutableArray<NSString *> *gLog;
static void DMLog(NSString *s) { if (!gLog) gLog = [NSMutableArray array]; [gLog addObject:s]; }
static BOOL gCornerMask __attribute__((unused));   // (/tmp/msb-a5-cornermask)
#define DMTestFlag(path) (gCornerMask && !strcmp((path), "/tmp/msb-a5-cornermask"))
static BOOL gGeom = YES;   // (Aerial 5.x our engine, themed)
static BOOL DMA5MacGeometry(void) { return gGeom; }
static UIUserInterfaceStyle gStyle = UIUserInterfaceStyleDark;
static UIUserInterfaceStyle DMSystemInterfaceStyle(void) { return gStyle; }
static const CGFloat kMilkyWayCorner = 12.0;
static const void *kA5ChipHiddenKey = &kA5ChipHiddenKey, *kTMinimizedKey = &kTMinimizedKey;
static BOOL DMStageMinimized(UIView *stage) { return [objc_getAssociatedObject(stage, kTMinimizedKey) boolValue]; }
static NSString *DMStageBundle(UIView *stage) { return stage.accessibilityIdentifier ?: @"app"; }
static CGFloat DMA5StageShift(void) { return 11.0; }   // (24 - Aerial's 13 pt top inset)
static NSHashTable<UIView *> *gA5StageCache __attribute__((unused));   // (the a5corners trigger's list, DEBUG)
@interface NSObject (TCATransaction)
+ (void)addCommitHandler:(void (^)(void))block forPhase:(int)phase;
@end
#include "one-corners.inc"

static int gFails, gChecks;
static void Check(BOOL ok, NSString *what) { gChecks++; if (!ok) gFails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }

// ---- the stand-ins ---------------------------------------------------------------------------------------------------------------------------
@interface TSceneLayerHostContainer : UIView   // (its class name holds "SceneLayerHost", as _UISceneLayerHostContainerView's)
@end
@implementation TSceneLayerHostContainer
@end
static UIWindow *gWindow;
static UIColor *Base(void) { return gStyle == UIUserInterfaceStyleDark ? [UIColor blackColor] : [UIColor whiteColor]; }
static UIView *HolderOf(UIView *st) { return st.subviews.firstObject; }
static UIView *AddHost(UIView *st) {   // the app's picture: an opaque orange app filling the scene host view
    UIView *h = HolderOf(st);
    TSceneLayerHostContainer *host = [[TSceneLayerHostContainer alloc] initWithFrame:h.bounds];
    host.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UIView *app = [[UIView alloc] initWithFrame:host.bounds];
    app.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    app.backgroundColor = [UIColor colorWithRed:1.0 green:0.6 blue:0.1 alpha:1.0];
    [host addSubview:app]; [h addSubview:host];
    return host;
}
static UIView *MakeStage(CGRect f, NSString *name, BOOL withHost) {
    UIView *st = [[UIView alloc] initWithFrame:f];
    st.accessibilityIdentifier = name;
    UIView *h = [[UIView alloc] initWithFrame:CGRectMake(6, 13, f.size.width - 12, f.size.height - 25)];
    h.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    h.backgroundColor = Base(); h.clipsToBounds = YES; h.layer.cornerRadius = 30.0; h.layer.maskedCorners = 0;   // (Aerial's 30, disarmed: theme 3b)
    [st addSubview:h];
    if (withHost) AddHost(st);
    [gWindow addSubview:st];
    return st;
}
static void Reset(void) {
    for (UIView *v in [gWindow.subviews copy]) [v removeFromSuperview];
    gGeom = YES; gCornerMask = NO; gStyle = UIUserInterfaceStyleDark; [gLog removeAllObjects];
}
static UIView *HostOf(UIView *st) { for (UIView *v in HolderOf(st).subviews) if ([NSStringFromClass([v class]) containsString:@"SceneLayerHost"]) return v; return nil; }
static CALayer *OurMask(UIView *st) { CALayer *m = objc_getAssociatedObject(HolderOf(st), kA5MaskKey); return m && HolderOf(st).layer.mask == m ? m : nil; }
static BOOL ClipOK(CALayer *l) {
    return l.masksToBounds && l.maskedCorners == (kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner) && fabs(l.cornerRadius - 12.0) < 0.01 && [l.cornerCurve isEqualToString:kCACornerCurveContinuous];
}
static BOOL SameColor(CGColorRef a, UIColor *b) { return a && CGColorEqualToColor(a, b.CGColor); }
static NSString *Text(UIView *st) {
    UIView *h = HolderOf(st), *host = HostOf(st); CALayer *l = host.layer, *m = OurMask(st);
    return [NSString stringWithFormat:@"holder %@ fill %@ mask %@ | picture %@ r %.1f %@ corners %lu clips %d fill %@", NSStringFromCGSize(h.bounds.size), h.layer.backgroundColor ? @"yes" : @"none",
        m ? NSStringFromCGSize(m.bounds.size) : @"none", host ? NSStringFromCGRect(host.frame) : @"none", l.cornerRadius, l.cornerCurve, (unsigned long)l.maskedCorners, l.masksToBounds, l.backgroundColor ? @"yes" : @"none"];
}
// One commit: what happens in it, then what it carried (a post-commit handler)
typedef struct { BOOL mask, clip, holderFill, hostFill; CGRect host, holder; } TCommitted;
static TCommitted Commit(UIView *st, void (^during)(void)) {
    __block TCommitted c = {0};
    [CATransaction begin];
    if (during) during();
    [CATransaction addCommitHandler:^{
        UIView *host = HostOf(st);
        c.mask = OurMask(st) != nil; c.clip = host && ClipOK(host.layer); c.holderFill = HolderOf(st).layer.backgroundColor != NULL;
        c.hostFill = host && SameColor(host.layer.backgroundColor, Base()); c.host = host.frame; c.holder = HolderOf(st).bounds;
    } forPhase:2];
    [CATransaction commit]; [CATransaction flush];
    return c;
}
static BOOL Clipped(TCommitted c) { return !c.mask && c.clip && !c.holderFill && c.hostFill && CGRectEqualToRect(c.host, c.holder); }
// The bottom corners as drawn: the window rendered at 2x (renderInContext), the pixels of both corners
static NSData *CornerPixels(UIView *st) {
    CGSize sz = st.bounds.size; size_t w = (size_t)(sz.width * 2), hgt = (size_t)(sz.height * 2);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, w, hgt, 8, w * 4, cs, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);
    CGContextTranslateCTM(ctx, 0, hgt); CGContextScaleCTM(ctx, 2, -2);
    CGContextSetRGBFillColor(ctx, 0.2, 0.5, 0.3, 1); CGContextFillRect(ctx, CGRectMake(0, 0, sz.width, sz.height));   // (the desktop under the window)
    [st.layer renderInContext:ctx];
    const uint8_t *px = CGBitmapContextGetData(ctx);
    NSMutableData *out = [NSMutableData data];
    CGRect h = HolderOf(st).frame;
    for (int corner = 0; corner < 2; corner++) {
        int x0 = (int)((corner ? CGRectGetMaxX(h) - 16 : h.origin.x) * 2), y0 = (int)((CGRectGetMaxY(h) - 16) * 2);
        for (int y = y0; y < y0 + 36; y++) [out appendBytes:px + (size_t)y * w * 4 + (size_t)x0 * 4 length:36 * 4];
    }
    CGContextRelease(ctx);
    return out;
}
static int CornerPixelsOff(NSData *a) {   // pixels of the corner squares that show the desktop (outside the curve): proof that a corner is rounded at all
    const uint8_t *p = a.bytes; int n = 0;
    for (NSUInteger i = 0; i + 3 < a.length; i += 4) if (abs((int)p[i] - 51) < 3 && abs((int)p[i + 1] - 128) < 3 && abs((int)p[i + 2] - 77) < 3) n++;
    return n;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        gWindow = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 1194, 834)];
        id ctx = ((id (*)(id, SEL))objc_msgSend)(NSClassFromString(@"CAContext"), NSSelectorFromString(@"localContext"));
        ((void (*)(id, SEL, id))objc_msgSend)(ctx, NSSelectorFromString(@"setLayer:"), gWindow.layer);
        const CGRect kWin = {{125, 42}, {943, 668}};   // (the default window on a 1194 x 834 pt screen: holder 931 x 643)

        {   // C1: the app's picture is in: it is clipped and filled, the holder neither masked nor filled
            Reset();
            UIView *st = MakeStage(kWin, @"C1", YES);
            TCommitted c = Commit(st, ^{ DMA5SyncHostMask(st); });
            Check(Clipped(c), [NSString stringWithFormat:@"C1 a window with its app's picture: the picture clipped to the 12 pt continuous bottom corners and filled, no mask (%@)", Text(st)]);
        }
        {   // C2: the young holder (no picture yet): our mask, as before, at the holder's size; the holder keeps its fill
            Reset();
            UIView *st = MakeStage(kWin, @"C2", NO);
            Commit(st, ^{ DMA5SyncHostMaskFor(st, HolderOf(st)); });   // (a young window: DMA5FixYoungStage hands the early holder over)
            CALayer *m = OurMask(st);
            Check(m && CGSizeEqualToSize(m.bounds.size, HolderOf(st).bounds.size) && fabs(m.cornerRadius - 12.0) < 0.01 && [m.cornerCurve isEqualToString:kCACornerCurveContinuous]
                  && m.maskedCorners == (kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner) && SameColor(HolderOf(st).layer.backgroundColor, Base()),
                  [NSString stringWithFormat:@"C2 a new window with no app picture yet: our mask on the holder, its fill kept (%@)", Text(st)]);
            // C3: the picture comes: the same commit carries the clip, the fill moved, the mask off
            TCommitted c = Commit(st, ^{ AddHost(st); DMA5SyncHostMask(st); });
            Check(Clipped(c), [NSString stringWithFormat:@"C3 ... its app's picture comes: one commit carries the clip, the fill on the picture, the mask off (%@)", Text(st)]);
        }
        {   // C4: two pictures in one holder (a window brought back by a respring shows its app twice): 1.8.8.3's mask, the pictures as UIKit left them
            Reset();
            UIView *st = MakeStage(kWin, @"C4", YES); UIView *second = AddHost(st);
            Commit(st, ^{ DMA5SyncHostMask(st); });
            Check(OurMask(st) && !HostOf(st).layer.masksToBounds && !second.layer.masksToBounds && !HostOf(st).layer.backgroundColor && SameColor(HolderOf(st).layer.backgroundColor, Base()),
                  [NSString stringWithFormat:@"C4 two app pictures in one holder (their corners' edge would be drawn twice): the mask, as 1.8.8.3 (%@)", Text(st)]);
            // C13: a second picture comes into a clipped holder: the same commit carries the mask, the first picture as UIKit left it, the holder's fill
            Reset();
            UIView *s2 = MakeStage(kWin, @"C13", YES);
            Commit(s2, ^{ DMA5SyncHostMask(s2); });
            UIView *first = HostOf(s2);
            __block UIView *two = nil;
            TCommitted c = Commit(s2, ^{ two = AddHost(s2); DMA5SyncHostMask(s2); });
            Check(c.mask && !first.layer.masksToBounds && !first.layer.backgroundColor && c.holderFill && !two.layer.masksToBounds,
                  [NSString stringWithFormat:@"C13 a second picture comes into a clipped holder: the same commit carries the mask, the pictures unclipped, the holder's fill (%@)", Text(s2)]);
            // C14: ... it goes again: the clip again
            c = Commit(s2, ^{ [two removeFromSuperview]; DMA5SyncHostMask(s2); });
            Check(Clipped(c), @"C14 ... and gone again: the clip again in that commit");
        }
        {   // C15: a picture laid out off the holder's bounds (0.49 pt shorter, as a brought-back window's second picture at Fill): the mask
            Reset();
            UIView *st = MakeStage(CGRectMake(-6, 30, 1206, 735.49), @"C15", YES);
            HostOf(st).autoresizingMask = 0; CGRect f = HolderOf(st).bounds; f.size.height = floor(f.size.height); HostOf(st).frame = f;
            Commit(st, ^{ DMA5SyncHostMask(st); });
            Check(OurMask(st) && !HostOf(st).layer.masksToBounds, [NSString stringWithFormat:@"C15 one picture laid out %.2f pt shorter than its holder: the mask, as 1.8.8.3 (%@)", HolderOf(st).bounds.size.height - f.size.height, Text(st)]);
        }
        {   // C16: a corner resize's held picture in the holder: rounded with the clip, square again under the mask
            Reset();
            UIView *st = MakeStage(kWin, @"C16", YES);
            UIView *held = [[UIView alloc] initWithFrame:HolderOf(st).bounds]; held.accessibilityIdentifier = @"MSBResizePicture"; held.clipsToBounds = YES;
            [HolderOf(st) addSubview:held];
            Commit(st, ^{ DMA5SyncHostMask(st); });
            CALayer *l = held.layer;
            BOOL rounded = fabs(l.cornerRadius - 12.0) < 0.01 && [l.cornerCurve isEqualToString:kCACornerCurveContinuous] && l.maskedCorners == (kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner);
            Commit(st, ^{ AddHost(st); DMA5SyncHostMask(st); });
            Check(rounded && l.cornerRadius == 0 && OurMask(st), @"C16 a held picture in the holder: rounded as the app's picture with the clip, square under the mask (the mask rounds it)");
        }
        {   // C5: light and dark: the fill follows the appearance
            Reset(); gStyle = UIUserInterfaceStyleLight;
            UIView *st = MakeStage(kWin, @"C5", YES);
            Commit(st, ^{ DMA5SyncHostMask(st); });
            BOOL light = SameColor(HostOf(st).layer.backgroundColor, [UIColor whiteColor]);
            gStyle = UIUserInterfaceStyleDark;
            TCommitted c = Commit(st, ^{ DMA5SyncHostMask(st); });
            Check(light && Clipped(c) && SameColor(HostOf(st).layer.backgroundColor, [UIColor blackColor]), @"C5 light: the picture's fill white; dark: black at the next pass");
        }
        {   // C6: the holder filled again (Aerial, or our theme's step 4): taken off at the next pass, the picture keeps it
            Reset();
            UIView *st = MakeStage(kWin, @"C6", YES);
            Commit(st, ^{ DMA5SyncHostMask(st); });
            TCommitted c = Commit(st, ^{ HolderOf(st).backgroundColor = [UIColor whiteColor]; DMA5SyncHostMask(st); });
            Check(Clipped(c), [NSString stringWithFormat:@"C6 the holder filled again: no fill on it in the same commit (%@)", Text(st)]);
        }
        {   // C7: the window resized, animated and not: the clip is the picture's own bounds, the holder's, in the same commit, with no write of ours
            Reset();
            UIView *st = MakeStage(kWin, @"C7", YES);
            Commit(st, ^{ DMA5SyncHostMask(st); });
            int mut = gA5FrameMutations;
            TCommitted a = Commit(st, ^{ st.frame = CGRectMake(-6, 30, 1206, 736.4); });   // (Fill, no pass of ours in this commit)
            __block double holderAnim = 0, hostAnim = 0;
            TCommitted b = Commit(st, ^{ [UIView animateWithDuration:0.3 animations:^{ st.frame = CGRectMake(-6, 30, 606, 736.4); [st layoutIfNeeded]; }];
                for (NSString *k in HolderOf(st).layer.animationKeys) if ([k hasPrefix:@"bounds"]) holderAnim = [HolderOf(st).layer animationForKey:k].duration;
                for (NSString *k in HostOf(st).layer.animationKeys) if ([k hasPrefix:@"bounds"]) hostAnim = [HostOf(st).layer animationForKey:k].duration; });
            Check(Clipped(a) && Clipped(b) && gA5FrameMutations == mut && holderAnim > 0 && fabs(holderAnim - hostAnim) < 0.001,
                  [NSString stringWithFormat:@"C7 resized to Fill, then animated to a half (0.3 s): the clip committed at the holder's size each time, no write (%d), the picture's bounds animation the holder's (%.2f / %.2f s)",
                   gA5FrameMutations - mut, hostAnim, holderAnim]);
        }
        {   // C8: 100 quiet passes: nothing written
            Reset();
            UIView *a = MakeStage(kWin, @"a", YES), *b = MakeStage(CGRectMake(-6, 30, 606, 736.4), @"b", YES);
            Commit(a, ^{ DMA5SyncHostMask(a); DMA5SyncHostMask(b); });
            int mut = gA5FrameMutations;
            for (int i = 0; i < 100; i++) Commit(a, ^{ DMA5SyncHostMask(a); DMA5SyncHostMask(b); });
            Check(gA5FrameMutations == mut, [NSString stringWithFormat:@"C8 100 quiet passes over 2 windows: %d writes", gA5FrameMutations - mut]);
        }
        {   // C9: not Aerial 5 with our theme: nothing of ours
            Reset(); gGeom = NO;
            UIView *st = MakeStage(kWin, @"C9", YES);
            Commit(st, ^{ DMA5SyncHostMask(st); });
            CALayer *l = HostOf(st).layer;
            Check(!OurMask(st) && !l.masksToBounds && l.cornerRadius == 0 && SameColor(HolderOf(st).layer.backgroundColor, Base()), @"C9 not Aerial 5 (DMA5MacGeometry NO): no clip, no mask, the holder's fill as it was");
        }
        {   // C10: a window minimized before its first pass: left as it is (as the mask was)
            Reset();
            UIView *st = MakeStage(kWin, @"C10", YES);
            objc_setAssociatedObject(st, kTMinimizedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            Commit(st, ^{ DMA5SyncHostMask(st); });
            Check(!OurMask(st) && !HostOf(st).layer.masksToBounds, @"C10 minimized: nothing of ours put on it");
        }
        {   // C11: the same shape: the clip the real code puts on the picture against the mask it puts on a holder with no picture yet; and as drawn
            for (int dark = 0; dark < 2; dark++) {
                Reset(); gStyle = dark ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
                UIView *st = MakeStage(kWin, @"C11", NO);
                Commit(st, ^{ DMA5SyncHostMaskFor(st, HolderOf(st)); });
                CALayer *m = OurMask(st);
                CGFloat mr = m.cornerRadius; NSString *mc = m.cornerCurve; CACornerMask mk = m.maskedCorners; CGRect mf = m.frame;
                Commit(st, ^{ AddHost(st); DMA5SyncHostMask(st); });
                CALayer *l = HostOf(st).layer;
                BOOL same = m && fabs(l.cornerRadius - mr) < 0.001 && [l.cornerCurve isEqualToString:mc] && l.maskedCorners == mk && CGRectEqualToRect(HostOf(st).frame, mf) && l.masksToBounds;
                NSData *px = CornerPixels(st);
                // (the drawn corners: the desktop shows in both bottom corner squares, outside the curve)
                int off = CornerPixelsOff(px);
                Check(same && off > 40, [NSString stringWithFormat:@"C11 %@: the picture's clip is the mask's shape (radius %.1f %@, corners %lu, frame %@ against the mask's %.1f %@ %lu %@), drawn rounded (%d desktop pixels in the bottom corner squares)",
                      dark ? @"dark" : @"light", l.cornerRadius, l.cornerCurve, (unsigned long)l.maskedCorners, NSStringFromCGRect(HostOf(st).frame), mr, mc, (unsigned long)mk, NSStringFromCGRect(mf), off]);
            }
        }
        {   // C17: the pass before every commit sees a holder that has to change: a clipped one that gets a second picture, a new one, and one at rest
            Reset();
            UIView *st = MakeStage(kWin, @"C17", YES);
            BOOL fresh = DMA5MaskStale(st);
            Commit(st, ^{ DMA5SyncHostMask(st); });
            BOOL rest = DMA5MaskStale(st);
            AddHost(st);
            BOOL second = DMA5MaskStale(st);
            Commit(st, ^{ DMA5SyncHostMask(st); });
            Check(fresh && !rest && second && !DMA5MaskStale(st), [NSString stringWithFormat:@"C17 the commit pass's question: a new picture to clip %d, at rest %d, a second picture comes into a clipped holder %d, after its pass %d (want 1 0 1 0)",
                  fresh, rest, second, DMA5MaskStale(st)]);
        }
        {   // C12: the A/B switch (debug) gives 1.8.8.3's mask back and the picture UIKit's own values; a release has no such switch
            Reset();
            UIView *st = MakeStage(kWin, @"C12", YES);
            Commit(st, ^{ DMA5SyncHostMask(st); });
            gCornerMask = YES;
            TCommitted c = Commit(st, ^{ DMA5SyncHostMask(st); });
#if DEBUG
            CALayer *l = HostOf(st).layer;
            Check(c.mask && !l.masksToBounds && l.cornerRadius == 0 && l.maskedCorners == 15 && !l.backgroundColor && SameColor(HolderOf(st).layer.backgroundColor, Base()),
                  [NSString stringWithFormat:@"C12 (debug) /tmp/msb-a5-cornermask: the mask on the holder, its fill back, the picture as UIKit left it (%@)", Text(st)]);
            gCornerMask = NO;
            c = Commit(st, ^{ DMA5SyncHostMask(st); });
            Check(Clipped(c), @"C12 (debug) ... the switch gone: the clip again");
#else
            Check(Clipped(c), [NSString stringWithFormat:@"C12 (release) /tmp/msb-a5-cornermask is no switch in a release: the clip stays (%@)", Text(st)]);
#endif
        }
    }
    printf("%d checks, %d failed\n", gChecks, gFails);
    return gFails ? 1 : 0;
}
