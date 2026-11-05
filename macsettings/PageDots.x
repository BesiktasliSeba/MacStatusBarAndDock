// PageDots.x -- no page dots on the Home Screen (the row of small dots below the icons showing which page you're on) — macOS's own
// equivalent, Launchpad, has none either. Replicates Lynx's "hidePageDots" (on there, never changed). Only the Home Screen's: iPadOS 18's
// Control Center keeps its page glyphs (1.7.1, PDHomeScreens below).
// Settings > Dock > Home Screen switches it (2026-09-25; shown on new installs, updates keep it hidden; applies after a respring).
//
// SBIconListPageControl (found by a class-name search, then confirmed by its own ivar: a delegate typed <SBIconListPageControlDelegate>)
// is a SpringBoard-only subclass of the ordinary PUBLIC UIPageControl — not a private, undocumented class with its own unknown lifecycle
// (see tonight's SBFloatingDockBehaviorAssertion incident in the memory notes): this only hooks -layoutSubviews, a method the OS already
// calls naturally and repeatedly on an object IT created, to force it hidden after the fact, and -setHidden:, the public setter every path
// that shows the dots again goes through (1.8.1). Nothing here is instantiated by us.
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#if DEBUG
#import <dlfcn.h>
#import <notify.h>
#import <substrate.h>
#endif
#import "../common/OtherTweaks.h"
#include "../common/PageDotsOwner.h"

#define PD_DOMAIN CFSTR("com.besiktasliseba.macpagedots")
static BOOL PDEnabled(void) {
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("enabled"), PD_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (!v) return NO;   // new installs show them (Settings > Dock > Show ...); an update keeps them hidden (sshtoggled --freeze-defaults)
    BOOL on = NO;   // (a boolean, or a number: an earlier Settings build stored the inverted switch as 0 / 1)
    if (CFGetTypeID(v) == CFBooleanGetTypeID()) on = CFBooleanGetValue(v);
    else if (CFGetTypeID(v) == CFNumberGetTypeID()) { int n = 0; CFNumberGetValue((CFNumberRef)v, kCFNumberIntType, &n); on = n != 0; }
    CFRelease(v);
    return on;
}

// Only the Home Screen's dots (common/PageDotsOwner.h): iPadOS 18's Control Center has an SBIconListPageControl too -- its page glyphs on the
// right -- whose folder view (the control's delegate) is ControlCenterUI's, not SpringBoard's (1.7.1 item 12).
static const char *PDOwnerImage(UIView *pc) {   // the image of the control's delegate's class (NULL: no delegate yet, or no getter)
    Method m = class_getInstanceMethod(object_getClass(pc), @selector(delegate));
    const char *t = m ? method_getTypeEncoding(m) : NULL;   // (an object getter: @16@0:8, read on 18.5)
    id owner = t && t[0] == '@' ? ((id (*)(id, SEL))objc_msgSend)(pc, @selector(delegate)) : nil;
    return owner ? class_getImageName([owner class]) : NULL;
}
static BOOL PDHomeScreens(UIView *pc) { return MSBDPageDotsHomeScreens(PDOwnerImage(pc)); }

#if DEBUG
// Debug (1.8.1 item 5): every change of a Home Screen page control's visibility, into our log while /tmp/macstatusbar-debug exists -- iPadOS asking
// to show the dots (kept hidden, or shown with Hide Page Dots off), a layout that found them showing, a control moving into a window -- each with
// its callers as image+offset (named on the Mac from the extracted image). com.besiktasliseba.macpagedots/dump writes every control's state.
static NSHashTable *gPDControls;   // (every page control seen, weak)
static void PDLog(NSString *line) {
    if (access("/tmp/macstatusbar-debug", F_OK) != 0) return;
    FILE *f = fopen("/tmp/macstatusbar.log", "a"); if (!f) return;
    fprintf(f, "[pagedots] %s\n", line.UTF8String); fclose(f);
}
static NSString *PDCallers(void) {   // the first callers outside this part and the runtime, as image+offset
    NSMutableArray *out = [NSMutableArray array];
    NSArray<NSNumber *> *ret = [NSThread callStackReturnAddresses];
    for (NSUInteger i = 1; i < ret.count && out.count < 7; i++) {
        Dl_info di; uintptr_t a = (uintptr_t)ret[i].unsignedLongLongValue & 0x0000000FFFFFFFFFULL;
        if (!dladdr((void *)a, &di) || !di.dli_fname) continue;
        const char *sl = strrchr(di.dli_fname, '/'), *img = sl ? sl + 1 : di.dli_fname;
        if (strstr(img, "MacPageDots") || strstr(img, "libobjc") || strstr(img, "libdispatch")) continue;
        [out addObject:[NSString stringWithFormat:@"%s+0x%lx", img, (unsigned long)(a - ((uintptr_t)di.dli_fbase & 0x0000000FFFFFFFFFULL))]];
    }
    return [out componentsJoinedByString:@" < "];
}
static NSString *PDState(UIView *pc) {
    BOOL shown = pc.window && !pc.hidden && pc.alpha > 0.01;
    for (UIView *s = pc.superview; shown && s; s = s.superview) if (s.hidden || s.alpha < 0.01) shown = NO;
    const char *img = PDOwnerImage(pc), *sl = img ? strrchr(img, '/') : NULL;
    id owner = [pc respondsToSelector:@selector(delegate)] && img ? ((id (*)(id, SEL))objc_msgSend)(pc, @selector(delegate)) : nil;
    return [NSString stringWithFormat:@"%p (%@ in %s, window %@, pages %ld, frame %@): hidden %d alpha %.2f -> %@", pc, owner ? NSStringFromClass([owner class]) : @"no folder view",
            sl ? sl + 1 : (img ?: "-"), pc.window ? NSStringFromClass([pc.window class]) : @"none", (long)((UIPageControl *)pc).numberOfPages, NSStringFromCGRect(pc.frame),
            pc.hidden, pc.alpha, shown ? @"ON THE SCREEN" : @"not on the screen"];
}
static void PDSeen(UIView *pc) {
    if (!gPDControls) {
        gPDControls = [NSHashTable weakObjectsHashTable];
        int t; notify_register_dispatch("com.besiktasliseba.macpagedots/dump", &t, dispatch_get_main_queue(), ^(int tok) {
            PDLog([NSString stringWithFormat:@"dump: Hide Page Dots %d, %lu page controls", PDEnabled(), (unsigned long)gPDControls.count]);
            for (UIView *v in gPDControls.allObjects) PDLog([@"  " stringByAppendingString:PDState(v)]);
        });
    }
    [gPDControls addObject:pc];
}
#endif

%hook SBIconListPageControl
- (void)layoutSubviews {
    %orig;
    if (PDEnabled() && PDHomeScreens((UIView *)self) && !MSBDOtherTweakDoing(kMSBDDupPageDots, YES)) {   // (Lynx hides them already: left to it)
#if DEBUG
        PDSeen((UIView *)self);
        if (!((UIView *)self).hidden && ((UIView *)self).window) PDLog([NSString stringWithFormat:@"a layout found the dots showing: hidden now. %@ <- %@", PDState((UIView *)self), PDCallers()]);
#endif
        ((UIView *)self).hidden = YES;
    }
}
// The dots are shown again through -setHidden: on paths that lay nothing out after it (common/PageDotsOwner.h MSBDPageDotsStoreHidden): a folder
// tweak's folder closing (ClassicFolders3: the M1's dots seen now and then), a turn of the screen ending with SBRootFolderController's
// -setPageControlHidden:NO, the page editor handing its control back visible, UIPageControl setting hidden from a new page count. With Hide Page
// Dots on, the Home Screen's stay hidden on each of them (1.8.1 item 5).
// Debug: /tmp/msb-pagedots-nohold stores what iPadOS asks (the behaviour before 1.8.1, to compare).
- (void)setHidden:(BOOL)hidden {
    BOOL hide = PDEnabled() && !MSBDOtherTweakDoing(kMSBDDupPageDots, YES);
#if DEBUG
    if (access("/tmp/msb-pagedots-nohold", F_OK) == 0) hide = NO;
#endif
    BOOL store = MSBDPageDotsStoreHidden(hide, PDOwnerImage((UIView *)self), hidden) != 0;
#if DEBUG
    if (PDHomeScreens((UIView *)self)) {
        PDSeen((UIView *)self);
        if (!hidden && ((UIView *)self).hidden) PDLog([NSString stringWithFormat:@"iPadOS asks to show the dots: %@. %@ <- %@", store ? @"kept hidden" : @"shown", PDState((UIView *)self), PDCallers()]);
    }
#endif
    %orig(store);
}
%end

#if DEBUG
static void (*o_PDDidMoveToWindow)(id, SEL);
static void PDDidMoveToWindow(id self, SEL _cmd) {   // (debug: a control moving into a window)
    o_PDDidMoveToWindow(self, _cmd);
    if (!((UIView *)self).window || !PDHomeScreens((UIView *)self)) return;
    PDSeen((UIView *)self);
    PDLog([NSString stringWithFormat:@"moved into a window: %@", PDState((UIView *)self)]);
}
#endif

%ctor {
    %init;
#if DEBUG
    Class pc = objc_getClass("SBIconListPageControl");
    if (pc) MSHookMessageEx(pc, @selector(didMoveToWindow), (IMP)PDDidMoveToWindow, (IMP *)&o_PDDidMoveToWindow);
#endif
}
