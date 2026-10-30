// CCModuleRegister.h -- RAM & CPU (ccmodule/, MacRAMCPU.bundle) as one of Control Center's modules, without CCSupport: its folder is one of the
// module folders and its identifier is on the allowed list in every module repository this process makes -- SpringBoard (Control Center and
// iPadOS 18's "Add a Control" gallery; called from MacCCGrabber) and Settings on 15-17 (Control Center's page; called from MacSettings).
// CCSModuleRepository's +_defaultModuleDirectories, +_defaultModuleIdentifierAllowedList ("@16@0:8") and -_initWithDirectoryURLs:
// allowedModuleIdentifiers: ("@32@0:8@16@24") -- the same on 17.5 and 18.5 -- each get ours added once; a method that is not there or has another
// shape is left alone, and nothing else changes. (CCSupport, where installed, loads its own folder; ours is a folder of our own, so neither sees
// the other's.)
// Not while the crash guard's step 1b has the module on its skip list (the line "skip MacRAMCPU", common/CrashStep.h; tools/crashmap-rules.txt):
// then Control Center never loads it, until the guard's note is cleared.
#pragma once
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <substrate.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>

#include "CCModuleList.h"   // (and MSBDCCModuleSkipped: step 1b's skip list names the module, and the guard's note is still there)
#if DEBUG   // (debug builds: which process registered, and the folders each repository is made with -> /tmp/macsettings.log with /tmp/macsettings-debug)
static void MSBDCCDebugLog(NSString *line) {
    if (access("/tmp/macsettings-debug", F_OK) != 0) return;
    FILE *f = fopen("/tmp/macsettings.log", "a"); if (!f) return;
    fprintf(f, "%.3f [ccmodule] %s (%s): %s\n", CFAbsoluteTimeGetCurrent(), [NSProcessInfo processInfo].processName.UTF8String, [NSThread isMainThread] ? "main" : "other thread", line.UTF8String); fclose(f);
}
#else
#define MSBDCCDebugLog(...) do {} while (0)
#endif
static id (*gMSBDCCOrigDirs)(id, SEL);
static id MSBDCCDirs(id self, SEL _cmd) { MSBDCCDebugLog(@"default folders asked"); return MSBDCCWithOurDirectory(gMSBDCCOrigDirs(self, _cmd)); }
static id (*gMSBDCCOrigAllowed)(id, SEL);
static id MSBDCCAllowed(id self, SEL _cmd) { MSBDCCDebugLog(@"default allowed list asked"); return MSBDCCWithOurIdentifier(gMSBDCCOrigAllowed(self, _cmd)); }
static id (*gMSBDCCOrigInit)(id, SEL, NSArray *, id);
static id MSBDCCInit(id self, SEL _cmd, NSArray *dirs, id allowed) {
    NSArray *withOurs = MSBDCCWithOurDirectory(dirs);
    MSBDCCDebugLog([NSString stringWithFormat:@"repository made with %lu folder(s), ours %@, allowed %@", (unsigned long)withOurs.count, withOurs.count > dirs.count ? @"added" : @"already there", allowed ? @"a list" : @"none"]);
    return gMSBDCCOrigInit(self, _cmd, withOurs, MSBDCCWithOurIdentifier(allowed));
}

// iPadOS 18: Control Center's settings for a module that is not in its DefaultModuleSettings.plist say 1 x 1 (CCUIIconGridSizeClassSmall); ours
// is 2 x 1 only (-supportedGridSizeClasses), so the gallery's search showed it at the Home Screen's small size and Control Center threw on that
// size ("Unimplemented Control Center grid size class: SBHIconGridSizeClassSmall" -- SpringBoard crashed, A12Z 18.5). Its settings now say 2 x 1,
// as Apple's own 2 x 1 module (Focus) has them; every other module's settings are as Control Center made them.
#include <dlfcn.h>
static NSString *MSBDCCSmallWide(void) {
    static NSString *v; static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *h = dlopen("/System/Library/PrivateFrameworks/ControlCenterUIServices.framework/ControlCenterUIServices", RTLD_LAZY | RTLD_NOLOAD);
        NSString *(*f)(long long) = h ? (NSString *(*)(long long))dlsym(h, "SBHIconGridSizeClassForCCUIGridSizeClass") : NULL;
        NSString *got = f ? f(2) : nil;   // (2: smallWide, as -supportedGridSizeClasses counts them)
        v = [got isKindOfClass:[NSString class]] && [got isEqualToString:@"CCUIIconGridSizeClassSmallWide"] ? got : @"CCUIIconGridSizeClassSmallWide";
    });
    return v;
}
static id (*gMSBDCCOrigSettings)(id, SEL, NSString *);
static id MSBDCCSettings(id self, SEL _cmd, NSString *mid) {
    id s = gMSBDCCOrigSettings(self, _cmd, mid);
    if (!s || ![mid isKindOfClass:[NSString class]] || ![mid isEqualToString:kMSBDCCModuleID]) return s;
    SEL gs = NSSelectorFromString(@"gridSizeClass"), ss = NSSelectorFromString(@"setGridSizeClass:");
    if (![s respondsToSelector:gs] || ![s respondsToSelector:ss] || ![s respondsToSelector:@selector(copyWithZone:)]) return s;
    id grid = ((id (*)(id, SEL))objc_msgSend)(s, gs);
    if ([grid isEqual:MSBDCCSmallWide()]) return s;
    id mine = [s copy];
    ((void (*)(id, SEL, id))objc_msgSend)(mine, ss, MSBDCCSmallWide());
    return mine;
}
static void MSBDCCModuleSettingsHook(void) {   // (SpringBoard, 18: CCUIModuleSettingsManager lives in ControlCenterUI)
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class m = objc_getClass("CCUIModuleSettingsManager");
        SEL q = NSSelectorFromString(@"moduleSettingsForModuleIdentifier:");
        Method mm = m ? class_getInstanceMethod(m, q) : NULL;
        if (mm && method_getTypeEncoding(mm) && !strcmp(method_getTypeEncoding(mm), "@24@0:8@16") && objc_getClass("CCUIModuleSettings"))
            MSHookMessageEx(m, q, (IMP)MSBDCCSettings, (IMP *)&gMSBDCCOrigSettings);
    });
}

// Where CCSModuleRepository exists (ControlCenterServices loaded); once. How many of the three methods it took (0: none there, or skipped).
static int gMSBDCCHooked = -1;
static int MSBDCCModuleRegister(void) {
    if (gMSBDCCHooked >= 0) return gMSBDCCHooked;
    int done = 0;
    gMSBDCCHooked = 0;
    if (MSBDCCModuleSkipped()) return 0;
    if (![[NSFileManager defaultManager] fileExistsAtPath:[kMSBDCCModuleDir stringByAppendingPathComponent:@"MacRAMCPU.bundle/Info.plist"]]) return 0;
    Class c = objc_getClass("CCSModuleRepository");
    if (!c) return 0;
    Class meta = object_getClass(c);
    SEL ds = NSSelectorFromString(@"_defaultModuleDirectories"), as = NSSelectorFromString(@"_defaultModuleIdentifierAllowedList");
    SEL is = NSSelectorFromString(@"_initWithDirectoryURLs:allowedModuleIdentifiers:");
    Method dm = class_getInstanceMethod(meta, ds), am = class_getInstanceMethod(meta, as), im = class_getInstanceMethod(c, is);
    if (dm && method_getTypeEncoding(dm) && !strcmp(method_getTypeEncoding(dm), "@16@0:8")) { MSHookMessageEx(meta, ds, (IMP)MSBDCCDirs, (IMP *)&gMSBDCCOrigDirs); done++; }
    if (am && method_getTypeEncoding(am) && !strcmp(method_getTypeEncoding(am), "@16@0:8")) { MSHookMessageEx(meta, as, (IMP)MSBDCCAllowed, (IMP *)&gMSBDCCOrigAllowed); done++; }
    if (im && method_getTypeEncoding(im) && !strcmp(method_getTypeEncoding(im), "@32@0:8@16@24")) { MSHookMessageEx(c, is, (IMP)MSBDCCInit, (IMP *)&gMSBDCCOrigInit); done++; }
    gMSBDCCHooked = done;
    MSBDCCDebugLog([NSString stringWithFormat:@"registered: %d of 3 repository methods taken", done]);
    if (done && [NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 18) {   // (the settings manager: ControlCenterUI, loaded with SpringBoard)
        if (objc_getClass("CCUIModuleSettingsManager")) MSBDCCModuleSettingsHook();
        else dispatch_async(dispatch_get_main_queue(), ^{ MSBDCCModuleSettingsHook(); });
    }
    return done;
}
// From a part's constructor: now if ControlCenterServices is already loaded (SpringBoard), else as soon as it is (Settings opens Control
// Center's page on 15-17), once, from whichever of these comes first:
//  - the bundle Settings loads for a page (-[NSBundle loadAndReturnError:], -load goes through it) has just been loaded: the page is made only
//    after that, so its module repository is made through our hooks. The image callback alone came too late on 15.6.1: iPadOS's dyld tells its
//    add-image listeners about ControlCenterServices before the Objective-C runtime has its classes, so the first image that found
//    CCSModuleRepository was CCSupport's HomeProvider.bundle, loaded after the page had made its repository -- Control Center's page, opened from
//    Settings' own list, listed every control but RAM & CPU (M1, 1.6.0; a cold link to the page came the other way round, by luck of order).
//  - an image added (every image, the ones already loaded too: one class lookup each, until it is done) -- for a framework loaded some other way.
#include <mach-o/dyld.h>
static void MSBDCCTryRegister(const char *why) {
    if (gMSBDCCHooked >= 0 || !objc_getClass("CCSModuleRepository")) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        MSBDCCDebugLog([NSString stringWithFormat:@"the class is there (%s)", why]);
        MSBDCCModuleRegister();
    });
}
static void MSBDCCImageAdded(const struct mach_header *mh, intptr_t slide) {
    if (gMSBDCCHooked >= 0) return;
#if DEBUG
    Dl_info di; const char *name = (mh && dladdr(mh, &di) && di.dli_fname) ? di.dli_fname : "an image";
    MSBDCCTryRegister(name);
#else
    MSBDCCTryRegister("an image");
#endif
}
static BOOL (*gMSBDCCOrigBundleLoad)(NSBundle *, SEL, NSError **);
static BOOL MSBDCCBundleLoad(NSBundle *self, SEL _cmd, NSError **error) {
    BOOL ok = gMSBDCCOrigBundleLoad(self, _cmd, error);
    if (gMSBDCCHooked < 0) MSBDCCTryRegister("a bundle just loaded");
    return ok;
}
static void MSBDCCModuleRegisterWhenLoaded(void) {
    if (objc_getClass("CCSModuleRepository")) { MSBDCCTryRegister("already loaded"); return; }
    SEL ls = @selector(loadAndReturnError:);
    Method lm = class_getInstanceMethod([NSBundle class], ls);
    if (lm && method_getTypeEncoding(lm) && !strcmp(method_getTypeEncoding(lm), "B24@0:8^@16")) MSHookMessageEx([NSBundle class], ls, (IMP)MSBDCCBundleLoad, (IMP *)&gMSBDCCOrigBundleLoad);
    _dyld_register_func_for_add_image(MSBDCCImageAdded);
}
