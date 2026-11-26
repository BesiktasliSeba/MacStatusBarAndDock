// MacLockCoexist.h -- Mac Lock Screen (F49, 1.8.9): is a part of the Lock Screen already another modification's? (plans/design-mac-lock-screen.md
// 3.4; coexistence is ours: our code is the one that yields). Foundation, the Objective-C runtime and Core Animation only (no UIKit), so the
// Mac test (tools/test-maclockcoexist.sh) runs it with real swizzles, blocks, forwarding and runtime subclasses.
//
// Nothing here names a tweak, a bundle, a file or a preference domain: it reads only where code and classes live.
//  - Where code lives: every loaded image's WHOLE range (all segments, from its load commands), rebuilt only when _dyld_image_count() has changed
//    (no callback, nothing at rest). An image is iPadOS's (the shared cache; the main executable, which is SpringBoard.app's on the iPad; images
//    under /System/, /usr/lib/ or /private/preboot/Cryptexes/ outside a jailbreak's folders), ours (a path holding "/MacStatusBarAndDock/", or our
//    two loaders in the tweak folder: CrashBlame.h's rule) or another's (everything else). A pointer outside every image is another's (a hooking
//    library's trampoline), except a block trampoline, judged by its block's invoke function; _objc_msgForward is another's (forwarding swizzles).
//  - Pointer signing: on arm64e (the 18.5 and 15.6.1 iPads) implementations, block invoke pointers and _objc_msgForward carry pointer-auth bits; every
//    pointer is stripped before any compare (without it every method of every class reads "outside every image": B0 proves it on both arm64e iPads).
//  - A class by the image it was defined in (class_getImageName); a class with none (made at run time: a KVO class, a runtime subclass) by its first
//    superclass that has one, and its own methods by their implementations. dladdr is never used for a verdict.
//  - Only the classes that DRAW a part are watched, and only the methods each defines itself (class_copyMethodList, not inherited): a hook on a
//    UIKit base class is a global theme, not an owner of a Lock Screen part; behaviour classes are never watched (design 3.4 2).
#pragma once
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include <objc/runtime.h>
#include <objc/message.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <ptrauth.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

// (dyld's own call, in libdyld on iPadOS 13+ and macOS 10.15+; declared in the private dyld_priv.h only)
extern const void *_dyld_get_shared_cache_range(size_t *length);

enum { kMLKindNone = 0, kMLKindSystem = 1, kMLKindOurs = 2, kMLKindOther = 3 };

static inline uintptr_t MLStrip(const void *p) {
#if __has_feature(ptrauth_calls)
    return (uintptr_t)ptrauth_strip(p, ptrauth_key_function_pointer);
#else
    return (uintptr_t)p;
#endif
}

// ---- the kind of an image by its path (isMain: the process's own executable) ----
static inline int MLHasPrefix(const char *s, const char *p) { return strncmp(s, p, strlen(p)) == 0; }
static inline int MLPathKind(const char *path, int isMain) {
    if (isMain) return kMLKindSystem;   // (SpringBoard.app's executable: 15-17 keep SpringBoard's classes there)
    if (!path || !*path) return kMLKindOther;
    if (strstr(path, "/MacStatusBarAndDock/")) return kMLKindOurs;
    const char *base = strrchr(path, '/'); base = base ? base + 1 : path;
    if ((!strcmp(base, "MacStatusBar.dylib") || !strcmp(base, "MacDock.dylib")) && (strstr(path, "/DynamicLibraries/") || strstr(path, "/TweakInject/")))
        return kMLKindOurs;
    // a jailbreak's folders (generic places, not tweaks): its root (/var/jb, a /private/preboot/<id>/ root), the tweak folders
    if (strstr(path, "/var/jb/") || strstr(path, "/TweakInject") || strstr(path, "/MobileSubstrate/")) return kMLKindOther;
    if (MLHasPrefix(path, "/private/preboot/") && !MLHasPrefix(path, "/private/preboot/Cryptexes/")) return kMLKindOther;
    if (MLHasPrefix(path, "/System/") || MLHasPrefix(path, "/usr/lib/") || MLHasPrefix(path, "/private/preboot/Cryptexes/")) return kMLKindSystem;
    return kMLKindOther;
}

// ---- the image table ----
typedef struct { uintptr_t lo, hi; int kind; const char *name; } MLImage;   // (name: the file name, for the DEBUG log only)
typedef struct {
    MLImage *v; uint32_t n, cap;
    uint32_t builtFor;            // _dyld_image_count() at the build
    uintptr_t cacheLo, cacheHi;   // the shared cache's mapped range
    char mainPath[PATH_MAX];      // the main executable's real path
    char mainName[PATH_MAX];      // ...and the path dyld loaded it by (class_getImageName gives this one)
} MLTable;

static inline int MLImageCmp(const void *a, const void *b) {
    uintptr_t x = ((const MLImage *)a)->lo, y = ((const MLImage *)b)->lo;
    return x < y ? -1 : x > y;
}
// Rebuilt only when the image count changed since the last build (a dlopen or dlclose); returns 1 when it was rebuilt.
static inline int MLTableBuild(MLTable *t) {
    uint32_t count = _dyld_image_count();
    if (t->v && count == t->builtFor) return 0;
    size_t len = 0;
    const void *cache = _dyld_get_shared_cache_range(&len);
    t->cacheLo = (uintptr_t)cache; t->cacheHi = cache ? (uintptr_t)cache + len : 0;
    for (uint32_t i = 0; i < t->n; i++) free((void *)t->v[i].name);
    t->n = 0;
    if (t->cap < count + 8) { t->cap = count + 32; t->v = (MLImage *)realloc(t->v, t->cap * sizeof(MLImage)); if (!t->v) { t->cap = 0; return 0; } }
    for (uint32_t i = 0; i < count; i++) {
        const struct mach_header *h = _dyld_get_image_header(i);
        if (!h) continue;
        uintptr_t ha = (uintptr_t)h;
        if (ha >= t->cacheLo && ha < t->cacheHi) continue;   // (in the shared cache: iPadOS's by its range)
        if (h->magic != MH_MAGIC_64) continue;
        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        uintptr_t lo = UINTPTR_MAX, hi = 0;
        const struct load_command *lc = (const struct load_command *)((const struct mach_header_64 *)h + 1);
        for (uint32_t k = 0; k < h->ncmds; k++, lc = (const struct load_command *)((const char *)lc + lc->cmdsize)) {
            if (lc->cmd != LC_SEGMENT_64) continue;
            const struct segment_command_64 *sg = (const struct segment_command_64 *)lc;
            if (!strcmp(sg->segname, "__PAGEZERO") || sg->vmsize == 0) continue;
            uintptr_t a = (uintptr_t)(sg->vmaddr + slide), b = a + (uintptr_t)sg->vmsize;
            if (a < lo) lo = a;
            if (b > hi) hi = b;
        }
        if (hi <= lo) continue;
        const char *path = _dyld_get_image_name(i);
        char real[PATH_MAX];
        const char *p = (path && realpath(path, real)) ? real : path;
        int isMain = h->filetype == MH_EXECUTE;
        if (isMain && p) strlcpy(t->mainPath, p, sizeof(t->mainPath));
        if (isMain && path) strlcpy(t->mainName, path, sizeof(t->mainName));
        const char *base = p ? strrchr(p, '/') : NULL;
        if (t->n >= t->cap) break;
        // (the path dyld loaded it by, and its real path: ours by either; else iPadOS's when dyld loaded it from a system path -- the 15.6.1 iPad's
        //  libobjc-trampolines.dylib, read on 25 Nov through the jailbreak's bound /usr/lib, has a real path in the jailbreak's folder: review
        //  1.8.9 F49 finding 17 --, else by its real path)
        int kd = MLPathKind(path, isMain), kr = MLPathKind(p, isMain);
        int kind = (kd == kMLKindOurs || kr == kMLKindOurs) ? kMLKindOurs : kd == kMLKindSystem ? kMLKindSystem : kr;
        t->v[t->n++] = (MLImage){ lo, hi, kind, strdup(base ? base + 1 : (p ?: "?")) };
    }
    qsort(t->v, t->n, sizeof(MLImage), MLImageCmp);
    t->builtFor = count;
    return 1;
}
static inline const MLImage *MLImageAt(const MLTable *t, uintptr_t a) {
    long lo = 0, hi = (long)t->n - 1;
    while (lo <= hi) {
        long mid = (lo + hi) / 2;
        const MLImage *m = &t->v[mid];
        if (a < m->lo) hi = mid - 1; else if (a >= m->hi) lo = mid + 1; else return m;
    }
    return NULL;
}
// The kind of the code at p (stripped first). A pointer outside every image is another's.
static inline int MLAddrKind(const MLTable *t, const void *p, const char **name) {
    uintptr_t a = MLStrip(p);
    if (name) *name = NULL;
    if (!a) return kMLKindNone;
    if (a >= t->cacheLo && a < t->cacheHi) { if (name) *name = "(shared cache)"; return kMLKindSystem; }
    const MLImage *m = MLImageAt(t, a);
    if (name) *name = m ? m->name : "(outside every image)";
    return m ? m->kind : kMLKindOther;
}
// The kind of an implementation: _objc_msgForward is another's; a block trampoline is judged by its block's invoke function.
struct MLBlockLayout { void *isa; int flags; int reserved; void *invoke; };
static inline int MLImpKind(const MLTable *t, IMP imp, const char **name) {
    if (name) *name = NULL;
    if (!imp) return kMLKindNone;
    if (MLStrip((const void *)imp) == MLStrip((const void *)_objc_msgForward)) { if (name) *name = "(_objc_msgForward)"; return kMLKindOther; }
    id block = imp_getBlock(imp);
    if (block) {
        const struct MLBlockLayout *b = (__bridge const struct MLBlockLayout *)block;
        return MLAddrKind(t, b->invoke, name);
    }
    return MLAddrKind(t, (const void *)imp, name);
}
// The kind of a class: the image it was defined in; a class with none (made at run time: an isa swizzle, a KVO class) by its own methods' code
// (another's when one is: a tweak's runtime subclass; KVO's are Foundation's), then by its first superclass that has an image.
static inline int MLClassKind(const MLTable *t, Class c, const char **name) {
    if (name) *name = NULL;
    for (Class k = c; k; k = class_getSuperclass(k)) {
        const char *img = class_getImageName(k);
        if (!img) {
            unsigned n = 0; Method *ms = class_copyMethodList(k, &n); int other = 0;
            for (unsigned i = 0; i < n && !other; i++) other = MLImpKind(t, method_getImplementation(ms[i]), name) == kMLKindOther;
            free(ms);
            if (other) return kMLKindOther;
            continue;
        }
        if (name) { const char *b = strrchr(img, '/'); *name = b ? b + 1 : img; }
        // (class_getImageName gives the path dyld loaded the image by: a jailbreak path for a tweak, a /System path for iPadOS's)
        int isMain = (t->mainPath[0] && !strcmp(img, t->mainPath)) || (t->mainName[0] && !strcmp(img, t->mainName));
        return MLPathKind(img, isMain);
    }
    return kMLKindOther;
}

// ---- method checks (3.4 3a): each watched class's OWN methods; only a changed implementation is judged again ----
typedef struct { Method m; SEL sel; uintptr_t imp; int kind; const char *img; } MLMethodSeen;
typedef struct {
    const char *className;
    const char *skip;             // '|'-separated words: own methods whose selector holds one belong to another iPadOS piece (not watched)
    Class cls;                    // (resolved when the class exists; Nil = not loaded / not on this iPadOS: nothing to judge)
    MLMethodSeen *seen; unsigned n;
    uint32_t copiedFor;           // _dyld_image_count() when the method list was copied
    int foreign;                  // last verdict: an own method whose implementation is another's
    SEL foreignSel; const char *foreignImage;
} MLWatchedClass;

static inline int MLSelSkipped(const char *sel, const char *skip) {
    if (!skip || !*skip || !sel) return 0;
    char word[64]; const char *p = skip;
    while (*p) {
        const char *e = strchr(p, '|'); size_t n = e ? (size_t)(e - p) : strlen(p);
        if (n && n < sizeof(word)) { memcpy(word, p, n); word[n] = 0; if (strstr(sel, word)) return 1; }
        if (!e) break;
        p = e + 1;
    }
    return 0;
}
static inline void MLWatchedRecopy(MLWatchedClass *w) {
    free(w->seen); w->seen = NULL; w->n = 0;
    if (!w->cls) return;
    unsigned n = 0, k = 0;
    Method *ms = class_copyMethodList(w->cls, &n);
    w->seen = (MLMethodSeen *)calloc(n ? n : 1, sizeof(MLMethodSeen));
    for (unsigned i = 0; i < n && w->seen; i++) {
        SEL sel = method_getName(ms[i]);
        if (MLSelSkipped(sel_getName(sel), w->skip)) continue;
        w->seen[k++] = (MLMethodSeen){ ms[i], sel, 0, -1, NULL };
    }
    w->n = w->seen ? k : 0;
    free(ms);
}
// Returns 1 when one of the class's own methods is another's. Cost: a pointer compare per method; a verdict only for a changed pointer.
static inline int MLWatchedCheck(const MLTable *t, MLWatchedClass *w, uint32_t imageCount) {
    if (!w->cls) w->cls = objc_getClass(w->className);
    if (!w->cls) return 0;
    if (!w->seen || w->copiedFor != imageCount) { MLWatchedRecopy(w); w->copiedFor = imageCount; }
    w->foreign = 0; w->foreignSel = NULL; w->foreignImage = NULL;
    for (unsigned i = 0; i < w->n; i++) {
        MLMethodSeen *s = &w->seen[i];
        IMP imp = method_getImplementation(s->m);
        uintptr_t a = MLStrip((const void *)imp);
        if (a != s->imp || s->kind < 0) { const char *nm = NULL; s->kind = MLImpKind(t, imp, &nm); s->imp = a; s->img = nm; }
        if (s->kind == kMLKindOther && !w->foreign) { w->foreign = 1; w->foreignSel = s->sel; w->foreignImage = s->img; }
    }
    return w->foreign;
}
// Check (a) for a hook of ours on a watched method the class defines itself: the implementation our hook replaced (orig). Another's = it hooked
// that method before us. Never called for the behaviour hooks or for inherited methods (design 3.4 3a).
static inline int MLOrigIsForeign(const MLTable *t, IMP orig, const char **name) { return MLImpKind(t, orig, name) == kMLKindOther; }

// ---- views and layers (3.4 3b, 3c) ----
// Every view and layer of ours on the Lock Screen carries this tag (an associated object on the layer); a tagged layer's subtree is ours.
static const void *const kMLOursTagKey = &kMLOursTagKey;
static inline void MLTagOurs(CALayer *l) { if (l) objc_setAssociatedObject(l, kMLOursTagKey, (id)kCFBooleanTrue, OBJC_ASSOCIATION_ASSIGN); }
static inline BOOL MLIsTaggedOurs(CALayer *l) { return l && objc_getAssociatedObject(l, kMLOursTagKey) != nil; }

// A small cache of class -> kind (the layer walk visits the same few classes at every appearance).
typedef struct { const void *cls[64]; signed char kind[64]; } MLClassCache;
static inline int MLClassKindCached(const MLTable *t, MLClassCache *cc, Class c) {
    uintptr_t h = ((uintptr_t)(__bridge const void *)c >> 4) & 63;
    for (int i = 0; i < 64; i++) {
        uintptr_t j = (h + i) & 63;
        if (cc->cls[j] == (__bridge const void *)c) return cc->kind[j];
        if (!cc->cls[j]) { int k = MLClassKind(t, c, NULL); cc->cls[j] = (__bridge const void *)c; cc->kind[j] = (signed char)k; return k; }
    }
    return MLClassKind(t, c, NULL);
}
// Is c one of the plain base classes (exactly UIView, UILabel, UIImageView, CALayer; on the Mac test NSView too)?
static inline BOOL MLIsPlainBase(Class c) {
    const char *n = class_getName(c);
    return !strcmp(n, "UIView") || !strcmp(n, "UILabel") || !strcmp(n, "UIImageView") || !strcmp(n, "CALayer") || !strcmp(n, "NSView");
}
// The class a layer stands for: its view's when its delegate is a view (on iPadOS a view is its layer's delegate), else the layer's own.
static inline Class MLLayerOwnerClass(CALayer *l) {
    id d = l.delegate;
    static Class viewClass;
    if (!viewClass) viewClass = objc_getClass("UIView") ?: objc_getClass("NSView");
    if (d && viewClass && [d isKindOfClass:viewClass]) return object_getClass(d);   // (object_getClass: an isa-swizzled view counts as what it is)
    return object_getClass(l);
}
typedef struct { Class cls; int plain; int depth; } MLFind;
// The part's own iPadOS layers and their sublayers `levels` down, stopping at the first find: a layer (or its view) of another's class, or, where
// plainCounts (B0 found that iPadOS never puts a plain child there), an untagged plain base-class child. Our tagged layers are skipped whole.
static inline int MLLayerWalk(const MLTable *t, MLClassCache *cc, CALayer *root, int levels, BOOL plainCounts, MLFind *find) {
    if (!root || levels <= 0) return 0;
    NSArray *subs = root.sublayers;
    for (CALayer *s in subs) {
        if (MLIsTaggedOurs(s)) continue;
        Class c = MLLayerOwnerClass(s);
        if (MLClassKindCached(t, cc, c) == kMLKindOther) { if (find) *find = (MLFind){ c, 0, levels }; return 1; }
        if (plainCounts && MLIsPlainBase(c)) { if (find) *find = (MLFind){ c, 1, levels }; return 1; }
        if (MLLayerWalk(t, cc, s, levels - 1, NO, find)) return 1;   // (the plain rule is for the container's own children only)
    }
    return 0;
}
// 3c: a direct child of a whole-face container that covers more than half of the screen and draws, of another's class (or an untagged plain
// class where plainCounts), stands every part down: someone draws a whole Lock Screen.
static inline BOOL MLLayerDraws(CALayer *l) {
    if (l.hidden || l.opacity <= 0.001f) return NO;
    CGColorRef bg = l.backgroundColor;
    return (bg && CGColorGetAlpha(bg) > 0.001) || l.contents != nil || l.sublayers.count > 0;
}
static inline int MLWholeFaceFind(const MLTable *t, MLClassCache *cc, CALayer *container, CGFloat screenArea, BOOL plainCounts, MLFind *find) {
    if (!container || screenArea <= 0) return 0;
    for (CALayer *s in container.sublayers) {
        if (MLIsTaggedOurs(s)) continue;
        CGRect b = s.bounds;
        if (b.size.width * b.size.height <= screenArea * 0.5 || !MLLayerDraws(s)) continue;
        Class c = MLLayerOwnerClass(s);
        int k = MLClassKindCached(t, cc, c);
        if (k == kMLKindOther || (plainCounts && MLIsPlainBase(c))) { if (find) *find = (MLFind){ c, k != kMLKindOther, 1 }; return 1; }
    }
    return 0;
}

// ---- the parts and the state file (3.4 5) ----
enum { kMLPartClock = 0, kMLPartBackground, kMLPartCards, kMLPartUser, kMLPartPair, kMLPartCount };
enum { kMLWhyNone = 0, kMLWhyMethod = 1, kMLWhyView = 2, kMLWhyWholeFace = 3, kMLWhyOutcome = 4 };
static inline const char *MLPartKey(int part) {
    static const char *k[] = { "clock", "background", "cards", "user", "pair" };
    return part >= 0 && part < kMLPartCount ? k[part] : "?";
}
static inline const char *MLWhyWord(int why) {
    static const char *w[] = { "", "method", "view", "whole face", "outcome" };
    return why >= 0 && why <= 4 ? w[why] : "?";
}
// The state file SpringBoard writes and Settings reads (labels and yes/no only: no names, no paths): { "handled": { "<part>": true, ... },
// "noStill": true, "stillRead": true }. stillRead (1.8.9 pass: the black backdrop): a still with a picture in it was read on this iPad in this SpringBoard life
// (Settings offers Blurred on 17/18 only then: MacLockScreen.h MLBlurredOffered). An empty dictionary when nothing is handled elsewhere.
static inline NSDictionary *MLStateDict(const int why[kMLPartCount], BOOL noStill, BOOL stillRead) {
    NSMutableDictionary *h = [NSMutableDictionary dictionary];
    for (int p = 0; p < kMLPartCount; p++) if (why[p]) h[@(MLPartKey(p))] = @YES;
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (h.count) d[@"handled"] = h;
    if (noStill) d[@"noStill"] = @YES;
    if (stillRead) d[@"stillRead"] = @YES;
    return d;
}
static inline BOOL MLStateHandled(NSDictionary *state, int part) {
    NSDictionary *h = [state isKindOfClass:[NSDictionary class]] ? state[@"handled"] : nil;
    id v = [h isKindOfClass:[NSDictionary class]] ? h[@(MLPartKey(part))] : nil;
    return [v respondsToSelector:@selector(boolValue)] && [v boolValue];
}

// ---- each part's watch list (3.4 2; B0 25 Nov, 15.6.1 and 17.5.1) ----
// The classes that DRAW a part, iPadOS's own names. Skip words: an own method of that class that serves another iPadOS piece (the wallpaper's
// parallax motion; a notification's text line count) is not counted: B0 read them hooked on the 15.6.1 iPad by tweaks that change nothing of the part's
// look. Picture and Name has no method watch: its classes (the footer, the teachable-moments container) also hold the call-to-action line, the
// Control Center grabber and the home affordance, which tweaks commonly move, retitle or hide (the 15.6.1 iPad: Lynx's _layoutCallToActionView,
// _addCallToActionLabel, controlCenterGrabberView); our block reads that line's frame at each layout, so they never collide with it. It is
// judged by the views in its containers (3.4 3b) and the whole-face rule. Wi-Fi and Battery is judged by its outcome (our own Hide Status Bar on
// Lock Screen hides the bar, or it is left to whatever does).
typedef struct { const char *cls, *skip; } MLWatchName;
// prominentClock: iPadOS draws its clock with CoverSheetKit's prominent display (16-18; MacLockScreen.h MLClockPathOf, 1.8.9 pass: two clocks on 16): its classes
// are watched too (rev 2 watched them from 17 only, while 16.7.7 draws its clock with them as well).
static inline int MLWatchNames(int part, BOOL prominentClock, MLWatchName *out, int max) {
    static const MLWatchName clock[] = { {"SBFLockScreenDateView", NULL}, {"SBFLockScreenDateSubtitleView", NULL}, {"SBFLockScreenDateSubtitleDateView", NULL},
                                         {"SBFLockScreenDateViewController", NULL} };
    static const MLWatchName clock17[] = { {"CSProminentDisplayView", NULL}, {"CSProminentDisplayViewController", NULL}, {"CSProminentTimeView", NULL},
                                           {"CSProminentSubtitleDateView", NULL}, {"CSProminentTextElementView", NULL} };
    static const MLWatchName back[] = { {"SBFWallpaperView", "arallax"}, {"SBFStaticWallpaperView", "arallax"}, {"SBUIBackgroundView", NULL} };
    static const MLWatchName cards[] = { {"PLPlatterView", NULL}, {"NCNotificationShortLookView", "NumberOf"} };
    int n = 0;
    #define MLADD(arr) for (size_t i = 0; i < sizeof(arr) / sizeof(arr[0]) && n < max; i++) out[n++] = arr[i]
    switch (part) {
        case kMLPartClock: MLADD(clock); if (prominentClock) { MLADD(clock17); } break;
        case kMLPartBackground: MLADD(back); break;
        case kMLPartCards: MLADD(cards); break;
        default: break;
    }
    #undef MLADD
    return n;
}
// One part's method watch, kept between appearances (only changed implementations are judged again).
#define ML_WATCH_MAX 12
typedef struct { MLWatchedClass w[ML_WATCH_MAX]; int n; int built; } MLPartWatch;
static inline void MLPartWatchBuild(MLPartWatch *pw, int part, BOOL prominentClock) {
    if (pw->built) return;
    MLWatchName names[ML_WATCH_MAX];
    int n = MLWatchNames(part, prominentClock, names, ML_WATCH_MAX);
    memset(pw, 0, sizeof(*pw));
    for (int i = 0; i < n; i++) { pw->w[i].className = names[i].cls; pw->w[i].skip = names[i].skip; }
    pw->n = n; pw->built = 1;
}
// 1 when one of the part's watched own methods is another's; *cls / *sel / *image say which (the DEBUG log only).
static inline int MLPartMethodsForeign(const MLTable *t, MLPartWatch *pw, const char **cls, SEL *sel, const char **image) {
    uint32_t count = _dyld_image_count();
    for (int i = 0; i < pw->n; i++) {
        if (MLWatchedCheck(t, &pw->w[i], count)) {
            if (cls) *cls = pw->w[i].className;
            if (sel) *sel = pw->w[i].foreignSel;
            if (image) *image = pw->w[i].foreignImage;
            return 1;
        }
    }
    return 0;
}
