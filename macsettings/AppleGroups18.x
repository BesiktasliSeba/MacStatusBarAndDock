// AppleGroups18.x -- iPadOS 18 (1.6.0, KT's goal): our keyboard and pointer settings with Apple's own, as a group at the top of Apple's pages:
//   General > Keyboard > Hardware Keyboard (TIHardwareKeyboardController, KeyboardSettings.bundle): "Mac Keys" -- Top-Left Key as Escape, Tab mute,
//     Globe volume, the two brightness pairs -- with the footer our Keyboard page has (its hint's "Modifier Keys" link opens Apple's row below);
//   General > Trackpad / Mouse (PSGMousePointerViewController): "Mac Pointer" -- Pointer Style, then (Mac pointer) Hide in Virtual Mac and Use
//     Pointer Control Style, and Block Pointer Pull-Down.
// Apple's rows stay as they are. Why only 18: 18 builds Settings' root list in SwiftUI (no PSUIPrefsListController), so our sidebar rows with their
// own Keyboard and Pointer pages (15-17, unchanged) cannot be there; they are in our group at the top of General instead (MacSettings.x).
// When one of our own pages shows Apple's rows (it makes Apple's page, never shown: common/NativeEmbed.h), nothing is put into that page: our page
// has our rows already.
// Both pages are still PSListControllers on 18.5 (their lists __NSArrayM, read with our spec dump): our rows go in right after a page hands its list
// out, through the page's own insert call (as General's interim group does), and again whenever the page builds its list anew. Each page and call
// is checked first (class, -specifiers, the insert call's types); anything else: nothing is put in, logged.
// Our rows read and write their preferences through a helper of ours (MSG18Prefs), never Apple's page: the page may handle its own preferences
// differently (the keyboard's go through TextInput), ours are plain CFPreferences with the notification each feature listens to.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#import <unistd.h>
#import <mach-o/dyld.h>
#include <stdatomic.h>
#include <substrate.h>
#import "../common/NativeEmbed.h"

@interface PSSpecifier : NSObject
- (NSString *)identifier;
- (id)propertyForKey:(NSString *)key;
- (long long)cellType;
@end
@interface PSListController : UIViewController
- (NSMutableArray *)specifiers;
@end

NSArray *MSKeysGroupSpecifiers(id target, NSString *title, NSArray *native, id linkTarget);   // (KeyboardSettings.x)
void MSKeysOpenModifierKeysOn(PSListController *page);                                       // (KeyboardSettings.x)
NSArray *MSPointerOwnSpecifiers(id target, BOOL onApplePage);                                 // (PointerSettings.x)

static void G18Log(NSString *line) {   // (debug builds: the macsettings log)
#if DEBUG
    if (access("/tmp/macsettings-debug", F_OK) != 0) return;
    FILE *f = fopen("/tmp/macsettings.log", "a");
    if (f) { fprintf(f, "[groups18] %s\n", line.UTF8String); fclose(f); }
#endif
}

// ---- reading and writing our rows' preferences (what PSListController does for a specifier with "defaults" and "key") ----
@interface MSG18Prefs : NSObject
@property (nonatomic, weak) PSListController *page;   // (the Apple page our rows are on: the keys' footer link opens its Modifier Keys row)
@end
@implementation MSG18Prefs
- (id)readPreferenceValue:(PSSpecifier *)spec {
    NSString *domain = [spec propertyForKey:@"defaults"], *key = [spec propertyForKey:@"key"];
    if (![domain isKindOfClass:[NSString class]] || ![key isKindOfClass:[NSString class]]) return nil;
    CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
    id v = (__bridge_transfer id)CFPreferencesCopyValue((__bridge CFStringRef)key, (__bridge CFStringRef)domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    return v ?: [spec propertyForKey:@"default"];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)spec {
    NSString *domain = [spec propertyForKey:@"defaults"], *key = [spec propertyForKey:@"key"], *note = [spec propertyForKey:@"PostNotification"];
    if (![domain isKindOfClass:[NSString class]] || ![key isKindOfClass:[NSString class]]) return;
    CFPreferencesSetValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, (__bridge CFStringRef)domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize((__bridge CFStringRef)domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if ([note isKindOfClass:[NSString class]] && note.length) notify_post(note.UTF8String);
    G18Log([NSString stringWithFormat:@"%@ %@ = %@", domain, key, value]);
}
- (void)msOpenModifierKeys { PSListController *p = self.page; if (p) MSKeysOpenModifierKeysOn(p); }
@end

// ---- the two pages ----
// (a method's return and argument types, offsets aside, as expected)
static BOOL G18Types(Class c, SEL sel, const char *ret, NSArray<NSString *> *args) {
    Method m = c ? class_getInstanceMethod(c, sel) : NULL;
    BOOL ok = m && method_getNumberOfArguments(m) == args.count + 2;
    if (ok) { char r[16] = {0}; method_getReturnType(m, r, sizeof(r)); ok = strcmp(r, ret) == 0; }
    for (NSUInteger i = 0; ok && i < args.count; i++) { char a[16] = {0}; method_getArgumentType(m, (unsigned)(i + 2), a, sizeof(a)); ok = strcmp(a, args[i].UTF8String) == 0; }
    return ok;
}
static BOOL G18PageOK(Class c) {
    Class list = objc_getClass("PSListController");
    return c && list && [c isSubclassOfClass:list] && G18Types(c, @selector(specifiers), "@", @[])
        && G18Types(c, NSSelectorFromString(@"insertContiguousSpecifiers:atIndex:animated:"), "v", @[@"@", @"q", @"B"])
        && G18Types(c, NSSelectorFromString(@"removeContiguousSpecifiers:animated:"), "v", @[@"@", @"B"]);
}
static const void *kG18PrefsKey = &kG18PrefsKey, *kG18TriedKey = &kG18TriedKey, *kG18OursKey = &kG18OursKey, *kG18SigKey = &kG18SigKey;
typedef NS_ENUM(int, G18Kind) { G18Keyboard = 1, G18Pointer = 2 };
static G18Kind G18KindOf(id page) {
    Class k = objc_getClass("TIHardwareKeyboardController"), p = objc_getClass("PSGMousePointerViewController");
    if (k && [page isKindOfClass:k]) return G18Keyboard;
    if (p && [page isKindOfClass:p]) return G18Pointer;
    return 0;
}
// Our rows on that page now, built anew (the keys' footer reads the switches and Apple's Modifier Keys; the pointer's Mac rows follow the style).
static NSArray *G18Rows(PSListController *page, G18Kind kind, NSArray *apple) {
    MSG18Prefs *prefs = objc_getAssociatedObject(page, kG18PrefsKey);
    if (!prefs) { prefs = [MSG18Prefs new]; prefs.page = page; objc_setAssociatedObject(page, kG18PrefsKey, prefs, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    return kind == G18Keyboard ? MSKeysGroupSpecifiers(prefs, @"Mac Keys", apple, prefs) : MSPointerOwnSpecifiers(prefs, YES);
}
// What our rows show, as a string: each row's id (or name) and cell type, and each group's footer. Equal: nothing to put in again.
static NSString *G18Signature(NSArray *rows) {
    NSMutableString *sig = [NSMutableString string];
    for (PSSpecifier *sp in rows) {
        id foot = [sp propertyForKey:@"footerText"];
        [sig appendFormat:@"%@|%lld|%@\n", [sp identifier] ?: @"", [sp respondsToSelector:@selector(cellType)] ? [sp cellType] : -1LL, [foot isKindOfClass:[NSString class]] ? foot : @""];
    }
    return sig;
}
// Puts our rows at the top of the page (or puts them in again, built anew: refresh -- only when what they show has changed: a switch of ours being
// flipped keeps its cell, 1.6.0 code review). Only on the main thread, after the page handed its list out.
static void G18Insert(PSListController *page, BOOL refresh) {
    G18Kind kind = G18KindOf(page);
    if (!kind || !G18PageOK(object_getClass(page))) return;
    NSArray *specs = ((id (*)(id, SEL))objc_msgSend)(page, @selector(specifiers));
    if (![specs isKindOfClass:[NSArray class]]) return;
    NSArray *ours = objc_getAssociatedObject(page, kG18OursKey);
    BOOL there = ours.count && [specs containsObject:ours.firstObject];
    if (there && !refresh) return;
    @try {
        NSArray *rows = G18Rows(page, kind, specs);
        if (!rows.count) return;
        NSString *sig = G18Signature(rows);
        if (there && [sig isEqualToString:objc_getAssociatedObject(page, kG18SigKey)]) return;   // (the same rows: they stay as they are)
        if (there) {
            NSMutableArray *present = [NSMutableArray array];
            for (id sp in ours) if ([specs containsObject:sp]) [present addObject:sp];
            ((void (*)(id, SEL, id, BOOL))objc_msgSend)(page, NSSelectorFromString(@"removeContiguousSpecifiers:animated:"), present, NO);
            specs = ((id (*)(id, SEL))objc_msgSend)(page, @selector(specifiers));
        }
        ((void (*)(id, SEL, id, long long, BOOL))objc_msgSend)(page, NSSelectorFromString(@"insertContiguousSpecifiers:atIndex:animated:"), rows, 0LL, NO);
        objc_setAssociatedObject(page, kG18OursKey, rows, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(page, kG18SigKey, sig, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        G18Log([NSString stringWithFormat:@"%@: %lu row(s) of ours %@ at the top of %lu", NSStringFromClass([page class]), (unsigned long)rows.count, there ? @"put in again" : @"put", (unsigned long)specs.count]);
    } @catch (NSException *e) { G18Log([NSString stringWithFormat:@"%@: insert failed: %@", NSStringFromClass([page class]), e.reason]); }
}
// While one of the pages is open: a switch of ours changed (the keys' footer hint), the Pointer Style changed (the Mac rows come or go). Looked at
// once the switch has finished moving (0.4 s; several changes in that time: one look).
static __weak PSListController *gG18Shown;
static void G18Watch(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;
    static BOOL pending = NO;
    for (NSString *n in @[@"com.besiktasliseba.macstatusbar/prefsChanged", @"com.besiktasliseba.volumeglobetweak/prefsChanged", @"com.besiktasliseba.brightnesskeytweak/prefsChanged"]) {
        int t = 0;
        notify_register_dispatch(n.UTF8String, &t, dispatch_get_main_queue(), ^(int token) {
            if (pending) return;
            pending = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                pending = NO;
                PSListController *p = gG18Shown;
                if (p && p.viewIfLoaded.window) G18Insert(p, YES);
            });
        });
    }
}

static id (*o_G18KeyboardSpecifiers)(id, SEL), (*o_G18PointerSpecifiers)(id, SEL);
static void (*o_G18KeyboardWillAppear)(id, SEL, BOOL), (*o_G18PointerWillAppear)(id, SEL, BOOL);
// (once the list is handed out, on the next turn of the main loop; asked for again and again while it is built: one try a second at most)
static id G18AfterSpecifiers(id self, id specs) {
    if (![specs isKindOfClass:[NSArray class]]) return specs;
    if (MSNEIsEmbedded(self)) return specs;   // (Apple's page made by our Keyboard / Pointer page for its rows: never shown, ours are on that page)
    NSArray *ours = objc_getAssociatedObject(self, kG18OursKey);
    if (ours.count && [specs containsObject:ours.firstObject]) return specs;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSNumber *tried = objc_getAssociatedObject(self, kG18TriedKey);
    if (tried && now - tried.doubleValue < 1.0) return specs;
    objc_setAssociatedObject(self, kG18TriedKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak PSListController *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{ PSListController *l = weakSelf; if (l) G18Insert(l, NO); });
    return specs;
}
static id G18KeyboardSpecifiers(id self, SEL _cmd) { return G18AfterSpecifiers(self, o_G18KeyboardSpecifiers(self, _cmd)); }
static id G18PointerSpecifiers(id self, SEL _cmd) { return G18AfterSpecifiers(self, o_G18PointerSpecifiers(self, _cmd)); }
// (back on the page -- from Modifier Keys, a keyboard layout, Pointer Style's list: our rows built anew, so the footer and the Mac rows are current)
static void G18WillAppear(id self, BOOL refresh) {
    gG18Shown = self;
    G18Watch();
    __weak PSListController *weakSelf = self;
    if (refresh) dispatch_async(dispatch_get_main_queue(), ^{ PSListController *l = weakSelf; if (l) G18Insert(l, YES); });
}
static void G18KeyboardWillAppear(id self, SEL _cmd, BOOL animated) { o_G18KeyboardWillAppear(self, _cmd, animated); G18WillAppear(self, objc_getAssociatedObject(self, kG18OursKey) != nil); }
static void G18PointerWillAppear(id self, SEL _cmd, BOOL animated) { o_G18PointerWillAppear(self, _cmd, animated); G18WillAppear(self, objc_getAssociatedObject(self, kG18OursKey) != nil); }

// The SwiftUI root of iPadOS 18 (no PSUIPrefsListController): where our sidebar rows and pages cannot be. 15-17: NO, nothing here runs.
static BOOL G18Root(void) { return objc_getClass("PSUIPrefsListController") == Nil && objc_getClass("PSListController") != Nil; }
// Installed once each page's class is there (General's comes with Settings, the keyboard's with its bundle): looked for as each image is added,
// and once more on the main queue after it -- a class that comes with an image is not always there yet while dyld tells of that image (18.5: the
// keyboard bundle loaded by our Keyboard page, the class found only at a later image; before 1.6.0's General shortcuts the bundle was loaded with
// General's list, so a later image always came first). Claimed with an atomic compare-and-swap, never a lock (inside dyld's add-image callback:
// MacSettings.x MSGeneral18Install).
static void G18Hook(Class c, IMP specs, IMP *oSpecs, IMP willAppear, IMP *oWillAppear) {
    MSHookMessageEx(c, @selector(specifiers), specs, oSpecs);
    // (-viewWillAppear: is UIViewController's when the page has none of its own: added on the page's class only, so nothing else changes)
    Method m = class_getInstanceMethod(c, @selector(viewWillAppear:));
    if (class_addMethod(c, @selector(viewWillAppear:), willAppear, method_getTypeEncoding(m))) *oWillAppear = method_getImplementation(m);
    else MSHookMessageEx(c, @selector(viewWillAppear:), willAppear, oWillAppear);
}
static atomic_int gG18KeyboardClaimed = 0, gG18PointerClaimed = 0;
static void G18Install(BOOL later) {
    atomic_int *keyboard = &gG18KeyboardClaimed, *pointer = &gG18PointerClaimed;
    if (atomic_load_explicit(keyboard, memory_order_acquire) && atomic_load_explicit(pointer, memory_order_acquire)) return;
    if (!G18Root()) return;
    int expected = 0;
    Class k = objc_getClass("TIHardwareKeyboardController");
    if (k && atomic_compare_exchange_strong(keyboard, &expected, 1)) {
        if (G18PageOK(k)) { G18Hook(k, (IMP)G18KeyboardSpecifiers, (IMP *)&o_G18KeyboardSpecifiers, (IMP)G18KeyboardWillAppear, (IMP *)&o_G18KeyboardWillAppear); G18Log(later ? @"Hardware Keyboard: our keys go at the top (found on the main queue after an image)" : @"Hardware Keyboard: our keys go at the top"); }
        else G18Log(@"Hardware Keyboard's page is not as expected: our keys stay out");
    }
    expected = 0;
    Class p = objc_getClass("PSGMousePointerViewController");
    if (p && atomic_compare_exchange_strong(pointer, &expected, 1)) {
        if (G18PageOK(p)) { G18Hook(p, (IMP)G18PointerSpecifiers, (IMP *)&o_G18PointerSpecifiers, (IMP)G18PointerWillAppear, (IMP *)&o_G18PointerWillAppear); G18Log(later ? @"Trackpad / Mouse: our pointer rows go at the top (found on the main queue after an image)" : @"Trackpad / Mouse: our pointer rows go at the top"); }
        else G18Log(@"Trackpad / Mouse's page is not as expected: our pointer rows stay out");
    }
}
static void G18ImageAdded(const struct mach_header *mh, intptr_t slide) {
    G18Install(NO);
    if (atomic_load_explicit(&gG18KeyboardClaimed, memory_order_acquire) && atomic_load_explicit(&gG18PointerClaimed, memory_order_acquire)) return;
    static atomic_int queued = 0;   // (one look on the main queue for a burst of images)
    int expected = 0;
    if (atomic_compare_exchange_strong(&queued, &expected, 1)) dispatch_async(dispatch_get_main_queue(), ^{ atomic_store(&queued, 0); G18Install(YES); });
}
%ctor {
    if (G18Root()) _dyld_register_func_for_add_image(G18ImageAdded);   // (15-17: nothing)
}
