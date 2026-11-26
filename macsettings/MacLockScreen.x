// MacLockScreen.x -- Mac Lock Screen (F49, 1.8.9; plans/design-mac-lock-screen.md rev 1, KT 25 Nov ~00:50 / ~02:20 / ~02:35 / ~03:00): a light,
// part-by-part style layer over the iPad's own Lock Screen (iPadOS's Cover Sheet). Off by default (new features ship off).
//
// Five parts, each its own setting (common/MacLockScreen.h): Clock Style (Mac / iPadOS / None), Background (Wallpaper / Blurred Wallpaper /
// Desktop Picture), Mac-Style Cards, Picture and Name, Wi-Fi and Battery. A part at its iPadOS value installs no hook (its Logos group is never
// %init'd) and changes nothing; the master off = no hook at all (the %ctor only listens for the switch). Everything that works on the Lock
// Screen stays iPadOS's own, in place and in function: we never call an unlock, dismiss or present API, never fake an iPadOS callback, never
// write a lock state, a wallpaper, a poster or a setting, and every view of ours takes no touch.
//
// Coexistence is ours (design 3.4, common/MacLockCoexist.h): before a part installs its hooks and again at every
// appearance, it checks generically whether another modification already owns it (where the code of the classes that draw it lives, the views
// in its containers, a whole face of another's); a part found owned stands down alone (iPadOS's values given back, its hooks pass straight
// through) and Settings shows "Handled by another tweak" for it (the state file: part labels only, never a name).
//
// Nothing at rest (no work while the Lock Screen is away): our views are made when the Cover Sheet appears and dropped when it goes; no timer of ours
// (one startup retry while CoverSheet's classes load, as LockStatusBar.x); the blurred picture is made once off the main thread and kept as a
// small PNG; the battery observers exist only while the face shows.
//
// Rev 2 (design section 12; KT 25 Nov ~11:45 on 18.5): a full macOS lock screen by default on every iPadOS (the Mac clock, the blurred
// wallpaper, the macOS user block with iPadOS's own unlock hint as a plain line under the name (12.4a: macOS at rest), Mac cards); exactly one
// status drawing at the top right (the pair only where none is drawn because WE hid it: common/LockBarHide.h); the face formed at the Cover
// Sheet's first layout in its window; a bounded poster-switcher state; the picture and name only for a lock (iPadOS's read or a lock seen for this appearance).
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <notify.h>
#include <sys/stat.h>
#include <os/log.h>
#include "../common/MacLockScreen.h"
#include "../common/MacLockCoexist.h"
#include "../common/MacCardLook.h"
#include "../common/OtherTweaks.h"
#include "../common/DesktopWallpaper.h"
#include "../common/BannerStyle.h"   // (3.3: with Destra's banners in force, Mac-Style Cards leaves the cells to it)   // (Background "Desktop Picture": the picture Settings > Desktop chose, read as SpringBoard's desktop reads it)
#define LBH_REASON @"com.besiktasliseba.maclockscreen"   // (Wi-Fi and Battery's own reason in SpringBoard's set, Q27)
#include "../common/LockBarHide.h"
#include "../common/HookTypes.h"

#define DM_FEATURE_MARK(name) do { static const char *const dmFeatureMark = "msbd-feature:" name; __asm__ volatile("" :: "r"(dmFeatureMark)); } while (0)   // (release-build feature marker, see statusbar/StatusBar.x)

#if DEBUG
static void MLLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void MLLog(NSString *fmt, ...) {
    if (access("/tmp/macstatusbar-debug", F_OK) != 0) return;
    va_list a; va_start(a, fmt); NSString *s = [[NSString alloc] initWithFormat:fmt arguments:a]; va_end(a);
    FILE *f = fopen("/tmp/macstatusbar.log", "a");
    if (!f) return;
    NSDateFormatter *df = [NSDateFormatter new]; df.dateFormat = @"HH:mm:ss.SSS";
    fprintf(f, "%s [maclock] %s\n", [df stringFromDate:[NSDate date]].UTF8String, s.UTF8String); fclose(f);
}
#else
#define MLLog(...) do { if (0) { (void)[NSString stringWithFormat:__VA_ARGS__]; } } while (0)   // (release: no log; the arguments still count as used)
#endif

@interface SBLockScreenManager : NSObject
+ (instancetype)sharedInstance;
@end
@interface CSCoverSheetViewController : UIViewController
@end
@interface CSCoverSheetView : UIView
@end
@interface SBFLockScreenDateView : UIView
- (NSDate *)date;
@end
@interface CSProminentDisplayView : UIView
- (NSDate *)displayDate;
@end
@interface PLPlatterView : UIView
@end
@interface CSMainPageView : UIView
@end

// ---------------------------------------------------------------------------------------------------------------- state
static MLSettings gS;
static int gOS;
static MLMachine gM;
static MLTable gTable;
static MLPartWatch gWatch[kMLPartCount];
static int gWhy[kMLPartCount];            // this appearance's verdict per part (kMLWhyNone = ours to draw)
static int gInstallWhy[kMLPartCount];     // found owned when its hooks were to go in: never installed in this SpringBoard life
static BOOL gInstalled[kMLPartCount], gCoreInstalled;
static BOOL gChecked;                     // (PART(p) is NO until this appearance's check has run: 2.7)
static BOOL gNoStill;                     // no still picture was readable on this iPadOS (Settings offers Wallpaper only then)
static BOOL gStillRead;                   // a still with a picture in it became a backdrop in this SpringBoard life (17/18 offer Blurred only then)
static BOOL gFaceUp;                      // the Cover Sheet is in a window on the iPad's own screen and no poster switcher is coming
static MLSwitcherState gSw;               // (17/18) the poster switcher's bounded state (12.2 (2))
static BOOL gAppearing;                   // an appearance is in progress (from -viewWillAppear: or a switch-on while shown, to its disappearance)
static BOOL gPairShows;                   // this pass's outcome of 12.1's rule: our Wi-Fi and Battery draws
static __weak CSCoverSheetViewController *gCS;
static NSDictionary *gLastState;
static NSHashTable *gCards;               // platters that carry our card look (weak)

static id MLIvar(id o, const char *name) {
    if (!o) return nil;
    Ivar v = class_getInstanceVariable(object_getClass(o), name);
    const char *t = v ? ivar_getTypeEncoding(v) : NULL;
    return t && t[0] == '@' ? object_getIvar(o, v) : nil;
}
static BOOL MLBoolCall(id o, SEL s, BOOL dflt) {
    if (!o || ![o respondsToSelector:s]) return dflt;
    Method m = class_getInstanceMethod(object_getClass(o), s);
    const char *e = m ? method_getTypeEncoding(m) : NULL;
    if (!e || (e[0] != 'B' && e[0] != 'c') || method_getNumberOfArguments(m) != 2) return dflt;
    return ((BOOL (*)(id, SEL))objc_msgSend)(o, s);
}
static id MLObjCall(id o, SEL s) {
    if (!o || ![o respondsToSelector:s]) return nil;
    Method m = object_isClass(o) ? class_getClassMethod((Class)o, s) : class_getInstanceMethod(object_getClass(o), s);
    const char *e = m ? method_getTypeEncoding(m) : NULL;
    if (!e || e[0] != '@' || method_getNumberOfArguments(m) != 2) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(o, s);
}
// the argument at index i (0 = self) is an integer (the only calls with an argument this part makes on private classes)
static BOOL MLArgInt(Method m, unsigned i) {
    if (!m || method_getNumberOfArguments(m) <= i) return NO;
    char t[16]; method_getArgumentType(m, i, t, sizeof(t));
    return t[0] == 'q' || t[0] == 'Q' || t[0] == 'l' || t[0] == 'L' || t[0] == 'i' || t[0] == 'I';
}
static id MLPresentationManager(void) { return MLObjCall(objc_getClass("SBCoverSheetPresentationManager"), @selector(sharedInstance)); }
// What draws iPadOS's own clock here (common/MacLockScreen.h MLClockPathOf, 1.8.9 pass: two clocks on 16): the prominent display on 16-18, SBFLockScreenDateView's
// labels on 15. Read once CoverSheet's classes are in (CoverSheet links CoverSheetKit): a class never comes or goes in a SpringBoard life.
static int MLClockPath(void) {
    static int path = -1;
    if (path < 0 && objc_getClass("CSCoverSheetView")) path = MLClockPathOf(objc_getClass("CSProminentDisplayView"), objc_getClass("CSProminentTimeView"), objc_getClass("SBFLockScreenDateView"));
    return path < 0 ? kMLClockPathNone : path;
}
static BOOL MLProminentClock(void) { return MLClockPath() == kMLClockPathProminent; }

// PART(p) (2.7): the face is up, the part is not at its iPadOS value, its hooks are in, this appearance's check ran and found nobody else there.
static BOOL MLDestraInForce(void) {   // (SpringBoard's word on the banner style in force, statusbar/BannerStyleSB.h)
    int t = 0; uint64_t st = 0;
    if (notify_register_check(kMSBDBannerStyleState, &t) != NOTIFY_STATUS_OK) return NO;
    notify_get_state(t, &st); notify_cancel(t);
    return MSBDBannerStateInForce(st) == kMSBDBannerDestra;
}
static BOOL gDestra;
static BOOL gDepthDown;   // (17/18) the depth effect could not be hidden in this appearance: the backdrop stands down (12.7)
static BOOL MLPart(int p) {
    if (p == kMLPartCards && gDestra) return NO;
    if (p == kMLPartBackground && gDepthDown) return NO;
    return gFaceUp && gChecked && MLPartWanted(&gS, p) && gInstalled[p] && !gInstallWhy[p] && gWhy[p] == kMLWhyNone;
}

// ---------------------------------------------------------------------------------------------------------------- settings
static void MLReadPrefs(void) {
    CFPreferencesAppSynchronize(CFSTR(MLS_DOMAIN));
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSString *k in @[ @"enabled", @"clockStyle", @"background", @"cards", @"showUser", @"statusPair", @"picture", @"name" ]) {
        id v = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)k, CFSTR(MLS_DOMAIN)));
        if (v) d[k] = v;
    }
    gS = MLSettingsFrom(d, gOS);
}
static NSString *MLDesktopPicturePath(void);
// (Background "Desktop Picture" with no picture set any more: the version's own default, 2.4)
static void MLEffectiveBackground(void) {
    if (gS.background == kMLBackDesktop && !MLDesktopPicturePath()) gS.background = MLDefaultBackground(gOS);
}

// ---------------------------------------------------------------------------------------------------------------- the state file (3.4 5)
static const char *MLWhyFor(int p) { return gInstallWhy[p] ? MLWhyWord(gInstallWhy[p]) : MLWhyWord(gWhy[p]); }
static void MLWriteState(void) {
    int why[kMLPartCount];
    for (int p = 0; p < kMLPartCount; p++) why[p] = MLPartWanted(&gS, p) ? (gInstallWhy[p] ?: gWhy[p]) : kMLWhyNone;
    NSDictionary *d = MLStateDict(why, gNoStill, gStillRead);
    if ([d isEqual:gLastState]) return;
    for (int p = 0; p < kMLPartCount; p++) {
        BOOL was = MLStateHandled(gLastState, p), now = MLStateHandled(d, p);
        if (now && !was) os_log(OS_LOG_DEFAULT, "Mac Lock Screen: %{public}s left to another modification (%{public}s)", MLPartKey(p), MLWhyFor(p));
        else if (was && !now) os_log(OS_LOG_DEFAULT, "Mac Lock Screen: %{public}s is ours again", MLPartKey(p));
    }
    gLastState = d;
    [d writeToFile:@MLS_STATE_FILE atomically:YES];
}

// ---------------------------------------------------------------------------------------------------------------- coexistence checks (3.4)
static UIView *MLCoverView(void) { CSCoverSheetViewController *cs = gCS; return cs.isViewLoaded ? cs.view : nil; }
// B0 (25 Nov): the containers where iPadOS never puts a plain base-class child, read on 15.6.1 and 17.5.1 in every state probed; on 16 and 18 the
// plain rule waits for their B0 reads (a false stand-down would turn a part off on a stock iPad).
static BOOL MLPlainRuleProven(void) { return gOS == 15 || gOS == 17; }
static BOOL MLDebugForeign(int p) {
#if DEBUG
    NSString *s = [NSString stringWithContentsOfFile:@"/tmp/msb-lockforeign" encoding:NSUTF8StringEncoding error:nil];
    for (NSString *w in [s componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]) if ([w isEqualToString:@(MLPartKey(p))] || [w isEqualToString:@"face"]) return YES;
#endif
    return NO;
}
static int MLWidgetFrames(UIView *cv, CGRect *out, int max);
static BOOL MLPairBlocked(UIView *cv, CGRect r);
static int MLViewsFind(int p, MLClassCache *cc) {
    UIView *cv = MLCoverView();
    if (!cv) return kMLWhyNone;
    MLFind f = {0};
    switch (p) {
        case kMLPartClock: {
            UIView *dv = MLIvar(cv, "_dateView");
            if ([dv isKindOfClass:[UIView class]] && MLLayerWalk(&gTable, cc, dv.layer, 3, MLPlainRuleProven(), &f)) { MLLog(@"clock: %s in the date view%s", class_getName(f.cls), f.plain ? " (plain)" : ""); return kMLWhyView; }
            break;
        }
        case kMLPartBackground: {
            UIView *bg = MLIvar(cv, "_backgroundView");
            if ([bg isKindOfClass:[UIView class]] && MLLayerWalk(&gTable, cc, bg.layer, 3, NO, &f)) { MLLog(@"background: %s in the background view", class_getName(f.cls)); return kMLWhyView; }
            break;
        }
        case kMLPartCards: {
            UIView *mp = MLIvar(cv, "_mainPageView");
            for (UIView *x in [mp isKindOfClass:[UIView class]] ? mp.subviews : @[]) {
                if (![NSStringFromClass([x.nextResponder class]) isEqualToString:@"CSCombinedListViewController"]) continue;
                if (MLLayerWalk(&gTable, cc, x.layer, 3, NO, &f)) { MLLog(@"cards: %s in the list", class_getName(f.cls)); return kMLWhyView; }
            }
            break;
        }
        case kMLPartUser: {
            UIView *ff = MLIvar(cv, "_fixedFooterView"), *tm = MLIvar(cv, "_teachableMomentsContainerView");
            if ([ff isKindOfClass:[UIView class]] && MLLayerWalk(&gTable, cc, ff.layer, 3, MLPlainRuleProven(), &f)) { MLLog(@"user: %s in the footer%s", class_getName(f.cls), f.plain ? " (plain)" : ""); return kMLWhyView; }
            if ([tm isKindOfClass:[UIView class]] && MLLayerWalk(&gTable, cc, tm.layer, 3, NO, &f)) { MLLog(@"user: %s in the teachable-moments view", class_getName(f.cls)); return kMLWhyView; }
            break;
        }
        case kMLPartPair: {
            CGRect widgets[4]; int n = MLWidgetFrames(cv, widgets, 4);
            CGRect r = MLPairFrame(cv.bounds.size.width, 30, CGSizeMake(56, 20), widgets, n);
            if (!CGRectIsEmpty(r) && MLPairBlocked(cv, r)) { MLLog(@"pair: another's view in the top-right band"); return kMLWhyView; }
            break;
        }
        default: break;
    }
    return kMLWhyNone;
}
static BOOL MLWholeFace(MLClassCache *cc) {
    UIView *cv = MLCoverView();
    if (!cv) return NO;
    if (MLClassKind(&gTable, object_getClass(cv), NULL) == kMLKindOther) { MLLog(@"whole face: the Cover Sheet's view is another's class"); return YES; }
    CGFloat area = cv.bounds.size.width * cv.bounds.size.height;
    UIView *mp = MLIvar(cv, "_mainPageView");
    MLFind f = {0};
    for (UIView *c in @[ cv, [mp isKindOfClass:[UIView class]] ? mp : cv, cv.window ?: cv ]) {
        if (MLWholeFaceFind(&gTable, cc, c.layer, area, MLPlainRuleProven() && c != cv.window, &f)) { MLLog(@"whole face: %s over %@", class_getName(f.cls), NSStringFromClass([c class])); return YES; }
    }
    return NO;
}
// The check at an appearance (before anything of ours draws) and once more after its first layout (views a tweak adds late).
static void MLCheckAll(BOOL afterLayout) {
    CFTimeInterval t0 = CACurrentMediaTime();
    MLTableBuild(&gTable);
    MLClassCache cc; memset(&cc, 0, sizeof(cc));
    BOOL face = MLWholeFace(&cc);
    for (int p = 0; p < kMLPartCount; p++) {
        if (!MLPartWanted(&gS, p) || gInstallWhy[p]) { if (!afterLayout) gWhy[p] = kMLWhyNone; continue; }
        int why = face ? kMLWhyWholeFace : kMLWhyNone;
        if (!why && !afterLayout) {
            const char *cls = NULL, *img = NULL; SEL sel = NULL;
            MLPartWatchBuild(&gWatch[p], p, MLProminentClock());
            if (MLPartMethodsForeign(&gTable, &gWatch[p], &cls, &sel, &img)) { why = kMLWhyMethod; MLLog(@"%s: %s %@ is %s's", MLPartKey(p), cls, NSStringFromSelector(sel), img ?: "?"); }
        }
        if (!why) why = MLViewsFind(p, &cc);
        if (!why && MLDebugForeign(p)) { why = kMLWhyView; MLLog(@"%s: the debug owner (/tmp/msb-lockforeign)", MLPartKey(p)); }
        if (afterLayout) { if (why && !gWhy[p]) gWhy[p] = why; }   // (a late find stands the part down at once)
        else gWhy[p] = why;
    }
    gChecked = YES;
    MLLog(@"checks%s in %.3f ms: clock %s background %s cards %s user %s pair %s", afterLayout ? " (after the first layout)" : "", (CACurrentMediaTime() - t0) * 1000,
          MLWhyFor(0), MLWhyFor(1), MLWhyFor(2), MLWhyFor(3), MLWhyFor(4));
    MLWriteState();
}

// ---------------------------------------------------------------------------------------------------------------- the backdrop (2.4)
static UIImageView *gBackdrop;
static UIImage *gBackdropImage; static NSString *gBackdropKeyShown;
static BOOL gBackdropMaking; static CFTimeInterval gBackdropMakingAt;
static int gStillFailures;   // (failed answers in a row: three = this iPadOS gives none; a success clears it -- review finding 8)
static NSMutableSet *gEmptyKeys;   // (keys whose still had no picture in it: not read again until the source changes; the black backdrop, option b)
static BOOL gFloatHidden, gFloatWas;      // (17/18) we hid the depth-effect layer, and what it was before
static BOOL gDismissing;                  // (from the dismissal's start: the depth effect stays given back)
typedef struct { void *data; size_t height, width, rowBytes; } MLBuf;
static void MLBoxLine(uint8_t *p, size_t n, size_t step, int r, uint8_t *tmp) {   // (Lock9's box blur: our own, no Accelerate in SpringBoard)
    for (size_t i = 0; i < n; i++) memcpy(tmp + i * 4, p + i * step, 4);
    for (int c = 0; c < 4; c++) {
        int sum = 0;
        for (int k = -r; k <= r; k++) { long j = k < 0 ? 0 : k >= (long)n ? (long)n - 1 : k; sum += tmp[j * 4 + c]; }
        for (size_t i = 0; i < n; i++) {
            p[i * step + c] = (uint8_t)(sum / (2 * r + 1));
            long out = (long)i - r, in = (long)i + r + 1;
            sum += tmp[(in >= (long)n ? (long)n - 1 : in) * 4 + c] - tmp[(out < 0 ? 0 : out) * 4 + c];
        }
    }
}
static void MLBoxBlur(MLBuf *b, int r) {
    size_t n = MAX(b->width, b->height);
    uint8_t *tmp = malloc(n * 4);
    if (!tmp) return;
    for (size_t y = 0; y < b->height; y++) MLBoxLine((uint8_t *)b->data + y * b->rowBytes, b->width, 4, r, tmp);
    for (size_t x = 0; x < b->width; x++) MLBoxLine((uint8_t *)b->data + x * 4, b->height, b->rowBytes, r, tmp);
    free(tmp);
}
// aspect-filled into 256 px on the long side, three box passes of 6 px, saturation x1.2, darkened to the target luminance (any queue).
// A still with no picture in it (common/MacLockScreen.h MLStillEmpty: 17.5.1's and 18.5's poster thumbnails) gives nil and *empty YES.
static UIImage *MLBlurred(UIImage *src, CGSize screen, BOOL contrast, BOOL *empty) {
    if (empty) *empty = NO;
    if (!src.CGImage) return nil;
    CGSize px = MLBackdropPixels(screen);
    size_t W = (size_t)px.width, H = (size_t)px.height;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, W, H, 8, W * 4, cs, kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(cs);
    if (!ctx) return nil;
    CGContextSetInterpolationQuality(ctx, kCGInterpolationMedium);
    if (CGBitmapContextGetData(ctx)) memset(CGBitmapContextGetData(ctx), 0, H * CGBitmapContextGetBytesPerRow(ctx));   // (a clear pixel of the still reads black)
    CGSize is = CGSizeMake(CGImageGetWidth(src.CGImage), CGImageGetHeight(src.CGImage));
    CGContextDrawImage(ctx, MLAspectFillRect(is, CGSizeMake(W, H)), src.CGImage);   // (aspect fill, centred: a portrait still's centre band on a landscape screen, 12.2 (4))
    MLBuf b = { CGBitmapContextGetData(ctx), H, W, CGBitmapContextGetBytesPerRow(ctx) };
    if (!b.data || MLStillEmpty(b.data, W, H, b.rowBytes)) { if (empty) *empty = b.data != NULL; CGContextRelease(ctx); return nil; }   // (never blurred, stored or drawn)
    if (b.data) {
        for (int pass = 0; pass < 3; pass++) MLBoxBlur(&b, 6);
        uint8_t *pxl = b.data; double sum = 0;
        for (size_t y = 0; y < H; y++) { uint8_t *r = pxl + y * b.rowBytes; for (size_t x = 0; x < W; x++, r += 4) sum += 0.114 * r[0] + 0.587 * r[1] + 0.299 * r[2]; }
        double dim = MLBackdropDim(sum / (W * H) / 255.0, contrast);
        for (size_t y = 0; y < H; y++) {
            uint8_t *r = pxl + y * b.rowBytes;
            for (size_t x = 0; x < W; x++, r += 4) {
                double B = r[0], G = r[1], R = r[2], L = 0.114 * B + 0.587 * G + 0.299 * R;
                double c[3] = { L + (B - L) * 1.2, L + (G - L) * 1.2, L + (R - L) * 1.2 };
                for (int i = 0; i < 3; i++) { double v = c[i] * dim; r[i] = (uint8_t)(v < 0 ? 0 : v > 255 ? 255 : v); }
            }
        }
    }
    CGImageRef out = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    UIImage *img = out ? [UIImage imageWithCGImage:out] : nil;
    if (out) CGImageRelease(out);
    return img;
}
static BOOL MLLandscape(UIView *v) { CGSize s = v.bounds.size; return s.width > s.height; }
static NSString *MLFileStamp(NSString *path) {
    struct stat st;
    if (!path || stat(path.UTF8String, &st) != 0) return nil;
    return [NSString stringWithFormat:@"%@ %ld.%09ld %lld", path.lastPathComponent, (long)st.st_mtimespec.tv_sec, (long)st.st_mtimespec.tv_nsec, (long long)st.st_size];
}
static NSString *MLDesktopPicturePath(void) {   // (Settings > Desktop > Desktop Picture: its path in our main domain; None = no picture)
    BOOL dark = [UITraitCollection currentTraitCollection].userInterfaceStyle == UIUserInterfaceStyleDark;
    const char *keys[2] = { dark ? kMSBDWallpaperDarkKey : kMSBDWallpaperPathKey, kMSBDWallpaperPathKey };
    for (int i = 0; i < 2; i++) {
        const char *key = keys[i];
        CFPropertyListRef v = CFPreferencesCopyValue((__bridge CFStringRef)@(key), CFSTR("com.besiktasliseba.macstatusbar"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        NSString *s = v && CFGetTypeID(v) == CFStringGetTypeID() ? [(__bridge NSString *)v copy] : nil;
        if (v) CFRelease(v);
        if (MSBDWallpaperPathAllowed(s) && access(s.UTF8String, R_OK) == 0) return s;
    }
    return nil;
}
static id MLWallpaperController(void) { return MLObjCall(objc_getClass("SBWallpaperController"), @selector(sharedInstance)); }
// The source's identity, computed at each appearance (a few stats and reads, nothing watches at rest)
static NSString *MLBackdropSource(void) {
    if (gS.background == kMLBackDesktop) { NSString *p = MLDesktopPicturePath(); return p ? [@"desktop " stringByAppendingString:MLFileStamp(p) ?: p] : nil; }
    // (17/18: the active lock poster's UUID, version and supplement, each by a typed read of the routes 17.5.1 and 18.5 answer: common/MacLockScreen.h
    //  MLPosterSource, 1.8.9 pass: the black backdrop. 15/16 have no poster: the wallpaper files below)
    if (gOS >= 17) return MLPosterSource(MLIvar(MLWallpaperController(), "_activeLockScreenPosterConfiguration"));
    NSMutableString *s = [NSMutableString stringWithString:@"wallpaper"];
    BOOL any = NO;
    for (NSString *f in @[ @"LockBackground.cpbitmap", @"HomeBackground.cpbitmap", @"OriginalLockBackground.cpbitmap", @"LockBackgroundThumbnail.jpg" ]) {
        NSString *st = MLFileStamp([@"/var/mobile/Library/SpringBoard/" stringByAppendingString:f]);
        if (st) { [s appendFormat:@" %@", st]; any = YES; }
    }
    return any ? s : nil;
}
static NSString *MLBackdropPath(BOOL landscape, BOOL key) { return [NSString stringWithFormat:key ? @MLS_BACKDROP_KEY_FMT : @MLS_BACKDROP_FILE_FMT, landscape ? 'L' : 'P']; }
static void MLLayoutCoverParts(UIView *cv);
static void MLBackdropStore(UIImage *img, NSString *key, BOOL landscape, CGSize still) {
    NSData *png = UIImagePNGRepresentation(img);
    if (!png || !key) return;
    [png writeToFile:MLBackdropPath(landscape, NO) atomically:YES];
    [MLBackdropStoredKey(key, still) writeToFile:MLBackdropPath(landscape, YES) atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
// (a still picture could not be read on this iPadOS: Settings offers Wallpaper only from now on, SpringBoard draws Wallpaper)
static void MLNoStill(NSString *why, BOOL structural) {
    if (gNoStill) return;
    if (!structural && ++gStillFailures < 3) { MLLog(@"no still picture this time (%@): %d in a row", why, gStillFailures); return; }
    gNoStill = YES; MLLog(@"no still picture: %@", why); MLWriteState();
}
static void MLBackdropMake(NSString *key, BOOL landscape, CGSize screen, BOOL contrast) {
    if (gBackdropMaking && CACurrentMediaTime() - gBackdropMakingAt < 5) return;   // (an answer that never came does not block the next appearance: finding 9)
    gBackdropMaking = YES; gBackdropMakingAt = CACurrentMediaTime();
    void (^done)(UIImage *) = ^(UIImage *src) {
        if (!src) { gBackdropMaking = NO; if (gS.background == kMLBackBlurred) MLNoStill(@"no source", NO); return; }
        gStillFailures = 0;
        BOOL wallpaperStill = gS.background == kMLBackBlurred;   // (the wallpaper's or poster's still, not our Desktop Picture)
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ @autoreleasepool {
            CFTimeInterval t0 = CACurrentMediaTime();
            BOOL empty = NO;
            UIImage *img = MLBlurred(src, screen, contrast, &empty);
            double ms = (CACurrentMediaTime() - t0) * 1000;
            CGSize still = src.CGImage ? CGSizeMake(CGImageGetWidth(src.CGImage), CGImageGetHeight(src.CGImage)) : CGSizeZero;
            if (img) MLBackdropStore(img, key, landscape, still);
            dispatch_async(dispatch_get_main_queue(), ^{
                gBackdropMaking = NO;
                if (empty) {   // (the black backdrop, option b: not stored, not drawn; this key is not read again until the source changes)
                    if (!gEmptyKeys || gEmptyKeys.count >= 8) gEmptyKeys = [NSMutableSet set];
                    [gEmptyKeys addObject:key];
                    MLLog(@"the %.0f x %.0f still has no picture in it (every pixel black or clear): no backdrop, the wallpaper stays as iPadOS draws it", still.width, still.height);
                    return;
                }
                MLLog(@"backdrop made in %.1f ms (%@) from a %.0f x %.0f still, %@", ms, img ? @"stored" : @"failed", still.width, still.height, landscape ? @"landscape" : @"portrait");
                if (!img) return;
                if (wallpaperStill && gOS >= 17 && gS.enabled && !gStillRead) { gStillRead = YES; MLWriteState(); }   // (only 17/18 read it)
                gBackdropImage = img; gBackdropKeyShown = key;
                UIView *cv = MLCoverView();
                if (cv) MLLayoutCoverParts(cv);
            });
        } });
    };
    if (gS.background == kMLBackDesktop) {
        NSString *p = MLDesktopPicturePath();
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ UIImage *i = p ? [UIImage imageWithContentsOfFile:p] : nil; dispatch_async(dispatch_get_main_queue(), ^{ done(i); }); });
        return;
    }
    id wc = MLWallpaperController();
    if (gOS < 17) {   // (15/16: the lock wallpaper view's own still, Lock9's path; B0: 15.6.1 SBFStaticWallpaperView 1116 x 1116 @2)
        SEL wv = NSSelectorFromString(@"_wallpaperViewForVariant:");
        UIView *v = [wc respondsToSelector:wv] && MLArgInt(class_getInstanceMethod(object_getClass(wc), wv), 2) ? ((id (*)(id, SEL, long))objc_msgSend)(wc, wv, 0) : nil;
        UIImage *img = MLObjCall(v, NSSelectorFromString(@"_displayedImage"));
        if ([img isKindOfClass:[UIImage class]]) { done(img); return; }
    }
    // (17/18, and 15/16 without that view: the wallpaper server's thumbnail of the lock variant; B0: 17.5.1 366 x 488, answered on the main thread)
    SEL th = NSSelectorFromString(@"wallpaperServer:fetchThumbnailDataForVariant:completionHandler:");
    Method m = wc ? class_getInstanceMethod(object_getClass(wc), th) : NULL;
    if (!m || method_getNumberOfArguments(m) != 5 || !MLArgInt(m, 3)) { gBackdropMaking = NO; if (gS.background == kMLBackBlurred) MLNoStill(@"no thumbnail call on this iPadOS", YES); return; }
    void (^answer)(id) = ^(id data) {
        UIImage *img = [data isKindOfClass:[NSData class]] ? [UIImage imageWithData:data] : nil;
        if ([NSThread isMainThread]) done(img); else dispatch_async(dispatch_get_main_queue(), ^{ done(img); });
    };
    ((void (*)(id, SEL, id, long, id))objc_msgSend)(wc, th, nil, 0, answer);
}
// At an appearance: the picture for this key, from memory, then the disk (decoded before the first frame), else made (shown when ready).
static void MLBackdropPrepare(UIView *cv) {
    if (!MLPart(kMLPartBackground)) return;
    BOOL landscape = MLLandscape(cv), contrast = UIAccessibilityDarkerSystemColorsEnabled();
    BOOL dark = cv.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    NSString *key = MLBackdropKey(MLBackdropSource(), landscape, dark, contrast);
    if (!key) { if (gS.background == kMLBackBlurred) MLNoStill(@"no source identity", NO); return; }
    if (gBackdropImage && [gBackdropKeyShown isEqualToString:key]) return;
    if ([gEmptyKeys containsObject:key]) { gBackdropImage = nil; gBackdropKeyShown = nil; return; }   // (its still had no picture in it: the wallpaper as iPadOS draws it)
    NSString *disk = [NSString stringWithContentsOfFile:MLBackdropPath(landscape, YES) encoding:NSUTF8StringEncoding error:nil];
    if (MLBackdropKeyMatches(disk, key)) {
        CFTimeInterval t0 = CACurrentMediaTime();
        UIImage *img = [UIImage imageWithContentsOfFile:MLBackdropPath(landscape, NO)];
        img = [img imageByPreparingForDisplay] ?: img;   // (decoded now, on this pass: whole from the first frame)
        if (img) {
            gBackdropImage = img; gBackdropKeyShown = key; MLLog(@"backdrop from the disk in %.2f ms", (CACurrentMediaTime() - t0) * 1000);
            if (gS.background == kMLBackBlurred && gOS >= 17 && !gStillRead) { gStillRead = YES; MLWriteState(); }   // (stored only from a still with a picture in it; only 17/18 read it)
            return;
        }
    }
    gBackdropImage = nil; gBackdropKeyShown = nil;
    MLBackdropMake(key, landscape, cv.bounds.size, contrast);
}
static void MLFloatLayer(BOOL hide) {   // (17/18: the depth effect's floating layer, through SpringBoard's own call, balanced)
    if (gOS < 17) return;
    id pm = MLPresentationManager();
    SEL set = @selector(setWallpaperFloatingLayerHidden:), get = @selector(wallpaperFloatingLayerHidden);
    if (![pm respondsToSelector:set]) return;
    if (hide && gDismissing) return;
    if (hide && !gFloatHidden) {
        gFloatWas = MLBoolCall(pm, get, NO);
        ((void (*)(id, SEL, BOOL))objc_msgSend)(pm, set, YES);
        gFloatHidden = YES;
        MLLog(@"depth effect hidden (was %d)", gFloatWas);
    } else if (!hide && gFloatHidden) {
        // (only while it is still our YES: SpringBoard may have changed it since -- review finding 13)
        if (MLBoolCall(pm, get, YES)) ((void (*)(id, SEL, BOOL))objc_msgSend)(pm, set, gFloatWas);
        gFloatHidden = NO;
        MLLog(@"depth effect given back (%d)", gFloatWas);
    }
}
static void MLBackdropDrop(void) {
    [gBackdrop removeFromSuperview];
    gBackdrop.image = nil;
    gBackdrop = nil;
    MLFloatLayer(NO);
}
// (17/18, 12.7) a depth poster's subject still drawn over our backdrop after SpringBoard's own call: the backdrop stands down for this appearance
// (the wallpaper and its depth effect as iPadOS draws them; our clock stays). Read a main-queue turn after the call (its animation's end values).
static BOOL MLDepthLayerDrawn(UIView *cv, BOOL *present) {
    UIView *c = MLIvar(cv, "_wallpaperFloatingLayerContainerView");
    *present = NO;
    if (![c isKindOfClass:[UIView class]]) return NO;
    for (UIView *x in c.subviews) {
        NSString *cn = NSStringFromClass([x class]);
        if (MLIsTaggedOurs(x.layer) || (![cn containsString:@"Floating"] && ![cn containsString:@"Replica"])) continue;   // (17.5.1: PBUIPosterFloatingLayerReplica)
        *present = YES;
        CGFloat a = 1; BOOL shown = YES;
        for (UIView *v = x; v && v != cv.window; v = v.superview) { if (v.hidden) shown = NO; a *= v.alpha; }
        if (shown && a > 0.01 && x.bounds.size.width > 1) return YES;
    }
    return NO;
}
static void MLDepthCheckSoon(void) {
    if (gOS < 17) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *cv = MLCoverView();
        if (!cv.window || !gBackdrop.superview || gDepthDown) return;
        BOOL present = NO, drawn = MLDepthLayerDrawn(cv, &present);
        if (!MLDepthStandsDown(YES, present, drawn)) return;
        gDepthDown = YES;
        MLLog(@"the depth effect is still drawn over the backdrop after SpringBoard's call: the wallpaper stays as iPadOS draws it for this appearance");
        MLBackdropDrop();
        [cv setNeedsLayout];
    });
}

// ---------------------------------------------------------------------------------------------------------------- the clock (2.6)
@interface MLClockView : UIView
@property (nonatomic, strong) UILabel *date, *time;
@end
@implementation MLClockView
@end
static MLClockView *gClock;
static __weak UIView *gPadlock;   // (SBUIProudLockIconView, found at each appearance)
static NSDateFormatter *gDateFmt, *gTimeFmt;
static NSHashTable *gHiddenByUs;   // iPadOS's clock views we hid (given back exactly: only what we hid)
static NSHashTable *gBandHidden;   // ...and the bar's band (A22)
static void MLHideIn(NSHashTable *__strong *set, UIView *v, BOOL hide) {
    if (![v isKindOfClass:[UIView class]]) return;
    if (!*set) *set = [NSHashTable weakObjectsHashTable];
    if (hide && !v.hidden) { v.hidden = YES; [*set addObject:v]; }
    else if (!hide && [*set containsObject:v]) { v.hidden = NO; [*set removeObject:v]; }
}
static void MLHide(UIView *v, BOOL hide) { MLHideIn(&gHiddenByUs, v, hide); }
static void MLGiveBackHidden(void) { for (UIView *v in [gHiddenByUs allObjects]) v.hidden = NO; [gHiddenByUs removeAllObjects]; }
static void MLGiveBackBand(void) { for (UIView *v in [gBandHidden allObjects]) v.hidden = NO; [gBandHidden removeAllObjects]; }
static void MLMakeFormatters(void) {
    NSLocale *loc = [NSLocale currentLocale];
    gDateFmt = [NSDateFormatter new]; gDateFmt.locale = loc; gDateFmt.timeZone = [NSTimeZone localTimeZone];
    gDateFmt.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"EEEEdMMMM" options:0 locale:loc];
    gTimeFmt = [NSDateFormatter new]; gTimeFmt.locale = loc; gTimeFmt.timeZone = [NSTimeZone localTimeZone];
    gTimeFmt.dateFormat = MLTimeFormat([NSDateFormatter dateFormatFromTemplate:@"jmm" options:0 locale:loc] ?: @"HH:mm");
}
static UILabel *MLFirstLabel(UIView *v, int depth) {
    if ([v isKindOfClass:[UILabel class]]) return (UILabel *)v;
    if (depth <= 0) return nil;
    for (UIView *s in v.subviews) { UILabel *l = MLFirstLabel(s, depth - 1); if (l) return l; }
    return nil;
}
static long MLLegibilityStyle(UIView *v) {
    id ls = [v respondsToSelector:@selector(legibilitySettings)] ? [v performSelector:@selector(legibilitySettings)] : nil;
    return [ls respondsToSelector:@selector(style)] ? ((long (*)(id, SEL))objc_msgSend)(ls, @selector(style)) : 1;
}
static BOOL MLShown(UIView *v) { return [v isKindOfClass:[UIView class]] && v.window && !v.hidden && v.alpha > 0.01; }
static void MLClockDrop(void) {
    [gClock removeFromSuperview]; gClock = nil;
    MLGiveBackHidden();
}
// The Mac clock (12.4, 12.5, 12.4a): macOS's measured proportions from the screen's short side (the time a bit larger, KT's Q28), placed by
// baselines, clamped to iPadOS's own clock zone, centred on the screen (common/MacLockScreen.h MLMacClockLayout). host: the date view (15-18: SBFLockScreenDateView; on 16-18 it holds CSProminentDisplayView,
// and the depth effect's layer is above it). timeView / dateView: iPadOS's own time and plain date line; zoneBottom: the zone's bottom and
// columnRight: the 17/18 landscape widget column's right edge (0 none), both in the Cover Sheet view's coordinates; dateDrawn: ours draws the
// date too (a date line carrying a widget, or an alternate line iPadOS draws, stays iPadOS's: then the time only).
static CGFloat gStatusBottom;      // (the top right's drawn bottom: a bar drawn or our pair, from 12.1's last read; 0 none)
static MLMacClock gClockLast;      // (the last layout and its inputs: the debug dump's expected values for L33)
static CGFloat gClockTopLast, gClockZoneLast;
static NSString *gClockTimeKey;    // (the time label's text, size, weight and colour as last set)
static BOOL MLHintMaskedByUs(UIView *v);
static UIView *MLTransientHint(UIView *prominent);
static UIView *MLProminent(UIView *cv);
static void MLClockPlace(UIView *host, UIView *timeView, UIView *dateView, BOOL dateDrawn, NSDate *now, CGFloat zoneBottom, CGFloat columnRight, CGFloat keptLineBottom) {
    if (gS.clockStyle == kMLClockNone) { MLHide(timeView, YES); if (dateDrawn) MLHide(dateView, YES); [gClock removeFromSuperview]; gClock = nil; return; }
    UIView *cv = MLCoverView();
    if (!cv.window || ![timeView isKindOfClass:[UIView class]]) return;
    CGSize scr = cv.bounds.size;
    CGFloat S = MIN(scr.width, scr.height);
    // the top limit: the padlock's drawn bottom (its frame plus our Menu Bar Size shift, a sublayer transform), the top right's drawn bottom,
    // and iPadOS's hint line at the top while it draws (18.5 Face ID with our field off or standing down), each + 8
    CGFloat top = gStatusBottom > 0 ? gStatusBottom + 8 : 0;
    UIView *pad = gPadlock, *lockView = MLIvar(pad, "_lockView");
    if (MLShown(lockView)) top = MAX(top, MLClockTopLimit(CGRectGetMaxY([cv convertRect:lockView.bounds fromView:lockView]), pad.layer.sublayerTransform.m42, 0) + 8);
    UIView *th = MLProminentClock() ? MLTransientHint(MLProminent(cv)) : nil;   // (the prominent display's transient line: 16-18, MLClockPath)
    if (MLShown(th) && !MLHintMaskedByUs(th)) top = MAX(top, CGRectGetMaxY([cv convertRect:th.bounds fromView:th]) + 8);
    if (!dateDrawn) top = MLClockKeptTop(top, keptLineBottom, S);   // (17/18: under the date line iPadOS keeps, review finding 1)
    if (!gDateFmt) MLMakeFormatters();
    NSString *ds = [gDateFmt stringFromDate:now], *ts = [gTimeFmt stringFromDate:now];
    BOOL bold = UIAccessibilityIsBoldTextEnabled();
    UIFontWeight tw = bold ? UIFontWeightBold : UIFontWeightSemibold, dwt = bold ? UIFontWeightSemibold : UIFontWeightMedium;   // (macOS's: 12.4a)
    UIFont *t1 = [UIFont systemFontOfSize:100 weight:tw], *d1 = [UIFont systemFontOfSize:100 weight:dwt];
    CGFloat tw1 = MLMacTimeWidth1([ts sizeWithAttributes:@{ NSFontAttributeName: t1 }].width / 100, ts.length), dw1 = [ds sizeWithAttributes:@{ NSFontAttributeName: d1 }].width / 100;
    MLFontMetrics tm = { t1.ascender / 100, t1.capHeight / 100, t1.lineHeight / 100 }, dm = { d1.ascender / 100, d1.capHeight / 100, d1.lineHeight / 100 };
    MLMacClock c = MLMacClockLayout(S, scr.width, top, zoneBottom, columnRight, tw1, dw1, dateDrawn, dm, tm);
    gClockLast = c; gClockTopLast = top; gClockZoneLast = zoneBottom;
    if (!c.fits) { if (gClock || gHiddenByUs.count) { MLLog(@"no room for the Mac clock in iPadOS's clock zone (top %.0f, zone bottom %.0f): iPadOS's clock stays", top, zoneBottom); MLClockDrop(); } return; }
    if (!gClock) {
        gClock = [[MLClockView alloc] initWithFrame:host.bounds];
        gClock.userInteractionEnabled = NO;
        MLTagOurs(gClock.layer);
        gClock.date = [UILabel new]; gClock.time = [UILabel new];
        for (UILabel *l in @[ gClock.date, gClock.time ]) { l.textAlignment = NSTextAlignmentCenter; l.backgroundColor = [UIColor clearColor]; l.adjustsFontSizeToFitWidth = NO; MLTagOurs(l.layer); [gClock addSubview:l]; }
        gClock.time.isAccessibilityElement = YES;   // (its own frame; the full-screen clock view is not an element: review finding 16)
        gClockTimeKey = nil;
        gClock.time.accessibilityTraits = UIAccessibilityTraitStaticText;
        gClock.date.isAccessibilityElement = NO;
    }
    if (gClock.superview != host) [host addSubview:gClock];
    gClock.frame = host.bounds;
    // white 0.80 over our backdrop (12.4a); over iPadOS's sharp wallpaper its legibility colours (rev 1 2.6)
    BOOL overOurs = MLPart(kMLPartBackground) && gBackdrop.image != nil;
    MLTextLook look = MLTextLookFor(overOurs, MLLegibilityStyle(host));
    UIColor *col = [UIColor colorWithWhite:look.white alpha:overOurs ? kMLClockWhiteAlpha : look.alpha];
    // (macOS's tracking, -0.03 em, between the glyphs only: none after the last, so the time stays centred. Set only when the text, size, weight
    //  or colour changed: a label's attributed text reads back with UIKit's own attributes added, so it is never compared with ours)
    NSString *tkey = [NSString stringWithFormat:@"%@|%.2f|%.3f|%@", ts ?: @"", c.timeSize, (double)tw, col];
    if (![gClockTimeKey isEqualToString:tkey]) {
        UIFont *tf = [UIFont systemFontOfSize:c.timeSize weight:tw];
        NSMutableAttributedString *tas = [[NSMutableAttributedString alloc] initWithString:ts ?: @"" attributes:@{ NSFontAttributeName: tf, NSForegroundColorAttributeName: col }];
        if (tas.length > 1) [tas addAttribute:NSKernAttributeName value:@(MLMacTimeKern(c.timeSize)) range:NSMakeRange(0, tas.length - 1)];
        gClock.time.attributedText = tas;
        gClockTimeKey = tkey;
    }
    gClock.date.hidden = !dateDrawn;
    if (dateDrawn) {
        UIFont *df = [UIFont systemFontOfSize:c.dateSize weight:dwt];
        if (![gClock.date.font isEqual:df]) gClock.date.font = df;
        if (![gClock.date.text isEqualToString:ds]) gClock.date.text = ds;
    }
    for (UILabel *l in @[ gClock.date, gClock.time ]) {
        l.textColor = col;
        l.layer.shadowColor = [UIColor colorWithWhite:look.shadowWhite alpha:1].CGColor;
        l.layer.shadowOpacity = (float)look.shadowAlpha; l.layer.shadowRadius = 6; l.layer.shadowOffset = CGSizeZero;
    }
    // (each label only as wide as its text, on whole points; placed in the Cover Sheet's coordinates, centred on the screen, then into the host's)
    CGFloat twd = ceil([gClock.time sizeThatFits:CGSizeMake(scr.width, c.timeSize * 1.3)].width) + 2;
    CGFloat dwd = dateDrawn ? ceil([gClock.date sizeThatFits:CGSizeMake(scr.width, c.dateSize * 1.3)].width) + 2 : 0;
    CGFloat mid = scr.width / 2;
    CGRect dateR = CGRectMake(round(mid - dwd / 2), c.top, dwd, c.dateH), timeR = CGRectMake(round(mid - twd / 2), c.timeTop, twd, c.timeH);
    gClock.time.frame = [gClock convertRect:timeR fromView:cv];
    if (dateDrawn) gClock.date.frame = [gClock convertRect:dateR fromView:cv];
    gClock.time.accessibilityLabel = dateDrawn ? [NSString stringWithFormat:@"%@, %@", ts, ds] : ts;
    MLHide(timeView, YES);
    if (dateDrawn) MLHide(dateView, YES);
}
static CGFloat MLBottomIn(UIView *v, UIView *cv) { return [v isKindOfClass:[UIView class]] && v.window ? CGRectGetMaxY([cv convertRect:v.bounds fromView:v]) : 0; }
// 15 (MLClockPath: no prominent display): iPadOS's labels inside SBFLockScreenDateView; the zone ends at the time label's bottom
static void MLClockLayout15(UIView *dv) {
    if (!MLPart(kMLPartClock)) { if (gClock || gHiddenByUs.count) MLClockDrop(); return; }
    UIView *time = MLIvar(dv, "_timeLabel"), *dateSub = MLIvar(dv, "_dateSubtitleView"), *custom = MLIvar(dv, "_customSubtitleView"), *active = MLIvar(dv, "_activeSubtitleView");
    if (![time isKindOfClass:[UIView class]]) return;
    // (an alternate subtitle -- charging, a timer: 15.6.1's _customSubtitleView, faded in while the date fades out -- stays iPadOS's under our
    //  time; review 1.8.9 F49 finding 2)
    BOOL plainDate = dateSub && !MLShown(custom) && (!active || active == dateSub);
    NSDate *d = [dv respondsToSelector:@selector(date)] ? [(SBFLockScreenDateView *)dv date] : nil;
    UIView *cv = MLCoverView();
    CGFloat zone = MLBottomIn(time, cv);
    if (!plainDate) zone = MIN(zone > 0 ? zone : CGFLOAT_MAX, [cv convertRect:((UIView *)(MLShown(custom) ? custom : active)).bounds fromView:(MLShown(custom) ? custom : active)].origin.y - 8);
    MLClockPlace(dv, time, dateSub, plainDate, d ?: [NSDate date], zone == CGFLOAT_MAX ? 0 : zone, 0, 0);   // (15: the kept line is under the time)
}
// 16-18 (MLClockPath: the prominent display): CSProminentDisplayView's time view and plain date line (a date line carrying a widget, or a
// transient line iPadOS draws, stays iPadOS's). The zone ends at iPadOS's time view's bottom, above the inline widget row when it holds widgets
// (17/18); the landscape widget column on the left (17/18). 16 has no widgets: those reads find nothing there and change nothing.
static void MLClockLayout17(UIView *pd) {
    if (!MLPart(kMLPartClock)) { if (gClock || gHiddenByUs.count) MLClockDrop(); return; }
    UIView *time = MLIvar(pd, "_timeView"), *sub = MLIvar(pd, "_subtitleView"), *transient = MLIvar(pd, "_transientSubtitleView");
    UIView *custom = MLObjCall(pd, NSSelectorFromString(@"customSubtitleView")) ?: MLIvar(pd, "_customSubtitleView");
    UIView *widgetLine = MLIvar(pd, "_subtitleComplicationView");   // (17.5.1: where a date-line widget lives; review finding 4)
    UIView *row = MLIvar(pd, "_complicationRowView");
    UIView *cv = MLCoverView();
    UIView *host = MLIvar(cv, "_dateView") ?: pd.superview;
    if (![time isKindOfClass:[UIView class]] || ![host isKindOfClass:[UIView class]]) return;
    BOOL widget = MLShown(widgetLine) && widgetLine.subviews.count > 0 && widgetLine.bounds.size.width > 1;
    // (the 18.5 Face ID hint in the transient line is mirrored into our field and draws nothing there: our date then takes the line)
    BOOL transientDrawn = MLShown(transient) && !MLHintMaskedByUs(transient);
    BOOL plainDate = [sub isKindOfClass:[UIView class]] && !MLShown(custom) && !transientDrawn && !widget;
    CGFloat zone = MLBottomIn(time, cv);
    BOOL rowWidgets = MLShown(row) && ![NSStringFromClass([row class]) containsString:@"Empty"] && row.bounds.size.height > 1;
    if (rowWidgets) zone = MIN(zone, [cv convertRect:row.bounds fromView:row].origin.y - 8);
    UIView *side = MLIvar(cv, "_sidebarComplicationContainerView");
    CGFloat columnRight = MLShown(side) && side.subviews.count ? CGRectGetMaxX([cv convertRect:side.bounds fromView:side]) : 0;
    // the date line iPadOS keeps (not plain): its drawn bottom, our time under it
    CGFloat kept = 0;
    if (!plainDate) for (UIView *v in @[ [sub isKindOfClass:[UIView class]] ? sub : time, MLShown(custom) ? custom : time, transientDrawn ? transient : time, widget ? widgetLine : time ]) {
        if (v == time || !MLShown(v)) continue;
        kept = MAX(kept, MLBottomIn(v, cv));
    }
    // (the minute: iPadOS's own update lays this view out -- setDisplayDate:, the time view's setDate: --; the time itself is now's)
    MLClockPlace(host, time, sub, plainDate, [NSDate date], zone, columnRight, kept);
}

// ---------------------------------------------------------------------------------------------------------------- the cards (2.2)
static BOOL MLOnLockList(UIView *platter) {   // (inside the Cover Sheet's list on our screen: never a widget, never a banner)
    UIWindow *w = platter.window;
    if (!w || w.screen != [UIScreen mainScreen] || ![NSStringFromClass([w class]) isEqualToString:@"SBCoverSheetWindow"]) return NO;
    for (UIView *v = platter.superview; v && v != w; v = v.superview) {
        NSString *c = NSStringFromClass([v.nextResponder class]);
        if ([c isEqualToString:@"CSWidgetGridViewController"] || [c isEqualToString:@"CSComplicationContainerViewController"]) return NO;
        if ([NSStringFromClass([v class]) isEqualToString:@"CSMainPageView"]) return YES;
    }
    return NO;
}
static void MLCardLayout(UIView *platter) {
    if (MLPart(kMLPartCards) && MLOnLockList(platter)) {
        if (!gCards) gCards = [NSHashTable weakObjectsHashTable];
        MSBDMacCardRecord(platter);
        MSBDMacCardApplyIfNeeded(platter, platter.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark, UIAccessibilityDarkerSystemColorsEnabled());
        [gCards addObject:platter];
    } else if ([gCards containsObject:platter]) {
        MSBDMacCardRestore(platter);
        [gCards removeObject:platter];
    }
}
static void MLCardsGiveBack(void) { for (UIView *p in [gCards allObjects]) MSBDMacCardRestore(p); [gCards removeAllObjects]; }

// ---------------------------------------------------------------------------------------------------------------- the picture and name (2.5, 2.6; rev 2 12.6)
// The macOS user block at rest (12.4a, KT's Q28 "exactly like macOS"): a large round picture with a soft shadow, the name under it, and a plain
// line of ours in iPadOS's own hint slot at the bottom carrying iPadOS's own unlock hint (the one hint view iPadOS draws, mirrored, and that
// view masked while ours shows it: one hint drawing). No capsule and no glyph: macOS shows its field only while typing, which this part never has.
@interface MLUserView : UIView
@property (nonatomic, strong) UIImageView *picture;
@property (nonatomic, strong) UILabel *name;
@property (nonatomic, strong) UIView *field;       // (the hint line's view)
@property (nonatomic, strong) UILabel *fieldText;
@end
@implementation MLUserView
@end
static MLUserView *gUser;
static BOOL gFieldOwned;           // another modification changes iPadOS's hint line: our field stands down (the picture and name stay)
static UIImage *MLMonogram(NSString *name, CGFloat d) {   // macOS's grey monogram (Lock9's colours), up to two initials
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(d, d)];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *rc) {
        CGContextRef c = rc.CGContext;
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, d, d)] addClip];
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGFloat comps[8] = { 0.66, 0.67, 0.70, 1, 0.52, 0.53, 0.57, 1 };
        CGGradientRef g = CGGradientCreateWithColorComponents(cs, comps, NULL, 2);
        CGContextDrawLinearGradient(c, g, CGPointMake(0, 0), CGPointMake(0, d), 0);
        CGGradientRelease(g); CGColorSpaceRelease(cs);
        NSString *ini = MLInitials(name);
        NSDictionary *a = @{ NSFontAttributeName: [UIFont systemFontOfSize:round(d * 0.40) weight:UIFontWeightMedium], NSForegroundColorAttributeName: [UIColor whiteColor] };
        CGSize ts = [ini sizeWithAttributes:a];
        [ini drawAtPoint:CGPointMake(round((d - ts.width) / 2), round((d - ts.height) / 2)) withAttributes:a];
    }];
}
static UIImage *MLPictureImage(NSString *name, CGFloat d) {
    UIImage *pic = gS.picture == kMLPictureFile ? [UIImage imageWithContentsOfFile:@MLS_PICTURE_FILE] : nil;
    if (!pic) return MLMonogram(name, d);
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(d, d)];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *rc) {
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, d, d)] addClip];
        CGSize s = pic.size; CGFloat k = MAX(d / MAX(s.width, 1), d / MAX(s.height, 1));
        [pic drawInRect:CGRectMake((d - s.width * k) / 2, (d - s.height * k) / 2, s.width * k, s.height * k)];
    }];
}
static CGFloat gListBottomUsed = -1;   // (the list's lowest content the block was last placed against)
static void MLHintUnmaskAll(void);
static void MLUserDrop(void) { [gUser removeFromSuperview]; gUser = nil; gListBottomUsed = -1; MLHintUnmaskAll(); }
static CGFloat MLTopInScreen(UIView *v, UIView *screenView) {
    if (![v isKindOfClass:[UIView class]] || !v.window || v.bounds.size.height <= 0.5) return 0;
    return [screenView convertRect:v.bounds fromView:v].origin.y;
}
// The lowest visible content of iPadOS's list (cells, the count line, Now Playing / Live Activities in the adjunct list), read only.
static void MLListBottomWalk(UIView *v, UIView *cv, CGFloat *bottom, int depth) {
    if (depth > 9 || v.hidden || v.alpha < 0.01) return;
    NSString *c = NSStringFromClass([v class]);
    BOOL content = [c isEqualToString:@"NCNotificationListCell"] || [c isEqualToString:@"NCNotificationListCountIndicatorView"] || [c hasPrefix:@"CSAdjunctItem"]
                || [c isEqualToString:@"PLPlatterView"];
    if (content && v.bounds.size.height > 1) {
        CGRect r = [cv convertRect:v.bounds fromView:v];
        if (CGRectIntersectsRect(r, cv.bounds)) *bottom = MAX(*bottom, CGRectGetMaxY(r));
        return;
    }
    for (UIView *s in v.subviews) MLListBottomWalk(s, cv, bottom, depth + 1);
}
static int MLWidgetFrames(UIView *cv, CGRect *out, int max) {   // (17/18: the side column and the inline row, read at each layout)
    int n = 0;
    UIView *side = MLIvar(cv, "_sidebarComplicationContainerView");
    if ([side isKindOfClass:[UIView class]] && !side.hidden && side.alpha > 0.01 && n < max) out[n++] = [cv convertRect:side.bounds fromView:side];
    UIView *dv = MLIvar(cv, "_dateView");
    for (UIView *pd in [dv isKindOfClass:[UIView class]] ? dv.subviews : @[]) {
        UIView *row = MLIvar(pd, "_complicationRowView");
        if ([row isKindOfClass:[UIView class]] && !row.hidden && row.alpha > 0.01 && n < max) out[n++] = [cv convertRect:row.bounds fromView:row];
    }
    return n;
}
// ---- iPadOS's hint views (12.6) ----
static __weak UIView *gHintLabel;   // the hint view mirrored now (iPadOS's)
static __weak UIView *gHintCand0, *gHintCand1, *gHintCand2;   // the three candidates of the last pick (their changes re-pick: review finding 4)
static BOOL gFieldPaging;           // the Cover Sheet's pages are off the main page: our field hidden, iPadOS's hint drawn (review finding 3)
static CALayer *gHintMask;          // our empty mask: a layer with no content as the view's layer.mask draws nothing of it
static NSHashTable *gMasked;        // (weak) views carrying our mask
static UIView *MLProminent(UIView *cv) {
    UIView *dv = MLIvar(cv, "_dateView");
    for (UIView *x in [dv isKindOfClass:[UIView class]] ? dv.subviews : @[]) if ([NSStringFromClass([x class]) isEqualToString:@"CSProminentDisplayView"]) return x;
    return nil;
}
static NSString *MLHintText(UIView *v) {
    for (NSString *n in @[ @"text", @"string" ]) {
        id t = MLObjCall(v, NSSelectorFromString(n));
        if ([t isKindOfClass:[NSString class]]) return t;
        if ([t isKindOfClass:[NSAttributedString class]]) return [(NSAttributedString *)t string];
    }
    return MLFirstLabel(v, 3).text;
}
static CGFloat MLEffAlpha(UIView *v) {
    if (![v isKindOfClass:[UIView class]] || !v.window) return 0;
    CGFloat a = 1;
    for (UIView *x = v; x && x != v.window; x = x.superview) { if (x.hidden) return 0; a *= x.alpha; }
    return a;
}
// a hint view's drawn alpha: SBUICallToActionLabel draws through its inner label, which its own fades animate
static CGFloat MLHintAlpha(UIView *v) {
    CGFloat a = MLEffAlpha(v);
    id inner = [v isKindOfClass:[UIView class]] ? MLObjCall(v, NSSelectorFromString(@"label")) : nil;
    if ([inner isKindOfClass:[UIView class]] && [(UIView *)inner isDescendantOfView:v]) a *= ((UIView *)inner).hidden ? 0 : ((UIView *)inner).alpha;
    return a;
}
// (17/18) the prominent display's transient line, only while it carries the Cover Sheet's own unlock hint (18.5 Face ID: the line by the padlock)
static UIView *MLTransientHint(UIView *prominent) {
    UIView *t = MLIvar(prominent, "_transientSubtitleView");
    if (![t isKindOfClass:[UIView class]]) return nil;
    CSCoverSheetViewController *cs = gCS;
    id pl = MLIvar(cs, "_proudLockViewController");
    id hint = MLObjCall(pl, NSSelectorFromString(@"transientSubtitleText")) ?: MLObjCall(cs, NSSelectorFromString(@"transientSubtitleText"));
    NSString *txt = MLHintText(t);
    return [hint isKindOfClass:[NSString class]] && [hint length] && [txt isEqualToString:hint] ? t : nil;
}
static BOOL MLHintMaskedByUs(UIView *v) { return [v isKindOfClass:[UIView class]] && gHintMask && v.layer.mask == gHintMask; }
// Our mask only on a view that carries none (a mask of iPadOS's or another's is never replaced: then our field stands down for that pass)
static BOOL MLHintMask(UIView *v) {
    if (!v) return NO;
    if (!gHintMask) { gHintMask = [CALayer layer]; MLTagOurs(gHintMask); }
    if (v.layer.mask == gHintMask) return YES;
    if (v.layer.mask) return NO;
    if (gHintMask.superlayer || [gMasked count]) { for (UIView *o in [gMasked allObjects]) if (o.layer.mask == gHintMask) o.layer.mask = nil; [gMasked removeAllObjects]; }
    v.layer.mask = gHintMask;
    if (!gMasked) gMasked = [NSHashTable weakObjectsHashTable];
    [gMasked addObject:v];
    return YES;
}
static void MLHintUnmaskViews(void) {   // (every view of iPadOS's we masked draws again)
    for (UIView *v in [gMasked allObjects]) if (v.layer.mask == gHintMask) v.layer.mask = nil;
    [gMasked removeAllObjects];
}
static void MLHintUnmaskAll(void) { MLHintUnmaskViews(); gHintLabel = nil; gFieldPaging = NO; }
// The candidates in the order iPadOS uses them: the footer's call-to-action (17.5.1 Touch ID), the teachable container's (15; 18.5 keeps it at
// alpha 0), the transient line by the padlock (18.5 Face ID). The slot for our field: the footer's label, else the teachable one (its place
// stays while its alpha is 0).
static UIView *MLHintPicked(UIView *cv, CGRect *slot) {
    UIView *ff = MLIvar(cv, "_fixedFooterView"), *tm = MLIvar(cv, "_teachableMomentsContainerView");
    UIView *cands[3] = { MLIvar(ff, "_callToActionLabel"), MLIvar(tm, "_callToActionLabel"), MLProminentClock() ? MLIvar(MLProminent(cv), "_transientSubtitleView") : nil };
    gHintCand0 = cands[0]; gHintCand1 = cands[1]; gHintCand2 = cands[2];
    if (cands[2] && cands[2] != MLTransientHint(MLProminent(cv))) cands[2] = nil;   // (the transient line only while it carries the unlock hint)
    MLHintFacts f[3];
    for (int i = 0; i < 3; i++) {
        UIView *c = cands[i];
        // (a view we masked still counts as drawn by iPadOS: the mask is ours, its alpha and hidden state iPadOS's)
        f[i].drawn = [c isKindOfClass:[UIView class]] && c.window != nil;
        f[i].alpha = MLHintAlpha(c);
        f[i].hasText = MLHintText(c).length > 0;
    }
    int k = MLHintPick(f, 3);
    // the field's slot: the drawn hint's own when it is a bottom label, else the footer's, else the teachable one's (its place stays at alpha 0)
    *slot = CGRectZero;
    int order[3] = { k == 0 || k == 1 ? k : 0, k == 1 ? 0 : 1, -1 };
    for (int j = 0; j < 2; j++) {
        UIView *c = order[j] >= 0 ? cands[order[j]] : nil;
        if ([c isKindOfClass:[UIView class]] && c.window && c.bounds.size.width > 1 && c.bounds.size.height > 1) { *slot = [cv convertRect:c.bounds fromView:c]; break; }
    }
    return k >= 0 ? cands[k] : nil;
}
static void MLFieldLookApply(void) {   // (the hint line: plain text, 12.4a)
    BOOL overOurs = MLPart(kMLPartBackground) && gBackdrop.image != nil;
    MLTextLook hl = MLHintLookFor(overOurs, UIAccessibilityDarkerSystemColorsEnabled(), MLLegibilityStyle(gHintLabel ?: MLCoverView()));
    gUser.fieldText.textColor = [UIColor colorWithWhite:hl.white alpha:hl.alpha];
    gUser.fieldText.layer.shadowColor = [UIColor colorWithWhite:hl.shadowWhite alpha:1].CGColor;
    gUser.fieldText.layer.shadowOpacity = (float)hl.shadowAlpha; gUser.fieldText.layer.shadowRadius = 4; gUser.fieldText.layer.shadowOffset = CGSizeZero;
}
// The mirror: iPadOS's words, language and visibility into our field, inside the same call as iPadOS's own change (an animation iPadOS runs
// around it animates ours too); our field drawn only while it carries a drawn hint; with it, iPadOS's view masked. Returns whether it shows.
static BOOL gFieldYield;
static BOOL MLFieldMirror(void) {
    UIView *h = gHintLabel;
    MLUserView *u = gUser;
    if (!u) return NO;
    NSString *t = h ? MLHintText(h) : nil;
    CGFloat a = MLHintAlpha(h);
    BOOL show = h && t.length && a > 0.01 && !gFieldOwned && !gFieldYield && !gFieldPaging && !u.hidden;
    if (show && !MLHintMask(h)) show = NO;   // (a mask of another's on it: iPadOS's line stays, ours does not draw)
    if (!show) { MLHintUnmaskViews(); u.field.hidden = YES; return NO; }   // (no hint of ours: every hint view of iPadOS's draws: one hint drawing, never none)
    if (![u.fieldText.text isEqualToString:t]) {
        u.fieldText.text = t;
        // (the line is as wide as its words: new words resize it around its centre at once, inside iPadOS's call; the place stays the layout's)
        CGFloat w = MIN(MLHintLineWidth([t sizeWithAttributes:@{ NSFontAttributeName: u.fieldText.font ?: [UIFont systemFontOfSize:12] }].width), MAX(2, u.bounds.size.width - 48));
        CGRect f = u.field.frame;
        if (fabs(f.size.width - w) >= 0.5) { u.field.frame = CGRectMake(round(CGRectGetMidX(f) - w / 2), f.origin.y, w, f.size.height); u.fieldText.frame = CGRectMake(0, 0, w, f.size.height); }
    }
    u.field.hidden = NO;
    u.field.alpha = MIN(1, a);
    return YES;
}
static void MLUserLayout(UIView *mainPage) {
    UIView *cv = MLCoverView();
    CSCoverSheetViewController *cs = gCS;
    MLModal md = { MLBoolCall(cs, @selector(isPasscodeLockVisible), NO), MLBoolCall(cs, @selector(isShowingTodayView), NO), gSw.pending,
                   MLBoolCall(cs, @selector(isShowingModalView), NO), !MLBoolCall(cs, @selector(isMainPageVisible), YES) };
    if (!cv || !MLPart(kMLPartUser) || !MLUserVisible(gM.lockFace, md)) { if (gUser) MLUserDrop(); return; }
    CGSize S = cv.bounds.size, scr = [UIScreen mainScreen].bounds.size;
    CGFloat side = MLPictureSide(scr), nameSize = MLNameSize(scr), nameH = MLNameLineH(nameSize), nameGap = MLNameGap(scr);
    CGFloat hintSize = MLHintSize(scr), hintH = MLHintLineH(hintSize);
    UIView *ff = MLIvar(cv, "_fixedFooterView"), *tm = MLIvar(cv, "_teachableMomentsContainerView");
    UIView *home = MLIvar(tm, "_homeAffordanceView"), *status = MLIvar(ff, "_statusTextView");
    CGRect slot;
    gHintLabel = MLHintPicked(cv, &slot);
    CGFloat fallback = MLUserBottom(S.height, 0, MLTopInScreen(home, cv), MLTopInScreen(status, cv), 0) + 12;
    NSString *name = MLShownName(&gS, [UIDevice currentDevice].name);
    if (!gUser) {
        gUser = [MLUserView new];
        gUser.userInteractionEnabled = NO;
        MLTagOurs(gUser.layer);
        gUser.picture = [UIImageView new]; gUser.name = [UILabel new];
        gUser.picture.isAccessibilityElement = NO; gUser.picture.accessibilityIgnoresInvertColors = YES;
        gUser.picture.layer.shadowColor = [UIColor blackColor].CGColor; gUser.picture.layer.shadowOpacity = 0.30f;
        gUser.picture.layer.shadowRadius = 10; gUser.picture.layer.shadowOffset = CGSizeMake(0, 3);
        gUser.name.textAlignment = NSTextAlignmentCenter;
        gUser.name.isAccessibilityElement = YES;
        gUser.field = [UIView new]; gUser.field.backgroundColor = [UIColor clearColor]; gUser.field.isAccessibilityElement = NO;
        gUser.fieldText = [UILabel new]; gUser.fieldText.textAlignment = NSTextAlignmentCenter; gUser.fieldText.isAccessibilityElement = NO;   // (VoiceOver reads iPadOS's own masked line)
        for (UIView *v in @[ gUser.picture, gUser.name, gUser.field, gUser.fieldText ]) MLTagOurs(v.layer);
        [gUser.field addSubview:gUser.fieldText];
        [gUser addSubview:gUser.picture]; [gUser addSubview:gUser.name]; [gUser addSubview:gUser.field];
    }
    // the hint line's size and place: iPadOS's hint slot, as wide as its words (Medium, Semibold with Bold Text)
    UIFont *hf = [UIFont systemFontOfSize:hintSize weight:UIAccessibilityIsBoldTextEnabled() ? UIFontWeightSemibold : UIFontWeightMedium];
    if (![gUser.fieldText.font isEqual:hf]) gUser.fieldText.font = hf;
    NSString *hintText = gHintLabel ? MLHintText(gHintLabel) : nil;
    CGFloat textW = hintText.length ? [hintText sizeWithAttributes:@{ NSFontAttributeName: hf }].width : 0;
    CGFloat fw = MIN(S.width - 48, MLHintLineWidth(textW));
    CGRect fieldR = MLHintRect(slot, S.width, fw, hintH, fallback, MLTopInScreen(home, cv));
    CGFloat listBottom = 0;
    UIView *mp = MLIvar(cv, "_mainPageView");
    for (UIView *x in [mp isKindOfClass:[UIView class]] ? mp.subviews : @[]) if (x != gUser) MLListBottomWalk(x, cv, &listBottom, 0);
    gListBottomUsed = listBottom;
    CGFloat topLimit = gClock.superview ? CGRectGetMaxY([cv convertRect:gClock.time.frame fromView:gClock]) : 0;
    CGFloat blockBottom = CGRectGetMinY(fieldR) - MLHintGap(scr, nameH, hintH);
    int mode = MLUserMode(blockBottom, listBottom, side, topLimit, nameH, nameGap);
    gUser.name.font = [UIFont systemFontOfSize:nameSize weight:UIAccessibilityIsBoldTextEnabled() ? UIFontWeightBold : UIFontWeightSemibold];
    if (![gUser.name.text isEqualToString:name]) gUser.name.text = name;
    CGFloat nw = ceil([gUser.name sizeThatFits:CGSizeMake(S.width, nameH)].width) + 2;
    CGRect widgets[4]; int nwid = MLWidgetFrames(cv, widgets, 4);
    mode = MLUserModeClear(S.width, blockBottom, mode, side, nw, nameH, nameGap, widgets, nwid);
    gFieldYield = MLFieldYields(fieldR, listBottom) || MLRectMeetsAny(fieldR, widgets, nwid);   // (the field yields last: 12.6)
    if (mode == kMLUserHidden && gFieldYield) { gUser.hidden = YES; MLFieldMirror(); return; }
    CGFloat d = mode == kMLUserWhole ? side : 56, h = mode == kMLUserHidden ? 0 : MLUserHeight(mode, side, nameH, nameGap);
    if (gUser.picture.bounds.size.width != d || !gUser.picture.image) gUser.picture.image = MLPictureImage(name, d);
    gUser.picture.hidden = mode == kMLUserNameOnly || mode == kMLUserHidden;
    gUser.name.hidden = mode == kMLUserHidden;
    MLTextLook look = MLTextLookFor(MLPart(kMLPartBackground) && gBackdrop.image != nil, MLLegibilityStyle(gHintLabel ?: cv));
    gUser.name.textColor = [UIColor colorWithWhite:look.white alpha:MLPart(kMLPartBackground) && gBackdrop.image ? 0.95 : MIN(1, look.alpha + 0.08)];
    gUser.name.layer.shadowColor = [UIColor colorWithWhite:look.shadowWhite alpha:1].CGColor;
    gUser.name.layer.shadowOpacity = (float)look.shadowAlpha; gUser.name.layer.shadowRadius = 4; gUser.name.layer.shadowOffset = CGSizeZero;
    if (gUser.superview != mainPage) [mainPage insertSubview:gUser atIndex:0];   // (under the list: its cards are never covered)
    CGFloat top = blockBottom - h;
    CGRect inCover = CGRectMake(0, top, S.width, CGRectGetMaxY(fieldR) - top);
    gUser.frame = [mainPage convertRect:inCover fromView:cv];
    CGFloat W = gUser.bounds.size.width;
    gUser.picture.frame = CGRectMake(round((W - d) / 2), 0, d, d);
    gUser.picture.layer.shadowPath = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, d, d)].CGPath;   // (no offscreen pass)
    gUser.name.frame = CGRectMake(round((W - nw) / 2), mode == kMLUserNameOnly ? 0 : d + (mode == kMLUserWhole ? nameGap : 8), nw, nameH);
    CGRect fr = CGRectOffset(fieldR, 0, -top);
    gUser.field.frame = fr;
    gUser.fieldText.frame = CGRectMake(0, 0, fr.size.width, fr.size.height);
    MLFieldLookApply();
    gUser.hidden = NO;
    MLFieldMirror();
}
// A change of any hint candidate (iPadOS's own call): the pick made again at once and the field mirrored inside that call
static BOOL MLIsHintCand(UIView *v) { return v && (v == gHintLabel || v == gHintCand0 || v == gHintCand1 || v == gHintCand2); }
static void MLHintChanged(UIView *v) {
    UIView *cv = MLCoverView();
    if (!gUser || !cv) return;
    if (v != gHintLabel) {
        CGRect slot;
        UIView *n = MLHintPicked(cv, &slot);
        if (n != gHintLabel) { gHintLabel = n; [MLIvar(cv, "_mainPageView") setNeedsLayout]; }   // (the field's place and width follow at the layout)
    }
    MLFieldMirror();
}
// the pages: off the main page our field is hidden and iPadOS's hint drawn where it stays (its containers do not slide); back at rest, mirrored
static void MLFieldFollowPages(CGFloat dx) {
    BOOL paging = dx != 0;
    if (paging == gFieldPaging) return;
    gFieldPaging = paging;
    MLFieldMirror();
}
// Another modification changing iPadOS's hint line (its labels' setters or the containers' call-to-action methods): our field stands down
// (12.6; Lynx on 15.6.1 hooks the footer's and the teachable container's). Read before our own hooks go in, and at each appearance for the
// containers' methods (never hooked by us).
static BOOL MLHintMethodsForeign(BOOL labelsToo) {
    struct { const char *cls, *sel; } w[] = { { "CSFixedFooterView", "_layoutCallToActionView" }, { "CSTeachableMomentsContainerView", "_addCallToActionLabel" },
        { "CSTeachableMomentsContainerView", "_layoutCallToActionLabel" }, { "SBUICallToActionLabel", "setText:" }, { "SBUICallToActionLabel", "setText:forLanguage:animated:" },
        { "SBUILegibilityLabel", "setString:" } };
    int n = labelsToo ? 6 : 3;
    for (int i = 0; i < n; i++) {
        Class c = objc_getClass(w[i].cls);
        Method m = c ? class_getInstanceMethod(c, sel_registerName(w[i].sel)) : NULL;
        const char *img = NULL;
        if (m && MLImpKind(&gTable, method_getImplementation(m), &img) == kMLKindOther) { MLLog(@"field: %s %s is %s's: the field stands down", w[i].cls, w[i].sel, img ?: "?"); return YES; }
    }
    return NO;
}

// ---------------------------------------------------------------------------------------------------------------- Wi-Fi and battery (A20, 2.6)
@interface SBWiFiManager : NSObject
+ (instancetype)sharedInstance;
- (int)signalStrengthBars;
- (BOOL)isAssociated;
@end
static UIView *gPair;
static UIImageView *gPairWiFi, *gPairBattery;
static id gBattObs1, gBattObs2;
static UIImage *MLWiFiImage(int bars, BOOL joined) {   // macOS's glyph (Lock9's): three arcs over a dot, the arcs above the strength dimmed
    CGFloat W = 17, H = 20;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(W, H)];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *rc) {
        CGPoint o = CGPointMake(W / 2, 15.5);
        for (int i = 0; i < 4; i++) {
            BOOL lit = joined && (i == 0 || i <= bars);
            [[UIColor colorWithWhite:1 alpha:lit ? 1.0 : 0.35] set];
            if (i == 0) { [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(o.x - 1.6, o.y - 1.6, 3.2, 3.2)] fill]; continue; }
            UIBezierPath *p = [UIBezierPath bezierPathWithArcCenter:o radius:1.6 + 3.4 * i startAngle:-M_PI * 0.75 endAngle:-M_PI * 0.25 clockwise:YES];
            p.lineWidth = 1.9; p.lineCapStyle = kCGLineCapRound; [p stroke];
        }
    }];
}
static UIImage *MLBatteryImage(void) {   // the level and the bolt from UIDevice (observed only while the face shows)
    UIDevice *dev = [UIDevice currentDevice];
    float lv = dev.batteryLevel; int level = lv >= 0 ? (int)lroundf(lv * 100) : 100;
    BOOL charging = dev.batteryState == UIDeviceBatteryStateCharging || dev.batteryState == UIDeviceBatteryStateFull;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(29, 20)];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *rc) {
        [[UIColor colorWithWhite:1 alpha:0.5] set];
        UIBezierPath *o = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.5, 4.5, 24, 11) cornerRadius:3.2]; o.lineWidth = 1; [o stroke];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(25.5, 8, 1.8, 4) cornerRadius:0.9] fill];
        [[UIColor whiteColor] set];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(2, 6, MAX(1.5, round(21 * level / 100.0)), 8) cornerRadius:1.8] fill];
        if (charging) {
            UIBezierPath *b = [UIBezierPath bezierPath];
            [b moveToPoint:CGPointMake(14, 5)]; [b addLineToPoint:CGPointMake(9.5, 11)]; [b addLineToPoint:CGPointMake(12.5, 11)];
            [b addLineToPoint:CGPointMake(11, 15)]; [b addLineToPoint:CGPointMake(15.5, 9)]; [b addLineToPoint:CGPointMake(12.5, 9)]; [b closePath];
            [[UIColor blackColor] setStroke]; b.lineWidth = 1.2; [b stroke]; [[UIColor whiteColor] setFill]; [b fill];
        }
    }];
}
static void MLPairRefresh(void) {
    SBWiFiManager *w = [objc_getClass("SBWiFiManager") respondsToSelector:@selector(sharedInstance)] ? [objc_getClass("SBWiFiManager") sharedInstance] : nil;
    BOOL joined = [w respondsToSelector:@selector(isAssociated)] ? [w isAssociated] : YES;
    int bars = [w respondsToSelector:@selector(signalStrengthBars)] ? [w signalStrengthBars] : 3;
    gPairWiFi.image = MLWiFiImage(bars, joined);
    gPairBattery.image = MLBatteryImage();
}
static void MLPairWatch(BOOL on) {
    UIDevice *dev = [UIDevice currentDevice];
    if (on && !gBattObs1) {
        if (!dev.batteryMonitoringEnabled) dev.batteryMonitoringEnabled = YES;   // (left on: switching it off in SpringBoard stops iPadOS's own battery feed, BatteryMenu.h / #15)
        void (^b)(NSNotification *) = ^(NSNotification *n) { if (gPair) MLPairRefresh(); };
        gBattObs1 = [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceBatteryLevelDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:b];
        gBattObs2 = [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceBatteryStateDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:b];
    } else if (!on && gBattObs1) {
        [[NSNotificationCenter defaultCenter] removeObserver:gBattObs1]; [[NSNotificationCenter defaultCenter] removeObserver:gBattObs2];
        gBattObs1 = gBattObs2 = nil;
    }
}
static CGFloat gPairDx;   // (the pair's shift with the Cover Sheet's pages)
static void MLPairDrop(void) { [gPair removeFromSuperview]; gPair = nil; gPairWiFi = gPairBattery = nil; gPairDx = 0; MLPairWatch(NO); }
static void MLStatusSoon(void);
static BOOL MLPairBlocked(UIView *cv, CGRect r) {   // (another modification's view in that top-right band: the part is theirs, 3.4 2)
    UIView *tm = MLIvar(cv, "_teachableMomentsContainerView");
    for (UIView *c in @[ cv, [tm isKindOfClass:[UIView class]] ? tm : cv ]) {
        for (UIView *s in c.subviews) {
            if (s == gPair || MLIsTaggedOurs(s.layer) || s.hidden || s.alpha < 0.01) continue;
            if (MLClassKind(&gTable, object_getClass(s), NULL) != kMLKindOther) continue;
            if (CGRectIntersectsRect([cv convertRect:s.bounds fromView:s], r)) return YES;
        }
    }
    return NO;
}
// ---- 12.1: exactly one status drawing at the top right (common/LockBarHide.h) ----
// Read afresh at each Cover Sheet layout pass, at the wake, at Hide Status Bar on Lock Screen's note (and a main-queue turn later), and a turn
// after each request SpringBoard's Lock Screen status bar controller gets while the face shows (its bar lives in another window: no Cover Sheet
// layout pass follows its changes). Our pair only where no bar is drawn because WE hid it, where iPadOS's page wants a bar, not over Today.
static BOOL gStatusLogged;   // ("a status bar is drawn" logged once per appearance)
static int gStatusSoon;      // (a re-read is queued)
// iPadOS's own per-page wish: the Cover Sheet's active appearance's status bar component (type 2, as -_updateStatusBar reads it on 18.5);
// where it cannot be read, the main page (not the camera page, not Today)
static BOOL MLPageWantsBar(CSCoverSheetViewController *cs) {
    id app = MLObjCall(cs, NSSelectorFromString(@"activeAppearance"));
    SEL cf = NSSelectorFromString(@"componentForType:identifier:");
    Method m = app ? class_getInstanceMethod(object_getClass(app), cf) : NULL;
    if (m && method_getNumberOfArguments(m) == 4 && MLArgInt(m, 2)) {
        id comp = nil;
        @try { comp = ((id (*)(id, SEL, long long, id))objc_msgSend)(app, cf, 2, nil); } @catch (NSException *e) { comp = nil; }
        SEL al = NSSelectorFromString(@"alpha"), hid = NSSelectorFromString(@"isHidden");
        Class sbc = objc_getClass("CSStatusBarComponent");   // (type 2 read on 18.5 only: the component's class confirms it, review finding 9)
        if (comp && sbc && [comp isKindOfClass:sbc] && [comp respondsToSelector:al] && [comp respondsToSelector:hid]) {
            Method am = class_getInstanceMethod(object_getClass(comp), al);
            const char *e = am ? method_getTypeEncoding(am) : NULL;
            double a = e && e[0] == 'd' ? ((double (*)(id, SEL))objc_msgSend)(comp, al) : 1;
            return !MLBoolCall(comp, hid, NO) && a > 0.01;
        }
    }
    return MLBoolCall(cs, @selector(isMainPageVisible), YES);
}
static void MLStatusDecide(const char *why) {
    CSCoverSheetViewController *cs = gCS;
    UIView *cv = MLCoverView();
    BOOL partOn = MLPart(kMLPartPair) && cv.window && !gDismissing;
    LBHBar b = cv.window ? LBHVisibleBar(cs) : (LBHBar){0};
    // Q27: iPadOS's own bar drawn while the part is on (not our menu bar's copy, which already shows the Mac's icons): hidden through
    // SpringBoard's own call with our own reason; the pair then waits for the next read (a turn later), which sees what is drawn
    BOOL hidByLSB = objc_getAssociatedObject(cs, LBH_FLAG_KEY) != nil, today = MLBoolCall(cs, @selector(isShowingTodayView), NO), page = MLPageWantsBar(cs);
    BOOL want = LBHPartHides(partOn, b.drawn, b.ourMenuBar, LBHReasonIn(), hidByLSB, page, today);
    if (want && !LBHReasonIn()) {
        int r = LBHSet(cs, YES);
        if (r == 1) { MLLog(@"iPadOS's own Lock Screen bar asked hidden for our Wi-Fi and Battery (%s)", why); MLStatusSoon(); }
        else if (r == -2 && !gStatusLogged) MLLog(@"no SpringBoard call for the Lock Screen's bar on this iPadOS: our Wi-Fi and Battery stays off while a bar is drawn");
    } else if (!want && LBHReasonIn()) { LBHSet(cs, NO); MLLog(@"iPadOS's own Lock Screen bar given back (%s)", why); }
    LBHPairFacts f = { partOn, b.drawn, hidByLSB, LBHReasonIn(), page, today };
    BOOL shows = LBHPairShows(f);
    if (partOn && b.drawn && !gStatusLogged) {
        gStatusLogged = YES;
        MLLog(@"a status bar is drawn (%s%s): our Wi-Fi and Battery stays off (%s)", b.what, b.ourMenuBar ? ", our menu bar's copy" : "", why);
    }
    gStatusBottom = b.drawn || shows ? 30 : 0;
    if (shows != gPairShows) { gPairShows = shows; MLLog(@"Wi-Fi and Battery %s (%s)", shows ? "shown" : "off", why); }
}
static void MLStatusSoon(void) {
    if (gStatusSoon > 1) return;
    gStatusSoon++;
    dispatch_async(dispatch_get_main_queue(), ^{
        gStatusSoon--;
        UIView *cv = MLCoverView();
        if (!gFaceUp || !cv.window) return;
        BOOL was = gPairShows;
        MLStatusDecide("read again");
        if (was != gPairShows) [cv setNeedsLayout];
    });
}
// the pair follows the Cover Sheet's pages (as LockStatusBar.x moves the Control Center grabber), exactly back at rest on the main page
static void MLFieldFollowPages(CGFloat dx);
static void MLPairFollowPages(CSCoverSheetViewController *cs, UIScrollView *sv) {
    SEL mainSel = NSSelectorFromString(@"_indexOfMainPage");
    CGFloat w = sv.bounds.size.width, dx = 0;
    if (w > 1 && [cs respondsToSelector:mainSel] && [sv isKindOfClass:[UIScrollView class]]) {
        NSUInteger main = ((NSUInteger (*)(id, SEL))objc_msgSend)(cs, mainSel);
        dx = main * w - sv.contentOffset.x;
        if (fabs(dx) < 0.5 || fabs(dx) > w * 1.05) dx = 0;
    }
    MLFieldFollowPages(dx);
    if (dx == gPairDx || !gPair) return;
    gPairDx = dx;
    gPair.transform = dx == 0 ? CGAffineTransformIdentity : CGAffineTransformMakeTranslation(dx, 0);
}
static void MLPairLayout(UIView *cv) {
    if (!gPairShows) { if (gPair) MLPairDrop(); return; }
    if (!gPair) {
        gPair = [UIView new]; gPair.userInteractionEnabled = NO; MLTagOurs(gPair.layer);
        gPairWiFi = [UIImageView new]; gPairBattery = [UIImageView new];
        MLTagOurs(gPairWiFi.layer); MLTagOurs(gPairBattery.layer);
        [gPair addSubview:gPairWiFi]; [gPair addSubview:gPairBattery];
        gPair.isAccessibilityElement = NO;
        MLPairRefresh(); MLPairWatch(YES);
    }
    CGSize ws = CGSizeMake(17, 20), bs = CGSizeMake(29, 20);
    CGRect widgets[4]; int n = MLWidgetFrames(cv, widgets, 4);
    CGRect r = MLPairFrame(cv.bounds.size.width, 30, MLPairSize(ws, bs), widgets, n);
    if (CGRectIsEmpty(r)) { gPair.hidden = YES; return; }
    UIView *above = MLIvar(cv, "_teachableMomentsContainerView");   // (under the Control Center grabber's view: its touches stay iPadOS's)
    if (gPair.superview != cv) { if ([above isKindOfClass:[UIView class]] && above.superview == cv) [cv insertSubview:gPair belowSubview:above]; else [cv addSubview:gPair]; }
    gPair.bounds = CGRectMake(0, 0, r.size.width, r.size.height); gPair.center = CGPointMake(CGRectGetMidX(r), CGRectGetMidY(r));   // (its transform follows the pages)
    gPair.hidden = NO;
    CGRect wr, br;
    MLPairPlaces(ws, bs, &wr, &br);   // (macOS's order, 12.4a: Wi-Fi rightmost, the battery to its left)
    gPairWiFi.frame = wr; gPairBattery.frame = br;
}

// ---------------------------------------------------------------------------------------------------------------- the band (A22)
// B0 (15.6.1, 17.5.1): with the Lock Screen's bar hidden by our Hide Status Bar on Lock Screen, its legibility band (two 450 x 75 shadow pictures
// at the top, SBFStatusBarLegibilityView) stays: dropped while our pair draws there, given back after.
static void MLBandLayout(UIView *cv) {
    UIView *band = MLIvar(cv, "_statusBarLegibilityView");
    if (![band isKindOfClass:[UIView class]]) return;
    MLHideIn(&gBandHidden, band, gPairShows);   // (rev 2: only while our pair draws, 12.1)
}

// ---------------------------------------------------------------------------------------------------------------- appearance and layout
static void MLLayoutCoverParts(UIView *cv) {
    // the backdrop: under everything of the Cover Sheet's view (below its background and dim views), over the wallpaper's window
    if (MLPart(kMLPartBackground) && gBackdropImage) {
        if (!gBackdrop) {
            gBackdrop = [UIImageView new];
            gBackdrop.contentMode = UIViewContentModeScaleAspectFill; gBackdrop.clipsToBounds = YES;
            gBackdrop.userInteractionEnabled = NO; gBackdrop.isAccessibilityElement = NO; gBackdrop.accessibilityIgnoresInvertColors = YES;
            gBackdrop.layer.minificationFilter = kCAFilterLinear; gBackdrop.layer.magnificationFilter = kCAFilterLinear;
            MLTagOurs(gBackdrop.layer);
        }
        if (gBackdrop.image != gBackdropImage) gBackdrop.image = gBackdropImage;
        if (gBackdrop.superview != cv) [cv insertSubview:gBackdrop atIndex:0];
        else if (cv.subviews.firstObject != gBackdrop) [cv sendSubviewToBack:gBackdrop];
        gBackdrop.frame = cv.bounds;
        BOOL wasHidden = gFloatHidden;
        MLFloatLayer(YES);
        if (!wasHidden && gFloatHidden) MLDepthCheckSoon();
    } else if (gBackdrop) MLBackdropDrop();
    MLStatusDecide("a layout pass");
    MLPairLayout(cv);
    MLBandLayout(cv);
}
static void MLDropAll(NSString *why) {
    BOOL had = gBackdrop || gClock || gUser || gPair || gCards.count || gHiddenByUs.count || gBandHidden.count || LBHReasonIn();
    MLBackdropDrop(); MLClockDrop(); MLUserDrop(); MLPairDrop(); MLCardsGiveBack(); MLGiveBackHidden(); MLGiveBackBand(); MLHintUnmaskAll();
    if (LBHReasonIn()) LBHSet(gCS, NO);   // (iPadOS's own Lock Screen bar back: Q27's give-back)
    gPairShows = NO; gStatusBottom = 0;
    gBackdropImage = nil; gBackdropKeyShown = nil;
    gDateFmt = nil; gTimeFmt = nil;
    if (had) MLLog(@"face dropped (%@)", why);
}
// A part no longer in force (switched off live, standing down): its give-backs at once, the others untouched (2.3)
static void MLGiveBackParts(void) {
    if (!MLPart(kMLPartBackground) && gBackdrop) MLBackdropDrop();
    if (!MLPart(kMLPartClock) && (gClock || gHiddenByUs.count)) MLClockDrop();
    if (!MLPart(kMLPartCards) && gCards.count) MLCardsGiveBack();
    if (!MLPart(kMLPartUser) && gUser) MLUserDrop();
    if (!MLPart(kMLPartPair) && (gPair || LBHReasonIn())) { gPairShows = NO; MLPairDrop(); if (LBHReasonIn()) LBHSet(gCS, NO); }
    if (!gPairShows && gBandHidden.count) MLGiveBackBand();
}
static void MLRelayoutAll(void) {
    UIView *cv = MLCoverView();
    if (!cv.window) return;
    MLGiveBackParts();
    [cv setNeedsLayout];
    UIView *dv = MLIvar(cv, "_dateView"), *mp = MLIvar(cv, "_mainPageView");
    [dv setNeedsLayout]; for (UIView *s in dv.subviews) [s setNeedsLayout];
    [mp setNeedsLayout];
    if (MLPart(kMLPartCards)) {   // (platters lay out again: each takes the look)
        NSMutableArray *st = [NSMutableArray arrayWithObject:mp ?: cv];
        while (st.count) { UIView *v = st.lastObject; [st removeLastObject]; if ([NSStringFromClass([v class]) isEqualToString:@"PLPlatterView"]) [v setNeedsLayout]; else [st addObjectsFromArray:v.subviews]; }
    }
}
// the Cover Sheet's view in a shown window on the iPad's own screen
static BOOL MLInMainWindow(CSCoverSheetViewController *cs) {
    UIView *v = cs.isViewLoaded ? cs.view : nil;
    return v.window && !v.window.hidden && v.window.screen == [UIScreen mainScreen];
}
static BOOL MLInstallWanted(void);
static UIView *MLFindClass(UIView *v, NSString *name, int depth) {
    if ([NSStringFromClass([v class]) isEqualToString:name]) return v;
    if (depth <= 0) return nil;
    for (UIView *x in v.subviews) { UIView *f = MLFindClass(x, name, depth - 1); if (f) return f; }
    return nil;
}
static int MLDismissedRead(void) {   // iPadOS's lock-or-pull read (-1: missing)
    id pm = MLPresentationManager();
    if (![pm respondsToSelector:@selector(hasBeenDismissedSinceKeybagLock)]) return -1;
    return MLBoolCall(pm, @selector(hasBeenDismissedSinceKeybagLock), NO) ? 1 : 0;
}
static id gBarNoteObs;
static void MLBarNote(BOOL on) {   // (Hide Status Bar on Lock Screen's in-process note, only while the face shows)
    if (on && !gBarNoteObs) gBarNoteObs = [[NSNotificationCenter defaultCenter] addObserverForName:LBH_CHANGED_NOTE object:nil queue:nil usingBlock:^(NSNotification *n) {
        if (!gFaceUp) return;
        MLStatusDecide("Hide Status Bar on Lock Screen changed the bar"); MLStatusSoon();
        UIView *cv = MLCoverView(); [cv setNeedsLayout];
    }];
    else if (!on && gBarNoteObs) { [[NSNotificationCenter defaultCenter] removeObserver:gBarNoteObs]; gBarNoteObs = nil; }
}
// The machine's part of an appearance: once (12.2 (1)); the Cover Sheet's window may still be hidden here at a pull (B0 reads it).
static void MLAppearMachine(CSCoverSheetViewController *cs) {
    gCS = cs;
    gAppearing = YES; gDepthDown = NO; gStatusLogged = NO;
    int dismissed = MLDismissedRead();
    MLOnAppear(&gM, dismissed);
#if DEBUG
    MLLog(@"appearance: the Cover Sheet's window %@, lock face %d (dismissed since lock %d)", !cs.isViewLoaded || !cs.view.window ? @"not yet there" : cs.view.window.hidden ? @"hidden" : @"shown", gM.lockFace, dismissed);
#endif
}
// The face's part: repeatable until the face is up, from -viewWillAppear:, the view's first layout in its window or -didMoveToWindow, and
// -viewDidAppear: as the last chance (18.5 10:23: the first lock after a switch-on had no face for the whole appearance).
static BOOL MLFaceTry(CSCoverSheetViewController *cs, const char *where) {
    if (gSw.pending && gOS >= 17) MLSwitcherRead(&gSw, MLBoolCall(cs, @selector(_isPresentingPosterSwitcher), NO));
    if (!MLFaceRetry(gS.enabled, gAppearing, gFaceUp, gDismissing, gSw.pending, MLInMainWindow(cs))) return gFaceUp;
    gCS = cs;
    gDestra = MLDestraInForce();
    MLEffectiveBackground();
    gFaceUp = YES;
    gChecked = NO;
    MLCheckAll(NO);
    gPadlock = MLPart(kMLPartClock) ? MLFindClass(cs.view, @"SBUIProudLockIconView", 4) : nil;
    if (MLPart(kMLPartUser)) gFieldOwned = gFieldOwned || MLHintMethodsForeign(NO);
    MLBackdropPrepare(cs.view);
    MLBarNote(YES);
    MLLog(@"appear (%s): lock face %d, parts clock %d background %d cards %d user %d pair %d", where, gM.lockFace, MLPart(0), MLPart(1), MLPart(2), MLPart(3), MLPart(4));
    MLStatusDecide("the appearance");
    MLRelayoutAll();
    MLStatusSoon();
    return YES;
}
static void MLGone(void) {
    gDismissing = NO; gAppearing = NO;
    MLOnGone(&gM);
    MLSwitcherEnd(&gSw);
    gFaceUp = NO; gChecked = NO;
    MLBarNote(NO);
    MLDropAll(@"the Cover Sheet is gone");
}

// A wake: iPadOS's read again; a poster switcher still up starts its state again (the face never forms over it); the face if not up; a changed
// pair decision laid out at once (review finding 6).
static void MLWake(CSCoverSheetViewController *cs) {
    BOOL was = gM.lockFace; MLOnScreenOn(&gM, MLDismissedRead());
    if (gOS >= 17 && MLBoolCall(cs, @selector(_isPresentingPosterSwitcher), NO)) { MLSwitcherBegin(&gSw); MLSwitcherRead(&gSw, YES); }
    if (!gFaceUp) { MLFaceTry(cs, "the wake"); return; }
    BOOL pairWas = gPairShows;
    MLStatusDecide("the wake");
    if (gM.lockFace != was) MLRelayoutAll();
    else if (pairWas != gPairShows) [MLCoverView() setNeedsLayout];
}

// ---------------------------------------------------------------------------------------------------------------- hooks
// (each group goes in only where its methods have the types its declarations compile to: common/HookTypes.h. The tables were read on 15.6.1,
//  16.7.7, 17.5.1 and 18.5 (a method a version does not have is left out of the check, as Logos hooks nothing for it); tools/test-hooktypes.sh
//  checks each table against its group. A version where one differs keeps the group out: the core's, Mac Lock Screen; a part's, that part)
static BOOL MLTypesOK(const MSBDHookSig *sigs, size_t n, const char *group) {
    NSString *wrong = nil;
    if (MSBDHookGroupTypesOK(sigs, n, "Mac Lock Screen", group, &wrong)) return YES;
    MLLog(@"%s not hooked: %@", group, wrong);
    return NO;
}
#define ML_TYPES_OK(G) MLTypesOK(kHookSigs_##G, sizeof(kHookSigs_##G) / sizeof(kHookSigs_##G[0]), #G)
static const MSBDHookSig kHookSigs_MLCore[] = {
    {"CSCoverSheetViewController", "viewWillAppear:", "v@:B"},
    {"CSCoverSheetViewController", "viewDidAppear:", "v@:B"},
    {"CSCoverSheetViewController", "viewWillDisappear:", "v@:B"},
    {"CSCoverSheetViewController", "viewDidDisappear:", "v@:B"},
    {"CSCoverSheetViewController", "setInScreenOffMode:", "v@:B"},
    {"CSCoverSheetViewController", "setInScreenOffMode:forAutoUnlock:fromUnlockSource:", "v@:BBi"},
    {"CSCoverSheetView", "layoutSubviews", "v@:"},
    {"CSCoverSheetView", "didMoveToWindow", "v@:"},
    {"SBLockScreenManager", "lockUIFromSource:withOptions:", "v@:i@"},
    {"SBLockScreenManager", "lockUIFromSource:withOptions:completion:", "v@:i@@"},
};
%group MLCore
%hook CSCoverSheetViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    gDismissing = NO;
    if (!gS.enabled) return;
    MLReadPrefs();   // (our settings and the Desktop Picture as they are now: nothing watches them at rest)
    if (!gS.enabled) return;
    MLAppearMachine(self);
    MLFaceTry(self, "viewWillAppear");
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!gFaceUp) {   // (the last chance: the view has its window by now)
        if (MLFaceTry(self, "viewDidAppear")) MLLog(@"the face came late: at viewDidAppear");
        return;
    }
    MLCheckAll(YES);   // (views a tweak adds in its own viewDidAppear or layout)
    if (MLPart(kMLPartUser) && !gFieldOwned) gFieldOwned = MLHintMethodsForeign(NO);
    MLRelayoutAll();
}
- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    gDismissing = YES;
    MLFloatLayer(NO);   // (the depth effect back at the start of the dismissal, and kept back until it is gone: review finding 12)
    MLHintUnmaskAll(); if (gUser) gUser.field.hidden = YES;   // (iPadOS's hint line back at once)
    gPairShows = NO; MLPairDrop(); MLGiveBackBand();   // (whoever hid the bar: never a frame of our pair over a bar given back, review finding 7)
    if (LBHReasonIn()) LBHSet(self, NO);   // (iPadOS's own bar at the dismissal's start, Q27)
}
- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    MLGone();
}
- (void)setInScreenOffMode:(BOOL)off {
    %orig;
    if (off) { MLOnScreenOff(&gM); MLSwitcherEnd(&gSw); return; }
    MLWake(self);
}
- (void)setInScreenOffMode:(BOOL)off forAutoUnlock:(BOOL)autoUnlock fromUnlockSource:(int)source {
    %orig;
    if (off) { MLOnScreenOff(&gM); MLSwitcherEnd(&gSw); return; }
    MLWake(self);
}
%end
%hook CSCoverSheetView
- (void)layoutSubviews {
    %orig;
    if (!gFaceUp) {   // (the first layout in its window forms the face before the first frame: 12.2 (1))
        CSCoverSheetViewController *cs = gCS;
        if (gAppearing && gS.enabled && cs.isViewLoaded && cs.view == (UIView *)self) MLFaceTry(cs, "the first layout");
        if (!gFaceUp) return;
    }
    if (!self.window) { MLDropAll(@"the Cover Sheet left its window"); gFaceUp = NO; return; }
    if (gSw.pending) return;
    MLLayoutCoverParts(self);
}
- (void)didMoveToWindow {
    %orig;
    CSCoverSheetViewController *cs = gCS;
    if (!gFaceUp && gAppearing && gS.enabled && self.window && cs.isViewLoaded && cs.view == (UIView *)self) MLFaceTry(cs, "didMoveToWindow");
}
%end
%hook SBLockScreenManager
- (void)lockUIFromSource:(int)source withOptions:(id)options {
    BOOL was = gM.lockFace;
    MLOnLock(&gM);
    %orig;
    if (gFaceUp && gM.lockFace != was) MLRelayoutAll();   // (a pull, then Lock: the picture and name come now: review finding 11)
}
- (void)lockUIFromSource:(int)source withOptions:(id)options completion:(id)completion {
    BOOL was = gM.lockFace;
    MLOnLock(&gM);
    %orig;
    if (gFaceUp && gM.lockFace != was) MLRelayoutAll();
}
%end
%end

// (12.1) SpringBoard's Lock Screen status bar requests: what is drawn at the top right is read again a turn later while the face shows; and
// the pair follows the Cover Sheet's pages. Each where its methods exist (15.6.1-18.5).
// The alpha is an NSNumber, the style an integer, the settings an object ("v40@0:8@16q24@32" on 15.6.1-18.5): declared as a double it was read
// from the wrong register (a 1.8.9 test build's Lock Screen crash, LockStatusBar.x). Neither hook reads its arguments; %orig passes them on.
static const MSBDHookSig kHookSigs_MLStatusWatch[] = {
    {"SBDashBoardStatusBarController", "setStatusBarAlpha:style:legibilitySettings:", "v@:@q@"},
    {"SBDashBoardStatusBarController", "setStatusBarHidden:forReason:", "v@:B@"},
};
%group MLStatusWatch
%hook SBDashBoardStatusBarController
- (void)setStatusBarAlpha:(id)alpha style:(long long)style legibilitySettings:(id)ls {
    %orig;
    if (gFaceUp && MLPart(kMLPartPair)) MLStatusSoon();
}
- (void)setStatusBarHidden:(BOOL)hidden forReason:(id)reason {
    %orig;
    if (gFaceUp && MLPart(kMLPartPair)) MLStatusSoon();
}
%end
%end
static const MSBDHookSig kHookSigs_MLPages[] = {
    {"CSCoverSheetViewController", "scrollablePageViewController:scrollViewDidScroll:", "v@:@@"},
};
%group MLPages
%hook CSCoverSheetViewController
- (void)scrollablePageViewController:(id)pvc scrollViewDidScroll:(UIScrollView *)sv {
    %orig;
    if (gPair || gUser) MLPairFollowPages(self, sv);
}
%end
%end

// (17/18) the poster switcher: our face goes at the START of its transition (it never zooms into the gallery card); a bounded state (12.2 (2))
static const MSBDHookSig kHookSigs_MLSwitcher[] = {
    {"CSCoverSheetViewController", "_prepareForPosterSwitcherPresentation", "v@:"},
    {"CSCoverSheetViewController", "_cleanupPosterSwitcherPresentationForCompleted:withActivatingTouches:", "v@:B@"},
};
%group MLSwitcher
%hook CSCoverSheetViewController
- (void)_prepareForPosterSwitcherPresentation {
    MLSwitcherBegin(&gSw);
    gFaceUp = NO;
    MLDropAll(@"the poster switcher comes");
    %orig;
    MLSwitcherRead(&gSw, MLBoolCall(self, @selector(_isPresentingPosterSwitcher), NO));
#if DEBUG
    MLLog(@"poster switcher: presenting %d at its prepare", MLBoolCall(self, @selector(_isPresentingPosterSwitcher), NO));
#endif
}
- (void)_cleanupPosterSwitcherPresentationForCompleted:(BOOL)completed withActivatingTouches:(id)touches {
    %orig;
    MLSwitcherCleanup(&gSw, MLBoolCall(self, @selector(_isPresentingPosterSwitcher), NO));
    if (!gSw.pending) MLFaceTry(self, "the poster switcher has gone");
}
%end
%end

static const MSBDHookSig kHookSigs_MLClock15[] = {
    {"SBFLockScreenDateView", "layoutSubviews", "v@:"},
    {"SBFLockScreenDateView", "setDate:", "v@:@"},
    {"SBFLockScreenDateView", "setCustomSubtitleView:", "v@:@"},
    {"SBFLockScreenDateView", "_updateLabelAlpha", "v@:"},
};
%group MLClock15
%hook SBFLockScreenDateView
- (void)layoutSubviews {
    %orig;
    if (gFaceUp || gClock) MLClockLayout15(self);
}
- (void)setDate:(NSDate *)date {
    %orig;
    if (gClock) [self setNeedsLayout];   // (iPadOS's own minute / midnight / wake update drives ours)
}
- (void)setCustomSubtitleView:(UIView *)view {   // (an alternate line coming or going: ours follows, review finding 2)
    %orig;
    if (gFaceUp || gClock) [self setNeedsLayout];
}
- (void)_updateLabelAlpha {
    %orig;
    if (gFaceUp || gClock) [self setNeedsLayout];
}
%end
%end

// (MLClock17: the prominent display's clock, installed wherever it draws iPadOS's clock: 16.7.7, 17.5.1, 18.5; MLClockPath)
static const MSBDHookSig kHookSigs_MLClock17[] = {
    {"CSProminentDisplayView", "layoutSubviews", "v@:"},
    {"CSProminentDisplayView", "setDisplayDate:", "v@:@"},
    {"CSProminentTimeView", "setDate:", "v@:@"},
};
%group MLClock17
%hook CSProminentDisplayView
- (void)layoutSubviews {
    %orig;
    if (gFaceUp || gClock) MLClockLayout17(self);
}
- (void)setDisplayDate:(NSDate *)date {
    %orig;
    if (gClock) [self setNeedsLayout];
}
%end
%hook CSProminentTimeView
- (void)setDate:(NSDate *)date {   // (iPadOS's minute may reach the time view directly: review finding 6)
    %orig;
    if (!gClock) return;
    for (UIView *v = ((UIView *)self).superview; v; v = v.superview) if ([NSStringFromClass([v class]) isEqualToString:@"CSProminentDisplayView"]) { [v setNeedsLayout]; break; }
}
%end
%end

static const MSBDHookSig kHookSigs_MLCards[] = {
    {"PLPlatterView", "layoutSubviews", "v@:"},
};
%group MLCards
%hook PLPlatterView
- (void)layoutSubviews {
    %orig;
    if (gFaceUp || gCards.count) MLCardLayout(self);
}
%end
%end

static const MSBDHookSig kHookSigs_MLUser[] = {
    {"CSMainPageView", "layoutSubviews", "v@:"},
    {"NCNotificationListView", "layoutSubviews", "v@:"},
};
%group MLUser
%hook CSMainPageView
- (void)layoutSubviews {
    %orig;
    if (gFaceUp || gUser) MLUserLayout(self);
}
%end
// a card arriving or going lays out iPadOS's list, not always the main page: the block is placed again when the list's lowest content moved
%hook NCNotificationListView
- (void)layoutSubviews {
    %orig;
    if (!gUser || !gFaceUp) return;
    UIView *cv = MLCoverView(), *mp = MLIvar(cv, "_mainPageView");
    if ([NSStringFromClass([((UIView *)self).superview class]) isEqualToString:@"NCNotificationListView"]) return;   // (the outermost list view only: review finding 14)
    if (![mp isKindOfClass:[UIView class]] || ![(UIView *)self isDescendantOfView:mp]) return;
    CGFloat lb = 0;
    for (UIView *x in mp.subviews) if (x != gUser) MLListBottomWalk(x, cv, &lb, 0);
    if (fabs(lb - gListBottomUsed) > 1) [mp setNeedsLayout];
}
%end
%end
// iPadOS's hint views: our field follows each change inside iPadOS's own call (12.6). Only the view mirrored now acts; the others pass straight on.
static const MSBDHookSig kHookSigs_MLHint[] = {
    {"SBUICallToActionLabel", "setText:", "v@:@"},
    {"SBUICallToActionLabel", "setText:forLanguage:animated:", "v@:@@B"},
    {"SBUICallToActionLabel", "setVisible:animated:", "v@:BB"},
    {"SBUICallToActionLabel", "setAlpha:", "v@:d"},
    {"SBUICallToActionLabel", "setHidden:", "v@:B"},
    {"SBUILegibilityLabel", "setString:", "v@:@"},
    {"SBUILegibilityLabel", "setAlpha:", "v@:d"},
    {"SBUILegibilityLabel", "setHidden:", "v@:B"},
};
%group MLHint
%hook SBUICallToActionLabel
- (void)setText:(NSString *)text {
    %orig;
    if (gUser && MLIsHintCand((UIView *)self)) MLHintChanged((UIView *)self);
}
- (void)setText:(NSString *)text forLanguage:(id)language animated:(BOOL)animated {
    %orig;
    if (gUser && MLIsHintCand((UIView *)self)) MLHintChanged((UIView *)self);
}
- (void)setVisible:(BOOL)visible animated:(BOOL)animated {
    %orig;
    if (gUser && MLIsHintCand((UIView *)self)) MLHintChanged((UIView *)self);
}
- (void)setAlpha:(CGFloat)alpha {
    %orig;
    if (gUser && MLIsHintCand((UIView *)self)) MLHintChanged((UIView *)self);
}
- (void)setHidden:(BOOL)hidden {
    %orig;
    if (gUser && MLIsHintCand((UIView *)self)) MLHintChanged((UIView *)self);
}
%end
%hook SBUILegibilityLabel
- (void)setString:(NSString *)string {
    %orig;
    if (gUser && MLIsHintCand((UIView *)self)) MLHintChanged((UIView *)self);
}
- (void)setAlpha:(CGFloat)alpha {
    %orig;
    if (gUser && MLIsHintCand((UIView *)self)) MLHintChanged((UIView *)self);
}
- (void)setHidden:(BOOL)hidden {
    %orig;
    if (gUser && MLIsHintCand((UIView *)self)) MLHintChanged((UIView *)self);
}
%end
%end
// the call-to-action label's own layout and fades (its gradient animation may set a mask of its own: our field then stands down, one hint)
static const MSBDHookSig kHookSigs_MLHintCTA[] = {
    {"SBUICallToActionLabel", "layoutSubviews", "v@:"},
    {"SBUICallToActionLabel", "fadeIn", "v@:"},
    {"SBUICallToActionLabel", "fadeOut", "v@:"},
};
%group MLHintCTA
%hook SBUICallToActionLabel
- (void)layoutSubviews {
    %orig;
    if (gUser && (UIView *)self == gHintLabel) MLFieldMirror();
}
- (void)fadeIn {
    %orig;
    if (gUser && MLIsHintCand((UIView *)self)) MLHintChanged((UIView *)self);
}
- (void)fadeOut {
    %orig;
    if (gUser && MLIsHintCand((UIView *)self)) MLHintChanged((UIView *)self);
}
%end
%end
// (17/18) the transient line by the padlock: its text comes through the prominent display's controller (18.5 Face ID's hint)
static const MSBDHookSig kHookSigs_MLHint17[] = {
    {"CSProminentDisplayViewController", "setTransientSubtitleText:withTimeout:", "v@:@d"},
};
%group MLHint17
%hook CSProminentDisplayViewController
- (void)setTransientSubtitleText:(id)text withTimeout:(double)timeout {
    %orig;
    if (!gFaceUp || !MLPart(kMLPartUser)) return;
    UIView *cv = MLCoverView(), *mp = MLIvar(cv, "_mainPageView");
    [mp setNeedsLayout]; [MLProminent(cv) setNeedsLayout];
}
%end
%end
static const MSBDHookSig kHookSigs_MLHint17b[] = {
    {"CSProminentDisplayViewController", "setTransientSubtitleText:", "v@:@"},
};
%group MLHint17b
%hook CSProminentDisplayViewController
- (void)setTransientSubtitleText:(id)text {
    %orig;
    if (!gFaceUp || !MLPart(kMLPartUser)) return;
    UIView *cv = MLCoverView(), *mp = MLIvar(cv, "_mainPageView");
    [mp setNeedsLayout]; [MLProminent(cv) setNeedsLayout];
}
%end
%end

#if DEBUG
// ---------------------------------------------------------------------------------------------------------------- the debug dump (B0 on the device pass)
// note com.besiktasliseba.maclockscreen.debugdump: the hosts this iPadOS gives (ivar, class, frame, hidden, alpha), iPadOS's lock/pull read, the
// parts' verdicts with the class, selector and image file name, the plain base-class children of each watched container, the list's lowest
// content, the widget frames, and whether a still picture can be read (the answer's size and time). Label texts are never written.
static NSString *MLDR(UIView *v, UIView *cv) {
    if (![v isKindOfClass:[UIView class]]) return v ? [NSString stringWithFormat:@"%@ (not a view)", NSStringFromClass([v class])] : @"-";
    return [NSString stringWithFormat:@"%@ %@ h%d a%.2f w%d", NSStringFromClass([v class]), NSStringFromCGRect(cv ? [cv convertRect:v.bounds fromView:v] : v.frame), v.hidden, v.alpha, v.window != nil];
}
static void MLDebugDump(void) {
    UIView *cv = MLCoverView();
    MLLog(@"dump: iPadOS %d, face %d, checked %d, appearing %d, dismissing %d, lock face %d (down %d pending lock %d), switcher pending %d (saw presenting %d), destra %d, no still %d, still read %d, empty keys %lu, depth down %d",
          gOS, gFaceUp, gChecked, gAppearing, gDismissing, gM.lockFace, gM.down, gM.pendingLock, gSw.pending, gSw.sawPresenting, gDestra, gNoStill, gStillRead, (unsigned long)gEmptyKeys.count, gDepthDown);
    id pm = MLPresentationManager();
    MLLog(@"dump: iPadOS's clock drawn by %s", MLClockPath() == kMLClockPathProminent ? "the prominent display (MLClock17)" : MLClockPath() == kMLClockPathDate ? "the date view's labels (MLClock15)" : "nothing we draw with");
    MLLog(@"dump: dismissed since keybag lock %d, floating layer hidden %d (ours %d)", MLBoolCall(pm, @selector(hasBeenDismissedSinceKeybagLock), NO), MLBoolCall(pm, @selector(wallpaperFloatingLayerHidden), NO), gFloatHidden);
    for (int p = 0; p < kMLPartCount; p++) MLLog(@"dump: part %s wanted %d installed %d install-why %s why %s PART %d", MLPartKey(p), MLPartWanted(&gS, p), gInstalled[p], MLWhyWord(gInstallWhy[p]), MLWhyWord(gWhy[p]), MLPart(p));
    if (!cv) { MLLog(@"dump: no Cover Sheet view"); return; }
    // ---- rev 2 B0 (12.10): the status census, the page's wish, the poster switcher, the hint views, the clock zone ----
    CSCoverSheetViewController *cs = gCS;
    UIWindow *cover = cv.window, *sbw = cover ? LBHStatusBarWindow(cover) : nil;
    MLLog(@"dump: status: Cover Sheet window %@ level %.0f hidden %d; status bar window %@ level %.0f hidden %d alpha %.2f", NSStringFromClass([cover class]), cover.windowLevel, cover.hidden,
          sbw ? NSStringFromClass([sbw class]) : @"none", sbw.windowLevel, sbw.hidden, sbw.alpha);
    for (NSString *what in @[ @"controller _fakeStatusBar", @"view _fakeStatusBar", @"status bar window" ]) {
        UIView *b = [what hasPrefix:@"controller"] ? MLIvar(cs, "_fakeStatusBar") : [what hasPrefix:@"view"] ? MLIvar(cv, "_fakeStatusBar") : LBHWindowBar(sbw);
        BOOL logo = NO, drawn = [b isKindOfClass:[UIView class]] && LBHViewDrawn(b, cover, &logo);
        MLLog(@"dump: status: %@ = %@ (window %@, effective alpha %.2f): drawn %d, our menu bar %d", what, MLDR(b, nil), b.window ? NSStringFromClass([b.window class]) : @"-", MLEffAlpha(b), drawn, logo);
    }
    UIView *root = sbw.rootViewController.isViewLoaded ? sbw.rootViewController.view : nil, *wrap = MLIvar(cv, "_fakeStatusBarWrapperView");
    for (UIView *c in @[ root ?: cv, wrap ?: cv ]) for (UIView *x in c.subviews) if ([NSStringFromClass([x class]) containsString:@"Portal"]) MLLog(@"dump: status: a portal in %@: %@ source %@", NSStringFromClass([c class]), MLDR(x, nil), NSStringFromClass([MLObjCall(x, NSSelectorFromString(@"sourceView")) class]));
    LBHBar vb = LBHVisibleBar(cs);
    MLLog(@"dump: status: VISIBLE BAR %d (%s, our menu bar %d); Hide Status Bar on Lock Screen's flag %d; our reason in %d; the page wants a bar %d (main page visible %d, Today %d); pair shows %d, top right bottom %.0f",
          vb.drawn, vb.what ?: "-", vb.ourMenuBar, objc_getAssociatedObject(cs, LBH_FLAG_KEY) != nil, LBHReasonIn(), MLPageWantsBar(cs), MLBoolCall(cs, @selector(isMainPageVisible), YES), MLBoolCall(cs, @selector(isShowingTodayView), NO), gPairShows, gStatusBottom);
    MLLog(@"dump: poster switcher presenting %d; the Cover Sheet's window hidden %d", MLBoolCall(cs, @selector(_isPresentingPosterSwitcher), NO), cover.hidden);
    {
        UIView *ff = MLIvar(cv, "_fixedFooterView"), *tm = MLIvar(cv, "_teachableMomentsContainerView"), *pd = MLProminent(cv);
        UIView *hints[3] = { MLIvar(ff, "_callToActionLabel"), MLIvar(tm, "_callToActionLabel"), MLIvar(pd, "_transientSubtitleView") };
        const char *names[3] = { "footer", "teachable", "transient line" };
        for (int i = 0; i < 3; i++) {
            UIView *h = hints[i];
            MLLog(@"dump: hint %s = %@, effective alpha %.2f, text length %lu, mask %@, the proud lock's hint %d", names[i], MLDR(h, cv), MLEffAlpha(h), (unsigned long)MLHintText(h).length,
                  h.layer.mask ? (MLHintMaskedByUs(h) ? @"ours" : NSStringFromClass([h.layer.mask class])) : @"none", i == 2 && MLTransientHint(pd) != nil);
        }
        MLLog(@"dump: hint mirrored %@, hint line %@ (owned by another %d)", gHintLabel ? NSStringFromClass([gHintLabel class]) : @"none", MLDR(gUser.field, cv), gFieldOwned);
        UIView *lockView = MLIvar(gPadlock, "_lockView");
        MLLog(@"dump: clock zone: padlock %@, prominent %@ time %@ row %@; the Mac clock: S %.0f, top %.0f, zone bottom %.0f -> date %.0f time %.0f, date top %.0f time top %.0f, scale %.2f fits %d (EXPECTED for L33)", MLDR(lockView, cv),
              MLDR(pd, cv), MLDR(MLIvar(pd, "_timeView"), cv), MLDR(MLIvar(pd, "_complicationRowView"), cv), MIN(cv.bounds.size.width, cv.bounds.size.height), gClockTopLast, gClockZoneLast,
              gClockLast.dateSize, gClockLast.timeSize, gClockLast.top, gClockLast.timeTop, gClockLast.scale, gClockLast.fits);
        BOOL present = NO, drawn = MLDepthLayerDrawn(cv, &present);
        MLLog(@"dump: depth layer present %d drawn %d (ours hidden %d); backdrop %@ key %@", present, drawn, gFloatHidden, MLDR(gBackdrop, cv), gBackdropKeyShown ?: @"-");
        MLLog(@"dump: wallpaper preview classes: SBWallpaperPreviewSnapshotCache %d, PRSPosterSnapshot %d", objc_getClass("SBWallpaperPreviewSnapshotCache") != Nil, objc_getClass("PRSPosterSnapshot") != Nil);
    }
    for (NSString *iv in @[ @"_dateView", @"_backgroundView", @"_mainPageView", @"_fixedFooterView", @"_teachableMomentsContainerView", @"_statusBarLegibilityView", @"_sidebarComplicationContainerView", @"_wallpaperFloatingLayerContainerView" ])
        MLLog(@"dump: CSCoverSheetView.%@ = %@", iv, MLDR(MLIvar(cv, iv.UTF8String), cv));
    UIView *dv = MLIvar(cv, "_dateView");
    for (NSString *iv in @[ @"_timeLabel", @"_dateSubtitleView", @"_activeSubtitleView" ]) MLLog(@"dump: date view.%@ = %@", iv, MLDR(MLIvar(dv, iv.UTF8String), cv));
    for (UIView *pd in [dv isKindOfClass:[UIView class]] ? dv.subviews : @[]) {
        if (![NSStringFromClass([pd class]) isEqualToString:@"CSProminentDisplayView"]) continue;
        for (NSString *iv in @[ @"_timeView", @"_subtitleView", @"_transientSubtitleView", @"_complicationRowView" ]) MLLog(@"dump: prominent.%@ = %@", iv, MLDR(MLIvar(pd, iv.UTF8String), cv));
        UIView *custom = MLObjCall(pd, NSSelectorFromString(@"customSubtitleView"));
        UILabel *tl = MLFirstLabel(MLIvar(pd, "_timeView"), 3);
        MLLog(@"dump: prominent custom subtitle %@, time font %@ %.1f", custom ? NSStringFromClass([custom class]) : @"none", tl.font.fontName, tl.font.pointSize);
    }
    UIView *ff = MLIvar(cv, "_fixedFooterView"), *tm = MLIvar(cv, "_teachableMomentsContainerView");
    MLLog(@"dump: footer call-to-action %@; status text %@", MLDR(MLIvar(ff, "_callToActionLabel"), cv), MLDR(MLIvar(ff, "_statusTextView"), cv));
    MLLog(@"dump: teachable call-to-action %@; home affordance %@", MLDR(MLIvar(tm, "_callToActionLabel"), cv), MLDR(MLIvar(tm, "_homeAffordanceView"), cv));
    CGFloat lb = 0; UIView *mp = MLIvar(cv, "_mainPageView");
    for (UIView *x in [mp isKindOfClass:[UIView class]] ? mp.subviews : @[]) if (x != gUser) MLListBottomWalk(x, cv, &lb, 0);
    CGRect wf[4]; int nw = MLWidgetFrames(cv, wf, 4);
    MLLog(@"dump: list bottom %.1f, widgets %d%@%@, user %@, clock %@", lb, nw, nw > 0 ? NSStringFromCGRect(wf[0]) : @"", nw > 1 ? NSStringFromCGRect(wf[1]) : @"", MLDR(gUser, cv), MLDR(gClock, cv));
    // the plain base-class census of the watched containers (3.4 3b: where iPadOS never puts one, a plain child counts)
    for (UIView *c in @[ dv ?: cv, ff ?: cv, tm ?: cv, cv, mp ?: cv ]) {
        NSMutableString *line = [NSMutableString string];
        for (UIView *x in c.subviews) if (MLIsPlainBase(object_getClass(x)) && !MLIsTaggedOurs(x.layer)) [line appendFormat:@" %s%@", class_getName(object_getClass(x)), NSStringFromCGRect(x.frame)];
        MLLog(@"dump: plain children of %@:%@", NSStringFromClass([c class]), line.length ? line : @" none");
    }
    // the method verdicts, with names (debug only)
    MLTableBuild(&gTable);
    for (int p = 0; p < kMLPartCount; p++) {
        MLPartWatchBuild(&gWatch[p], p, MLProminentClock());
        for (int i = 0; i < gWatch[p].n; i++) {
            MLWatchedClass *w = &gWatch[p].w[i];
            MLWatchedCheck(&gTable, w, _dyld_image_count());
            MLLog(@"dump: watch %s %s: %s, %u own, %@", MLPartKey(p), w->className, w->cls ? "present" : "absent", w->n, w->foreign ? [NSString stringWithFormat:@"ANOTHER'S %@ (%s)", NSStringFromSelector(w->foreignSel), w->foreignImage ?: "?"] : @"clear");
        }
    }
    // a still picture: the wallpaper view's (15/16) and the thumbnail's (asked now; the answer logged when it comes)
    id wc = MLWallpaperController();
    SEL wv = NSSelectorFromString(@"_wallpaperViewForVariant:");
    UIView *v = [wc respondsToSelector:wv] && MLArgInt(class_getInstanceMethod(object_getClass(wc), wv), 2) ? ((id (*)(id, SEL, long))objc_msgSend)(wc, wv, 0) : nil;
    UIImage *img = MLObjCall(v, NSSelectorFromString(@"_displayedImage"));
    MLLog(@"dump: lock wallpaper view %@, still %@", v ? NSStringFromClass([v class]) : @"none", [img isKindOfClass:[UIImage class]] ? NSStringFromCGSize(img.size) : @"none");
    SEL th = NSSelectorFromString(@"wallpaperServer:fetchThumbnailDataForVariant:completionHandler:");
    if (wc && [wc respondsToSelector:th] && method_getNumberOfArguments(class_getInstanceMethod(object_getClass(wc), th)) == 5 && MLArgInt(class_getInstanceMethod(object_getClass(wc), th), 3)) {
        CFTimeInterval t0 = CACurrentMediaTime();
        ((void (*)(id, SEL, id, long, id))objc_msgSend)(wc, th, nil, 0, ^(id data) {
            UIImage *i = [data isKindOfClass:[NSData class]] ? [UIImage imageWithData:data] : nil;
            BOOL main = [NSThread isMainThread];
            dispatch_async(dispatch_get_main_queue(), ^{ MLLog(@"dump: thumbnail answered in %.1f ms on the %@ thread: %@", (CACurrentMediaTime() - t0) * 1000, main ? @"main" : @"background", i ? NSStringFromCGSize(i.size) : @"none"); });
        });
    } else MLLog(@"dump: no thumbnail call on this iPadOS");
    MLLog(@"dump: source key %@", MLBackdropSource() ? @"readable" : @"none");
}
#endif

// ---------------------------------------------------------------------------------------------------------------- install (3.4 4 i)
static BOOL MLHostTypes(int p) {   // (the classes and selectors a part draws with; a version missing one keeps the stock look and logs why)
    switch (p) {
        case kMLPartClock: return MLClockPath() != kMLClockPathNone;   // (what draws iPadOS's clock, with the shape ours draws with: MLClockPathOf)
        case kMLPartBackground: return class_getInstanceVariable(objc_getClass("CSCoverSheetView"), "_backgroundView") != NULL;
        case kMLPartCards: return objc_getClass("PLPlatterView") != Nil;
        case kMLPartUser: return objc_getClass("CSMainPageView") != Nil && objc_getClass("NCNotificationListView") != Nil
                                 && class_getInstanceVariable(objc_getClass("CSCoverSheetView"), "_fixedFooterView") != NULL;
        case kMLPartPair: return objc_getClass("CSCoverSheetView") != Nil;
    }
    return NO;
}
static BOOL MLCoreTypes(void) {
    return objc_getClass("CSCoverSheetViewController") && objc_getClass("CSCoverSheetView") && objc_getClass("SBLockScreenManager")
        && [objc_getClass("CSCoverSheetViewController") instancesRespondToSelector:@selector(setInScreenOffMode:forAutoUnlock:fromUnlockSource:)]
        && [objc_getClass("SBLockScreenManager") instancesRespondToSelector:@selector(lockUIFromSource:withOptions:completion:)];
}
// (a part's own hooks with the types they are written for here: HookTypes.h; Background and Wi-Fi and Battery draw from the core's hooks)
static BOOL MLPartTypesOK(int p) {
    switch (p) {
        case kMLPartClock: return MLProminentClock() ? ML_TYPES_OK(MLClock17) : ML_TYPES_OK(MLClock15);
        case kMLPartCards: return ML_TYPES_OK(MLCards);
        case kMLPartUser: return ML_TYPES_OK(MLUser);
        default: return YES;
    }
}
static BOOL gCoreRefused;   // (the core's methods are not as its hooks are written on this iPadOS: nothing installed in this SpringBoard life)
static BOOL MLInstallWanted(void) {   // returns NO while CoverSheet's classes are not loaded yet (retried at startup)
    if (!MLAnyPartWanted(&gS)) return YES;
    if (!MLCoreTypes()) return NO;
    if (gCoreRefused) return YES;
    MLTableBuild(&gTable);
    if (!gCoreInstalled) {
        if (!ML_TYPES_OK(MLCore)) { gCoreRefused = YES; MLLog(@"core hooks NOT in (iPadOS %d): Mac Lock Screen stays off here", gOS); return YES; }
        %init(MLCore);
        if ([objc_getClass("CSCoverSheetViewController") instancesRespondToSelector:@selector(_prepareForPosterSwitcherPresentation)] && ML_TYPES_OK(MLSwitcher)) %init(MLSwitcher);
        Class sbc = objc_getClass("SBDashBoardStatusBarController");
        if ([sbc instancesRespondToSelector:@selector(setStatusBarAlpha:style:legibilitySettings:)] && [sbc instancesRespondToSelector:@selector(setStatusBarHidden:forReason:)] && ML_TYPES_OK(MLStatusWatch)) %init(MLStatusWatch);
        if ([objc_getClass("CSCoverSheetViewController") instancesRespondToSelector:@selector(scrollablePageViewController:scrollViewDidScroll:)] && ML_TYPES_OK(MLPages)) %init(MLPages);
        gCoreInstalled = YES;
        DM_FEATURE_MARK("mac-lock-screen");
        MLLog(@"core hooks in (iPadOS %d)", gOS);
    }
    for (int p = 0; p < kMLPartCount; p++) {
        if (gInstalled[p] || gInstallWhy[p] || !MLPartWanted(&gS, p)) continue;
        if (!MLHostTypes(p)) { MLLog(@"%s: a class or method it draws with is missing on this iPadOS: stock look", MLPartKey(p)); gInstallWhy[p] = kMLWhyNone; continue; }
        if (!MLPartTypesOK(p)) { MLLog(@"%s: a method it hooks is not as written for this iPadOS: stock look", MLPartKey(p)); gInstallWhy[p] = kMLWhyNone; continue; }
        // check (a) on the current implementations BEFORE hooking: found -> this part's hooks never go in in this SpringBoard life
        const char *cls = NULL, *img = NULL; SEL sel = NULL;
        MLPartWatchBuild(&gWatch[p], p, MLProminentClock());
        if (MLPartMethodsForeign(&gTable, &gWatch[p], &cls, &sel, &img)) {
            gInstallWhy[p] = kMLWhyMethod;
            MLLog(@"%s: not installed: %s %@ is %s's", MLPartKey(p), cls, NSStringFromSelector(sel), img ?: "?");
            continue;
        }
        switch (p) {
            case kMLPartClock: if (MLProminentClock()) { %init(MLClock17); } else { %init(MLClock15); } break;   // (16-18 the prominent display, 15 the date view: 1.8.9 pass: two clocks on 16)
            case kMLPartCards: %init(MLCards); break;
            case kMLPartUser: {
                %init(MLUser);
                // the field's hint hooks: only where no other modification changes iPadOS's hint line (read before ours go in, 12.6)
                gFieldOwned = MLHintMethodsForeign(YES);
                // (a hint group not as written for this iPadOS (HookTypes.h): our line stands down and iPadOS's own is drawn: one hint, never a stale one)
                if (!gFieldOwned && !(ML_TYPES_OK(MLHint) && ML_TYPES_OK(MLHintCTA) && ML_TYPES_OK(MLHint17) && ML_TYPES_OK(MLHint17b))) { gFieldOwned = YES; MLLog(@"field: a hint group is not as written for this iPadOS: the field stands down"); }
                if (!gFieldOwned && objc_getClass("SBUICallToActionLabel") && objc_getClass("SBUILegibilityLabel") && ML_TYPES_OK(MLHint)) %init(MLHint);
                Class cta = objc_getClass("SBUICallToActionLabel"), pdc = objc_getClass("CSProminentDisplayViewController");
                if (!gFieldOwned && [cta instancesRespondToSelector:@selector(fadeIn)] && [cta instancesRespondToSelector:@selector(fadeOut)] && ML_TYPES_OK(MLHintCTA)) %init(MLHintCTA);
                if (!gFieldOwned && [pdc instancesRespondToSelector:@selector(setTransientSubtitleText:withTimeout:)] && ML_TYPES_OK(MLHint17)) %init(MLHint17);
                if (!gFieldOwned && [pdc instancesRespondToSelector:@selector(setTransientSubtitleText:)] && ML_TYPES_OK(MLHint17b)) %init(MLHint17b);
                break;
            }
            default: break;   // (Background and Wi-Fi and Battery draw from the core group's Cover Sheet layout)
        }
        gInstalled[p] = YES;
        MLLog(@"%s hooks in", MLPartKey(p));
    }
    MLWriteState();
    return YES;
}
static void MLPrefsChanged(void) {
    BOOL wasOn = gS.enabled;
    MLSettings was = gS;
    MLReadPrefs(); MLEffectiveBackground();
    for (int p = 0; p < kMLPartCount; p++) if (!MLPartWanted(&gS, p)) gWhy[p] = kMLWhyNone;
    if (wasOn != gS.enabled) MLOnMasterSwitch(&gM);   // (no lock seen while off ever reaches a later appearance: 12.2 (3))
    if (!gS.enabled) {
        if (wasOn) { MLDropAll(@"switched off"); gFaceUp = NO; gAppearing = NO; MLBarNote(NO); }
        if (access(MLS_STATE_FILE, F_OK) == 0) unlink(MLS_STATE_FILE);
        gLastState = @{};
        // (the backdrop's cache goes with the feature, 2.4)
        for (int i = 0; i < 2; i++) { unlink(MLBackdropPath(i, NO).UTF8String); unlink(MLBackdropPath(i, YES).UTF8String); }
        return;
    }
    if (gS.background == kMLBackWallpaper && was.background != kMLBackWallpaper)
        for (int i = 0; i < 2; i++) { unlink(MLBackdropPath(i, NO).UTF8String); unlink(MLBackdropPath(i, YES).UTF8String); }
    if (was.background != gS.background) { gBackdropImage = nil; gBackdropKeyShown = nil; }
    MLInstallWanted();
    MLWriteState();
    CSCoverSheetViewController *cs = gCS;
    // (a change while the Cover Sheet SHOWS: applied now, on at once as off at once. The switch-on path never starts an appearance on a hidden
    //  Cover Sheet -- unlocked, its window stays hidden: 12.2 (3) b)
    if (!MLInMainWindow(cs)) return;
    if (!wasOn) { MLAppearMachine(cs); MLFaceTry(cs, "switched on"); }
    else if (gFaceUp) { MLCheckAll(NO); MLBackdropPrepare(cs.view); MLStatusDecide("a setting changed"); MLRelayoutAll(); }
    else if (gAppearing) MLFaceTry(cs, "a setting changed");
}

%ctor {
    if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
    gOS = (int)[NSProcessInfo processInfo].operatingSystemVersion.majorVersion;
    // (a stale "Handled by another tweak" never stays: decided afresh in this SpringBoard life; nothing written when there is nothing to clear)
    if (access(MLS_STATE_FILE, F_OK) == 0) unlink(MLS_STATE_FILE);
    gLastState = @{};
    int token = 0;
    notify_register_dispatch(MLS_NOTIFY, &token, dispatch_get_main_queue(), ^(int t) { MLPrefsChanged(); });
#if DEBUG
    int dbgToken = 0;   // (L30's simulated owner: /tmp/msb-lockforeign read now, the checks run at once)
    notify_register_dispatch("com.besiktasliseba.maclockscreen.debugcheck", &dbgToken, dispatch_get_main_queue(), ^(int t) {
        CSCoverSheetViewController *cs = gCS;
        if (!gFaceUp || !cs.view.window) { MLLog(@"debug check: no face up"); return; }
        MLCheckAll(NO); MLGiveBackParts(); MLRelayoutAll();
    });
    int dumpToken = 0;
    notify_register_dispatch("com.besiktasliseba.maclockscreen.debugdump", &dumpToken, dispatch_get_main_queue(), ^(int t) { MLDebugDump(); });
#endif
    CFPreferencesAppSynchronize(CFSTR(MLS_DOMAIN));
    id on = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("enabled"), CFSTR(MLS_DOMAIN)));
    if (!MLBoolOr(on, NO)) return;   // (off: nothing installed, nothing else read; the switch's note installs when it is turned on: review finding 7)
    MLReadPrefs();
    // (CoverSheet's classes may load after us: tried again each second for 30 s at most, at startup only, as LockStatusBar.x)
    __block int tries = 0;
    __block void (^attempt)(void);
    void (^a)(void) = ^{
        if (MLInstallWanted() || ++tries >= 30) { attempt = nil; return; }
        void (^again)(void) = attempt;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), again);
    };
    attempt = a;
    attempt();
}
