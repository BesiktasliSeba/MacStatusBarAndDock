// test-maclockcoexist.m -- Mac test of Mac Lock Screen's coexistence verdicts (common/MacLockCoexist.h, F49 1.8.9; design 3.4 7): a plain macOS
// tool (Foundation, Core Animation, AppKit views as the layers' delegates; no UIKit). Its own executable stands for SpringBoard.app's (its
// classes must read iPadOS's); maclockcoexist-fixture/other.m, built as a dylib in a plain folder, is another modification, and built again into
// a .../MacStatusBarAndDock/ folder, one of our own parts. Real swizzles: a function, a block implementation, _objc_msgForward, a runtime subclass
// (an isa swizzle), a hook on a base class (must NOT count), a skip word (must NOT count), our own hook (must NOT count). Pointer signing cannot be
// shown on an arm64 Mac (B0 proved it on the arm64e iPads: unstripped, every method of every class read "outside every image" on 15.6.1).
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include MLC_HEADER

static int gFail, gPass;
#define CHECK(cond, ...) do { if (cond) gPass++; else { gFail++; printf("FAIL  "); printf(__VA_ARGS__); printf("\n"); } } while (0)

// stand-ins for iPadOS's classes (in this executable: iPadOS's by the main-executable rule, as SpringBoard.app's own classes on 15-17)
@interface SBFLockScreenDateView : NSObject @end
@implementation SBFLockScreenDateView - (void)layoutSubviews {} - (void)setDate:(id)d {} @end
@interface SBFLockScreenDateSubtitleView : NSObject @end
@implementation SBFLockScreenDateSubtitleView - (void)layoutSubviews {} @end
@interface SBFWallpaperView : NSObject @end
@implementation SBFWallpaperView - (BOOL)parallaxEnabled { return YES; } - (void)setFrame:(CGRect)f {} @end
@interface SBUIBackgroundView : NSObject @end
@implementation SBUIBackgroundView - (void)layoutSubviews {} @end
@interface PLPlatterView : NSObject @end
@implementation PLPlatterView - (void)layoutSubviews {} - (void)didMoveToWindow {} @end
@interface NCNotificationShortLookView : NSObject @end
@implementation NCNotificationShortLookView - (unsigned long)maximumNumberOfPrimaryTextLines { return 1; } - (void)layoutSubviews {} @end
@interface MLKVOThing : NSObject @property (nonatomic) int value; @end
@implementation MLKVOThing @end

static MLTable gT;
static int Foreign(int part) { MLPartWatch pw; memset(&pw, 0, sizeof(pw)); MLPartWatchBuild(&pw, part, YES); return MLPartMethodsForeign(&gT, &pw, NULL, NULL, NULL); }

int main(int argc, char **argv) { @autoreleasepool {
    if (argc < 3) { printf("usage: test-maclockcoexist <other dylib> <ours dylib>\n"); return 2; }
    // ---- paths (3.4 1) ----
    struct { const char *p; int k; } paths[] = {
        { "/System/Library/PrivateFrameworks/CoverSheet.framework/CoverSheet", kMLKindSystem }, { "/usr/lib/libobjc.A.dylib", kMLKindSystem },
        { "/System/Library/AccessibilityBundles/SpringBoard.axbundle/SpringBoard", kMLKindSystem },
        { "/private/preboot/Cryptexes/OS/System/Library/Frameworks/X.framework/X", kMLKindSystem }, { "/System/Cryptexes/OS/usr/lib/x.dylib", kMLKindSystem },
        { "/var/jb/usr/lib/TweakInject/SomeTweak.dylib", kMLKindOther }, { "/Library/MobileSubstrate/DynamicLibraries/SomeTweak.dylib", kMLKindOther },
        { "/usr/lib/TweakInject/SomeTweak.dylib", kMLKindOther }, { "/private/preboot/ABCD/dopamine-x1/procursus/usr/lib/TweakInject/SomeTweak.dylib", kMLKindOther },
        { "/private/preboot/ABCD/dopamine-x1/procursus/usr/lib/libsomething.dylib", kMLKindOther }, { "/var/containers/Bundle/Application/X/App.app/App", kMLKindOther },
        { "/private/preboot/ABCD/dopamine-x1/procursus/usr/lib/MacStatusBarAndDock/MacLockScreen.dylib", kMLKindOurs },
        { "/var/jb/usr/lib/MacStatusBarAndDock/MacStatusBarCore.dylib", kMLKindOurs }, { "/var/jb/usr/lib/TweakInject/MacStatusBar.dylib", kMLKindOurs },
        { "/usr/lib/TweakInject/MacDock.dylib", kMLKindOurs }, { "/Library/MobileSubstrate/DynamicLibraries/MacStatusBar.dylib", kMLKindOurs },
        { "/var/jb/usr/lib/MacStatusBar.dylib", kMLKindOther }, { NULL, kMLKindOther },
    };
    for (size_t i = 0; i < sizeof(paths) / sizeof(paths[0]); i++) CHECK(MLPathKind(paths[i].p, 0) == paths[i].k, "path %s -> %d (got %d)", paths[i].p ?: "(null)", paths[i].k, MLPathKind(paths[i].p, 0));
    CHECK(MLPathKind("/anything/at/all", 1) == kMLKindSystem, "the main executable is iPadOS's (SpringBoard.app's)");
    // ---- the table ----
    MLTableBuild(&gT);
    CHECK(gT.n > 0 && gT.cacheHi > gT.cacheLo, "the table: %u images outside the shared cache, the cache's range", gT.n);
    CHECK(MLTableBuild(&gT) == 0, "no image loaded since: not rebuilt (nothing at rest)");
    CHECK(MLAddrKind(&gT, (const void *)objc_msgSend, NULL) == kMLKindSystem, "the shared cache's code is iPadOS's");
    CHECK(MLClassKind(&gT, [SBFLockScreenDateView class], NULL) == kMLKindSystem, "a class of the main executable is iPadOS's");
    void *heap = malloc(64);
    CHECK(MLAddrKind(&gT, heap, NULL) == kMLKindOther, "a pointer outside every image is another's (a trampoline)");
    free(heap);
    CHECK(!Foreign(kMLPartClock) && !Foreign(kMLPartBackground) && !Foreign(kMLPartCards), "stock: no part's watched method is another's");
    void *oh = dlopen(argv[1], RTLD_NOW), *uh = dlopen(argv[2], RTLD_NOW);
    CHECK(oh && uh, "the stand-in dylibs load (%s)", dlerror() ?: "");
    if (!oh || !uh) { printf("test-maclockcoexist: %d passed, %d failed\n", gPass, gFail); return 1; }
    CHECK(MLTableBuild(&gT) == 1, "two images loaded: the table is rebuilt");
    IMP (*sw)(Class, SEL) = dlsym(oh, "other_swizzle"), (*swb)(Class, SEL) = dlsym(oh, "other_swizzleBlock"), (*swf)(Class, SEL) = dlsym(oh, "other_swizzleForward");
    IMP (*base)(void) = dlsym(oh, "other_hookBase"); Class (*rsub)(Class) = dlsym(oh, "other_runtimeSubclass");
    CALayer *(*olayer)(void) = dlsym(oh, "other_layer"); NSView *(*oview)(void) = dlsym(oh, "other_view");
    IMP (*ours)(Class, SEL) = dlsym(uh, "ours_swizzle");
    CHECK(sw && swb && swf && base && rsub && olayer && oview && ours, "the stand-ins' functions");
    // a hook on a base class: not an owner of a Lock Screen part (only the methods a watched class defines itself)
    IMP bwas = base();
    CHECK(!Foreign(kMLPartClock) && !Foreign(kMLPartCards), "a hook on NSObject's -description does not count");
    method_setImplementation(class_getInstanceMethod([NSObject class], @selector(description)), bwas);
    // a function swizzle on a watched method: found, with its selector; the same pointer kept: found again; put back: gone
    Method dm = class_getInstanceMethod([SBFLockScreenDateView class], @selector(layoutSubviews));
    IMP was = sw([SBFLockScreenDateView class], @selector(layoutSubviews));
    MLPartWatch pw; memset(&pw, 0, sizeof(pw)); MLPartWatchBuild(&pw, kMLPartClock, YES);
    const char *cls = NULL, *img = NULL; SEL sel = NULL;
    CHECK(MLPartMethodsForeign(&gT, &pw, &cls, &sel, &img) && sel == @selector(layoutSubviews) && cls && !strcmp(cls, "SBFLockScreenDateView") && img && strstr(img, "other"),
          "a function swizzle on SBFLockScreenDateView -layoutSubviews: Clock Style stands down (%s %s %s)", cls ?: "-", sel ? sel_getName(sel) : "-", img ?: "-");
    CHECK(MLPartMethodsForeign(&gT, &pw, NULL, NULL, NULL), "the kept pair: found again with no new verdict");
    CHECK(!Foreign(kMLPartCards) && !Foreign(kMLPartBackground), "the other parts go on");
    method_setImplementation(dm, was);
    CHECK(!MLPartMethodsForeign(&gT, &pw, NULL, NULL, NULL), "the swizzle taken back: the part is ours again (a changed pointer is judged again)");
    // a block implementation made by the other image: judged by its invoke function
    Method pm = class_getInstanceMethod([PLPlatterView class], @selector(layoutSubviews));
    was = swb([PLPlatterView class], @selector(layoutSubviews));
    CHECK(Foreign(kMLPartCards), "a block implementation from another image: Mac-Style Cards stands down");
    method_setImplementation(pm, was);
    method_setImplementation(pm, imp_implementationWithBlock(^(id me) { (void)me; }));
    CHECK(!Foreign(kMLPartCards), "a block of the main executable's (as iPadOS's own blocks): not another's");
    method_setImplementation(pm, was);
    // _objc_msgForward (forwarding-based swizzling)
    Method bm = class_getInstanceMethod([SBUIBackgroundView class], @selector(layoutSubviews));
    was = swf([SBUIBackgroundView class], @selector(layoutSubviews));
    CHECK(Foreign(kMLPartBackground), "_objc_msgForward on SBUIBackgroundView: Background stands down");
    method_setImplementation(bm, was);
    // skip words: another iPadOS piece's own methods in a watched class
    was = sw([SBFWallpaperView class], @selector(parallaxEnabled));
    CHECK(!Foreign(kMLPartBackground), "a hook on SBFWallpaperView -parallaxEnabled (the wallpaper's motion) does not count");
    method_setImplementation(class_getInstanceMethod([SBFWallpaperView class], @selector(parallaxEnabled)), was);
    was = sw([NCNotificationShortLookView class], @selector(maximumNumberOfPrimaryTextLines));
    CHECK(!Foreign(kMLPartCards), "a hook on a notification's text line count does not count");
    method_setImplementation(class_getInstanceMethod([NCNotificationShortLookView class], @selector(maximumNumberOfPrimaryTextLines)), was);
    was = sw([NCNotificationShortLookView class], @selector(layoutSubviews));
    CHECK(Foreign(kMLPartCards), "...but its layout: Mac-Style Cards stands down");
    method_setImplementation(class_getInstanceMethod([NCNotificationShortLookView class], @selector(layoutSubviews)), was);
    // our own hook: never another's
    was = ours([SBFWallpaperView class], @selector(setFrame:));
    CHECK(!Foreign(kMLPartBackground), "our own part's hook (.../MacStatusBarAndDock/) is ours, not another's");
    method_setImplementation(class_getInstanceMethod([SBFWallpaperView class], @selector(setFrame:)), was);
    was = ours([SBFLockScreenDateSubtitleView class], @selector(layoutSubviews));
    CHECK(MLOrigIsForeign(&gT, was, NULL) == 0, "the implementation our hook replaced: iPadOS's (nobody hooked it before us)");
    IMP ourHook = method_setImplementation(class_getInstanceMethod([SBFLockScreenDateSubtitleView class], @selector(layoutSubviews)), was);
    sw([SBFLockScreenDateSubtitleView class], @selector(layoutSubviews));
    IMP theirs = method_getImplementation(class_getInstanceMethod([SBFLockScreenDateSubtitleView class], @selector(layoutSubviews)));
    CHECK(MLOrigIsForeign(&gT, theirs, NULL) == 1 && MLImpKind(&gT, ourHook, NULL) == kMLKindOurs, "another's hook before ours: its implementation is another's (check a's orig rule)");
    method_setImplementation(class_getInstanceMethod([SBFLockScreenDateSubtitleView class], @selector(layoutSubviews)), was);
    // a runtime subclass (an isa swizzle) made by another image: another's by its own methods; KVO's: Foundation's
    Class rs = rsub([SBFLockScreenDateView class]);
    CHECK(rs && class_getImageName(rs) == NULL && MLClassKind(&gT, rs, NULL) == kMLKindOther, "a runtime subclass with another's code (an isa swizzle) is another's");
    MLKVOThing *k = [MLKVOThing new];
    [k addObserver:(id)[NSObject new] forKeyPath:@"value" options:0 context:NULL];
    Class kc = object_getClass(k);
    CHECK(kc != [MLKVOThing class] && MLClassKind(&gT, kc, NULL) == kMLKindSystem, "a KVO class (%s) reads as its superclass, iPadOS's", class_getName(kc));
    // ---- the layer walk (3.4 3b) and the whole-face rule (3.4 3c) ----
    MLClassCache cc; memset(&cc, 0, sizeof(cc));
    CALayer *root = [CALayer layer], *mid = [CALayer layer];
    [root addSublayer:mid];
    MLFind f = {0};
    CHECK(!MLLayerWalk(&gT, &cc, root, 3, NO, &f), "a stock container: nothing found");
    CHECK(MLLayerWalk(&gT, &cc, root, 3, YES, &f) && f.plain, "a plain CALayer child where iPadOS never puts one: found (plain)");
    MLTagOurs(mid);
    CHECK(!MLLayerWalk(&gT, &cc, root, 3, YES, &f), "our own tagged child: skipped");
    CALayer *deep = olayer(); CALayer *l2 = [CALayer layer], *l3 = [CALayer layer];
    [root addSublayer:l2]; [l2 addSublayer:l3]; [l3 addSublayer:deep];
    memset(&cc, 0, sizeof(cc));
    CHECK(MLLayerWalk(&gT, &cc, root, 3, NO, &f) && !f.plain && !strcmp(class_getName(f.cls), "OtherLayer"), "another's layer three levels down: found");
    CHECK(!MLLayerWalk(&gT, &cc, root, 2, NO, &f), "...and not when walking two levels");
    CALayer *r2 = [CALayer layer];
    NSView *v = oview();
    [r2 addSublayer:v.layer];
    memset(&cc, 0, sizeof(cc));
    CHECK(MLLayerWalk(&gT, &cc, r2, 1, NO, &f) && !strcmp(class_getName(f.cls), "OtherView"), "a layer whose view (its delegate) is another's class: found");
    NSView *plainView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 5, 5)]; plainView.wantsLayer = YES;
    CALayer *r3 = [CALayer layer]; [r3 addSublayer:plainView.layer];
    CHECK(!MLLayerWalk(&gT, &cc, r3, 1, NO, &f) && MLLayerWalk(&gT, &cc, r3, 1, YES, &f) && f.plain, "a plain view: only with the plain rule");
    // whole face
    CALayer *face = [CALayer layer], *big = olayer();
    big.bounds = CGRectMake(0, 0, 1000, 800); big.backgroundColor = CGColorCreateGenericGray(0, 1);
    [face addSublayer:big];
    memset(&cc, 0, sizeof(cc));
    CHECK(MLWholeFaceFind(&gT, &cc, face, 1024 * 768, NO, &f), "another's drawing layer over more than half the screen: a whole face (every part stands down)");
    big.hidden = YES; CHECK(!MLWholeFaceFind(&gT, &cc, face, 1024 * 768, NO, &f), "...hidden: not");
    big.hidden = NO; big.opacity = 0; CHECK(!MLWholeFaceFind(&gT, &cc, face, 1024 * 768, NO, &f), "...transparent: not");
    big.opacity = 1; big.bounds = CGRectMake(0, 0, 300, 300); CHECK(!MLWholeFaceFind(&gT, &cc, face, 1024 * 768, NO, &f), "...small: not");
    big.bounds = CGRectMake(0, 0, 1000, 800); big.backgroundColor = NULL;
    CHECK(!MLWholeFaceFind(&gT, &cc, face, 1024 * 768, NO, &f), "...drawing nothing: not");
    CALayer *plainBig = [CALayer layer]; plainBig.bounds = CGRectMake(0, 0, 1000, 800); plainBig.backgroundColor = CGColorCreateGenericGray(0, 1);
    CALayer *f2 = [CALayer layer]; [f2 addSublayer:plainBig];
    CHECK(!MLWholeFaceFind(&gT, &cc, f2, 1024 * 768, NO, &f) && MLWholeFaceFind(&gT, &cc, f2, 1024 * 768, YES, &f), "a plain full-screen layer: only with the plain rule");
    MLTagOurs(plainBig); CHECK(!MLWholeFaceFind(&gT, &cc, f2, 1024 * 768, YES, &f), "our own backdrop (tagged): never a whole face");
    // ---- cost (3.4 6): a second pass judges no pointer again ----
    MLPartWatch pc; memset(&pc, 0, sizeof(pc)); MLPartWatchBuild(&pc, kMLPartClock, YES);
    MLPartMethodsForeign(&gT, &pc, NULL, NULL, NULL);
    CFTimeInterval t0 = CACurrentMediaTime();
    for (int i = 0; i < 1000; i++) MLPartMethodsForeign(&gT, &pc, NULL, NULL, NULL);
    double us = (CACurrentMediaTime() - t0) * 1e6 / 1000;
    CHECK(us < 50, "the kept-pair check: %.2f us per pass", us);
    // ---- the clock's watch follows what draws iPadOS's clock (1.8.9 pass: two clocks on 16): the prominent display's classes wherever it draws it (16-18) ----
    MLWatchName wn[ML_WATCH_MAX]; int wDate = MLWatchNames(kMLPartClock, NO, wn, ML_WATCH_MAX), hasProm = 0;
    for (int i = 0; i < wDate; i++) if (!strncmp(wn[i].cls, "CSProminent", 11)) hasProm++;
    CHECK(wDate == 4 && hasProm == 0, "the date view's clock (15): its four classes, no prominent class");
    int wProm = MLWatchNames(kMLPartClock, YES, wn, ML_WATCH_MAX); hasProm = 0;
    for (int i = 0; i < wProm; i++) if (!strncmp(wn[i].cls, "CSProminent", 11)) hasProm++;
    CHECK(wProm == 9 && hasProm == 5, "the prominent display's clock (16-18): its five classes watched too");
    printf("test-maclockcoexist: %d passed, %d failed\n", gPass, gFail);
    return gFail ? 1 : 0;
} }
