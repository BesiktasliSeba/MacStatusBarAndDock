// CCModuleRegister.h -- our Control Center controls as Control Center's own modules, without CCSupport: RAM & CPU (ccmodule/, MacRAMCPU.bundle)
// and, from 1.7.6, SSH (MacSSH.bundle). Each one's folder is one of the module folders and its identifier is on the allowed list in every module
// repository this process makes -- SpringBoard (Control Center and iPadOS 18's "Add a Control" gallery; called from MacCCGrabber) and Settings on
// 15-17 (Control Center's page; called from MacSettings). Only the controls that are to load now (CCModuleList.h, MSBDCCActiveControls: the
// bundle in place, not on step 1b's skip list, SSH with OpenSSH installed): the others are not in the repository at all.
// CCSModuleRepository's +_defaultModuleDirectories, +_defaultModuleIdentifierAllowedList ("@16@0:8") and -_initWithDirectoryURLs:
// allowedModuleIdentifiers: ("@32@0:8@16@24") -- the same on 17.5 and 18.5 -- each get ours added once; a method that is not there or has another
// shape is left alone, and nothing else changes. (CCSupport, where installed, loads its own folder; ours are folders of our own, so neither sees
// the other's.)
// Not while the crash guard's step 1b has a control on its skip list (the line "skip MacRAMCPU" or "skip MacSSH", common/CrashStep.h;
// tools/crashmap-rules.txt): then Control Center never loads it, until the guard's note is cleared.
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
static NSArray<NSString *> *gMSBDCCFolders, *gMSBDCCIdentifiers;   // (the controls to load, MSBDCCActiveControls: set once, before the hooks)
static id (*gMSBDCCOrigDirs)(id, SEL);
static id MSBDCCDirs(id self, SEL _cmd) { MSBDCCDebugLog(@"default folders asked"); return MSBDCCWithOurDirectories(gMSBDCCOrigDirs(self, _cmd), gMSBDCCFolders); }
static id (*gMSBDCCOrigAllowed)(id, SEL);
static id MSBDCCAllowed(id self, SEL _cmd) { MSBDCCDebugLog(@"default allowed list asked"); return MSBDCCWithOurIdentifiers(gMSBDCCOrigAllowed(self, _cmd), gMSBDCCIdentifiers); }
static id (*gMSBDCCOrigInit)(id, SEL, NSArray *, id);
static id MSBDCCInit(id self, SEL _cmd, NSArray *dirs, id allowed) {
    NSArray *withOurs = MSBDCCWithOurDirectories(dirs, gMSBDCCFolders);
    MSBDCCDebugLog([NSString stringWithFormat:@"repository made with %lu folder(s), %lu of ours added, allowed %@", (unsigned long)withOurs.count, (unsigned long)(withOurs.count - ([dirs isKindOfClass:[NSArray class]] ? dirs.count : 0)), allowed ? @"a list" : @"none"]);
    return gMSBDCCOrigInit(self, _cmd, withOurs, MSBDCCWithOurIdentifiers(allowed, gMSBDCCIdentifiers));
}

// iPadOS 18: Control Center takes each module's grid size and app ("container") from its settings: ControlCenterUI's DefaultModuleSettings.plist
// for Apple's modules (Alarm, Stopwatch, Timer -> com.apple.mobiletimer, Focus 2 x 1 -> com.apple.springboard, ...), and for any module not
// listed there 1 x 1 (CCUIIconGridSizeClassSmall) and com.apple.springboard (-[CCUIModuleSettingsManager moduleSettingsForModuleIdentifier:],
// 18.5). Ours are given theirs as that file gives Apple's:
//  - RAM & CPU: 2 x 1, the only size it has (-supportedGridSizeClasses): with the 1 x 1 default the gallery's search showed it at the Home Screen's
//    small size and Control Center threw on that size ("Unimplemented Control Center grid size class: SBHIconGridSizeClassSmall" -- SpringBoard
//    crashed, A12Z 18.5, 1.6.0); and Activity Monitor as its app (1.7.6 item 3): "Add a Control" lists every control that is not in one of
//    Apple's own sections under its app, by this container -- RAM & CPU was under "SpringBoard". Activity Monitor is no installed app, so its
//    section gets its name and picture from the status bar part (statusbar/AppLibraryApps.h, DMALCollIcon): only while that part says it names
//    that section (MSBDCCActivityMonitorSectionReady, whatever Show in App Library says); else SpringBoard as before.
//  - SSH: 1 x 1, with Settings as its app (its switch is in Settings, as Remote Login is in a Mac's System Settings; the status bar part gives the
//    section the Settings app's own icon).
// Every other module's settings are as Control Center made them.
#include <dlfcn.h>
static NSString *MSBDCCGridSize(long long ccuiClass, NSString *fallback) {   // (Control Center's own name for a grid size class)
    static NSString *(*f)(long long); static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *h = dlopen("/System/Library/PrivateFrameworks/ControlCenterUIServices.framework/ControlCenterUIServices", RTLD_LAZY | RTLD_NOLOAD);
        f = h ? (NSString *(*)(long long))dlsym(h, "SBHIconGridSizeClassForCCUIGridSizeClass") : NULL;
    });
    NSString *got = f ? f(ccuiClass) : nil;
    return [got isKindOfClass:[NSString class]] && [got isEqualToString:fallback] ? got : fallback;
}
static NSString *MSBDCCSmallWide(void) { return MSBDCCGridSize(2, @"CCUIIconGridSizeClassSmallWide"); }   // (2: smallWide, as -supportedGridSizeClasses counts them)
static NSString *MSBDCCSmall(void) { return MSBDCCGridSize(0, @"CCUIIconGridSizeClassSmall"); }           // (0: small, Control Center's own default)
static NSString *MSBDCCContainerFor(NSString *mid) {   // (CCModuleList.h; Activity Monitor while the status bar part names its section)
    static BOOL (*ready)(void);
    if (!ready) ready = (BOOL (*)(void))dlsym(RTLD_DEFAULT, kMSBDCCActivityMonitorSectionFn);   // (found once the status bar part is loaded)
    return MSBDCCContainerForModule(mid, ready && ready());
}
static id (*gMSBDCCOrigSettings)(id, SEL, NSString *);
static id MSBDCCSettings(id self, SEL _cmd, NSString *mid) {
    id s = gMSBDCCOrigSettings(self, _cmd, mid);
    if (!s || ![mid isKindOfClass:[NSString class]] || ![gMSBDCCIdentifiers containsObject:mid]) return s;
    BOOL ram = [mid isEqualToString:kMSBDCCModuleID];
    NSString *grid = ram ? MSBDCCSmallWide() : MSBDCCSmall(), *container = MSBDCCContainerFor(mid);
    static NSMutableDictionary *made; static dispatch_once_t once;   // (ours, made once each; asked from more than one queue)
    dispatch_once(&once, ^{ made = [NSMutableDictionary dictionary]; });
    SEL gs = NSSelectorFromString(@"gridSizeClass"), cs = NSSelectorFromString(@"moduleContainerBundleIdentifier");
    @synchronized (made) {
        id mine = made[mid];
        if (mine && [((id (*)(id, SEL))objc_msgSend)(mine, gs) isEqual:grid] && (![mine respondsToSelector:cs] || [((id (*)(id, SEL))objc_msgSend)(mine, cs) isEqual:container])) return mine;
        SEL init = NSSelectorFromString(@"initWithGridSizeClass:containerBundleIdentifier:");
        Method im = class_getInstanceMethod(object_getClass(s), init);
        mine = nil;
        if (im && method_getTypeEncoding(im) && !strcmp(method_getTypeEncoding(im), "@32@0:8@16@24") && [s respondsToSelector:cs]) {
            mine = ((id (*)(id, SEL, id, id))objc_msgSend)([object_getClass(s) alloc], init, grid, container);
        } else if (ram && [s respondsToSelector:NSSelectorFromString(@"setGridSizeClass:")] && [s respondsToSelector:@selector(copyWithZone:)]) {
            mine = [s copy];   // (another shape: the 2 x 1 size as before 1.7.6, the container as Control Center made it)
            ((void (*)(id, SEL, id))objc_msgSend)(mine, NSSelectorFromString(@"setGridSizeClass:"), grid);
        }
        if (!mine) return s;
        made[mid] = mine;
        MSBDCCDebugLog([NSString stringWithFormat:@"18 settings for %@: %@, app %@", mid, grid, container]);
        return mine;
    }
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
    NSMutableArray *folders = [NSMutableArray array], *ids = [NSMutableArray array];
    MSBDCCActiveControls(@"", kMSBDCCModuleStepFile, folders, ids);
    if (!ids.count) { MSBDCCDebugLog(@"no control of ours to load"); return 0; }
    gMSBDCCFolders = [folders copy]; gMSBDCCIdentifiers = [ids copy];
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
    MSBDCCDebugLog([NSString stringWithFormat:@"registered %@: %d of 3 repository methods taken", [ids componentsJoinedByString:@", "], done]);
    if (done && [NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 18) {   // (the settings manager: ControlCenterUI, loaded with SpringBoard)
        if (objc_getClass("CCUIModuleSettingsManager")) MSBDCCModuleSettingsHook();
        else dispatch_async(dispatch_get_main_queue(), ^{ MSBDCCModuleSettingsHook(); });
    }
    return done;
}
// Removal (the prerm's root helper posts kMSBDCCRemovingNote, then edits the files too): SpringBoard on 15-17 takes our controls out of the user's
// list through Control Center's own settings (Apple's file, or CCSupport's where it is installed: it answers for the same methods), so the list
// it keeps is the one on disk -- with them left there, its next save would put them back. Nothing else in the list changes.
static inline void MSBDCCTakeOursOutOfUserList(void) {   // (inline: only SpringBoard's part calls it)
    if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 18) return;   // (18 keeps its layout another way: its tiles go when the module is gone)
    Class c = objc_getClass("CCSModuleSettingsProvider");
    Method sm = c ? class_getClassMethod(c, NSSelectorFromString(@"sharedProvider")) : NULL;
    Method gm = c ? class_getInstanceMethod(c, NSSelectorFromString(@"orderedUserEnabledModuleIdentifiers")) : NULL;
    Method tm = c ? class_getInstanceMethod(c, NSSelectorFromString(@"setAndSaveOrderedUserEnabledModuleIdentifiers:")) : NULL;
    if (!sm || !gm || !tm || strcmp(method_getTypeEncoding(sm) ?: "", "@16@0:8") || strcmp(method_getTypeEncoding(gm) ?: "", "@16@0:8")
        || strcmp(method_getTypeEncoding(tm) ?: "", "v24@0:8@16")) return;
    id provider = ((id (*)(id, SEL))objc_msgSend)((id)c, method_getName(sm));
    NSArray *now = provider ? ((id (*)(id, SEL))objc_msgSend)(provider, method_getName(gm)) : nil;
    if (![now isKindOfClass:[NSArray class]]) return;
    NSMutableArray *kept = [now mutableCopy];
    [kept removeObjectsInArray:@[kMSBDCCModuleID, kMSBDCCSSHModuleID]];
    if (kept.count == now.count) return;
    ((void (*)(id, SEL, id))objc_msgSend)(provider, method_getName(tm), kept);
    MSBDCCDebugLog([NSString stringWithFormat:@"removal: %lu control(s) of ours taken out of the user's list", (unsigned long)(now.count - kept.count)]);
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
