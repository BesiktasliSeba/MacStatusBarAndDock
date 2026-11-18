// CrashBlame.h -- whose crash was it? (MacStatusBar&Dock, 2026-09-26) Reads one SpringBoard crash report (.ips, iOS 15/16: a one-line JSON
// header, then a JSON body) and says whether it points at us. Used by the crash guard (CrashGuard.h) and the Aerial 5.0 probation (StatusBar.x),
// through the small helper library MacCrashBlame.dylib (loader/CrashBlameHelper.m): the loaders are plain C, this needs Foundation.
//
// Verdicts:
//  OURS   the TOP-MOST image on the crashing stack that is not Apple's (nor the hooking platform's) is one of ours (MacStatusBar.dylib,
//         MacDock.dylib, anything in .../MacStatusBarAndDock/), or one of our names (DM..., MSB..., MSBD... classes/functions, our pref domains)
//         is in the crash text (exception, "asi" messages, termination reasons) -- counted. The crashing stack: the last exception backtrace (where
//         an exception was thrown), else the faulting thread. Also OURS: a window engine we drive (Aerial, Zetsu, MilkyWay4) on top with our code
//         below it -- our own integration bugs are not excused;
//  APPLE  only Apple code (and the hooking platform: ElleKit, systemhook, ...) on those stacks, and no other tweak loaded -- counted: our actions
//         can crash Apple code without a single frame of ours on the stack (the FBSceneMonitor dealloc assert seen before);
//  UNPINNED (1.8.7.7, GitHub #14) the same Apple-only stacks, but another SpringBoard tweak is loaded (MSBDBlameOthersInReport: any image of the
//         report; else, in the helper only, the tweaks installed for SpringBoard, MSBDBlameOthersInstalled): it could be anyone's, so it counts only
//         as a WEAK crash (CrashGuard.h: it can second a crash of ours, it never starts an action on its own but in a long loop). Before, it counted
//         as ours, and #14's reporter (and #9/#10) had MacStatusBar&Dock switched off for popover aborts and a Do Not Disturb listener of other tweaks;
//  OTHER  another tweak's library is the top-most non-Apple image -- NOT counted (another tweak's crash must not switch us off), even when one of
//         our hooks is lower on the stack: -[UIApplication sendEvent:] and -[UIResponder pressesBegan:withEvent:] (the Dock, the volume keys)
//         are on nearly every touch and key stack. Such pass-through hooks are marked "transparent" in the crash map
//         (tools/crashmap-rules.txt): they give way to any other non-Apple code below them (a tweak that called through them), and count as ours
//         only when nothing but Apple code is around them;
//  UNKNOWN the report could not be read or understood -- counted (the old behaviour). So is a watchdog stackshot cut at an unnamed image (it could
//         be ours: msbdStackshotCut, it stays APPLE whoever else is loaded).
// Frames above "_sigtramp" belong to a signal handler (a crash reporter, our own test builds' death log), not to the crash: they are skipped.
// Our names are also looked for in the exception's reason our death record kept (common/CrashCause.h; 15/16 reports carry no reason of their own):
// a reason naming DM.../MSB... classes is ours.
// Cost: one read of at most 3 MB and one JSON parse, only for a crash report found after an early start; the verdict is cached by the caller.
#pragma once
#import <Foundation/Foundation.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <objc/runtime.h>   // (class_getImageName: the library of a class an exception names, 1.8.7.7)

enum { kMSBDBlameUnknown = 0, kMSBDBlameOurs = 1, kMSBDBlameApple = 2, kMSBDBlameOther = 3, kMSBDBlameUnpinned = 4 };
#define MSBD_BLAME_UNPINNED 1   // (1.8.7.7: this classifier knows UNPINNED -- the Mac tests run on the code before it too, tools/test-crashblame.sh)
#define MSBD_BLAME_MAX_BYTES (3 * 1024 * 1024)

// Our libraries by name (for a report that gives only names): the two loaders and the parts (Makefile PAYLOADS, MacCrashBlame).
static inline BOOL MSBDBlameIsOurName(NSString *name) {
    static NSSet *ours;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ours = [NSSet setWithArray:@[@"MacStatusBar", @"MacDock", @"MacCrashBlame", @"BrightnessKeyTweak", @"DockMagnification", @"DockMagnificationSettings",
            @"ForceQuitMenu", @"GraveEscapeTweak", @"MacAddToFolder", @"MacAppBridge", @"MacAppSizeMenu", @"MacCCGrabber", @"MacCrashNotice", @"MacEthernetFix", @"MacFolderMenu", @"MacHomeBar",
            @"MacIconLabels", @"MacLargeTitles", @"MacLockStatusBar", @"MacPageDots", @"MacPointer", @"MacSettings", @"MacSettingsBadge", @"MacStatusBarCore",
            @"MacStatusBarSettings", @"MixAudio", @"TabMuteTweak", @"VolumeGlobeTweak"]];
    });
    if ([name hasSuffix:@".dylib"]) name = [name substringToIndex:name.length - 6];
    return [ours containsObject:name];
}
// The hooking platform: on the stack of many crashes (it loads every tweak), never the cause by itself -- counts like Apple code.
static inline BOOL MSBDBlameIsPlatform(NSString *name) {
    static NSSet *platform;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        platform = [NSSet setWithArray:@[@"libellekit.dylib", @"ellekit", @"systemhook.dylib", @"TweakLoader.dylib", @"TweakInject.dylib", @"libinjector.dylib",
            @"CydiaSubstrate", @"libsubstrate.dylib", @"libsubstitute.dylib", @"libhooker.dylib", @"libblackjack.dylib", @"libroot.dylib", @"dyld"]];
    });
    return [platform containsObject:name];
}
typedef enum { kMSBDImgUnknown, kMSBDImgOurs, kMSBDImgApple, kMSBDImgOther } MSBDImgKind;
static inline MSBDImgKind MSBDBlameImageKind(NSString *path, NSString *name) {
    if (![path isKindOfClass:[NSString class]]) path = nil;
    if (![name isKindOfClass:[NSString class]]) name = path.lastPathComponent;
    if (!name.length && !path.length) return kMSBDImgUnknown;
    if ([path containsString:@"/MacStatusBarAndDock/"]) return kMSBDImgOurs;
    if (([name isEqualToString:@"MacStatusBar.dylib"] || [name isEqualToString:@"MacDock.dylib"]) &&   // (the loaders; Dopamine reports the tweak folder's real
        (!path || [path containsString:@"/DynamicLibraries/"] || [path containsString:@"/TweakInject/"])) return kMSBDImgOurs;   // path, .../usr/lib/TweakInject)
    if (!path.length) return MSBDBlameIsOurName(name) ? kMSBDImgOurs : kMSBDImgUnknown;   // (a name alone says too little about anyone else)
    if (MSBDBlameIsPlatform(name)) return kMSBDImgApple;
    if ([path containsString:@"/MobileSubstrate/"] || [path containsString:@"/TweakInject/"]) return kMSBDImgOther;   // (rootful tweak folders)
    for (NSString *apple in @[@"/System/", @"/usr/lib/", @"/usr/libexec/", @"/usr/sbin/", @"/usr/bin/", @"/Developer/", @"/private/preboot/Cryptexes/", @"/Library/Apple/", @"/AppleInternal/"])
        if ([path hasPrefix:apple]) return kMSBDImgApple;
    return kMSBDImgOther;   // (/var/jb, /private/preboot/<id>/jb-..., /var/containers, ...: jailbreak or third-party code)
}

// A window engine we drive (hook-free, through its own classes): on top with our code below it, the crash is ours.
static inline BOOL MSBDBlameIsEngine(NSString *name) {
    if ([name hasSuffix:@".dylib"]) name = [name substringToIndex:name.length - 6];
    return [@[@"Aerial", @"Zetsu", @"MilkyWay4", @"MilkyWay3SubModule"] containsObject:name ?: @""];
}
// Jailbreak infrastructure (1.8.7.7, #14): loaded with any set of tweaks, so never "another tweak" for an Apple-only crash -- the hooking platform
// above, Dopamine's own (its basebin: its dyld, systemhook, libjailbreak, libchoma, rootlesshooks), palera1n's (its binpack: universalhooks),
// ElleKit's Safe Mode (.../usr/lib/ellekit/: MobileSafety), the substrate loaders, and Choicy's loader (it only decides which tweaks load; on the
// stacks of every Choicy user).
static inline BOOL MSBDBlameIsInfra(NSString *path, NSString *name) {
    if (![path isKindOfClass:[NSString class]]) path = nil;
    if (![name isKindOfClass:[NSString class]]) name = path.lastPathComponent;
    name = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] ?: @"";
    if (MSBDBlameIsPlatform(name)) return YES;
    if ([path containsString:@"/basebin/"] || [path containsString:@"/usr/lib/ellekit/"] || [path hasPrefix:@"/cores/binpack/"]) return YES;
    static NSSet *infra;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        infra = [NSSet setWithArray:@[@"libjailbreak.dylib", @"libchoma.dylib", @"rootlesshooks.dylib", @"MobileSafety.dylib", @"SubstrateLoader.dylib",
            @"SubstrateInserter.dylib", @"SubstrateBootstrap.dylib", @"substitute-loader.dylib", @"substitute-inserter.dylib", @"libsubstitute.0.dylib",
            @"universalhooks.dylib"]];
    });
    if ([infra containsObject:name]) return YES;
    return [name rangeOfString:@"choicy" options:NSCaseInsensitiveSearch].location != NSNotFound;
}
// Another tweak, for "another tweak loaded" (1.8.7.7): a non-Apple image that is not ours, not infrastructure, not a window engine we drive (its
// integration is ours: MSBDBlameIsEngine) and not one of our own debug probes (MSBD...). Its library name (never a path: Report a Problem shows it).
static inline NSString *MSBDBlameOtherTweakName(NSString *path, NSString *name) {
    if (![path isKindOfClass:[NSString class]]) path = nil;
    if (![name isKindOfClass:[NSString class]]) name = path.lastPathComponent;
    if (MSBDBlameImageKind(path, name) != kMSBDImgOther) return nil;
    NSString *n = [(name.length ? name : path.lastPathComponent) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (!n.length || MSBDBlameIsInfra(path, n) || MSBDBlameIsEngine(n) || [n hasPrefix:@"MSBD"]) return nil;
    return n;
}
// A report's images: "usedImages" (15+: only the images some frame of some thread is in) or "binaryImages" (older: every image), and the names
// "imageExtraInfo" (legacy) may give by the same index.
static inline void MSBDBlameImageLists(NSDictionary *body, NSArray **images, NSArray **extra) {
    NSArray *im = [body isKindOfClass:[NSDictionary class]] ? body[@"usedImages"] : nil;
    if (![im isKindOfClass:[NSArray class]]) im = [body isKindOfClass:[NSDictionary class]] ? body[@"binaryImages"] : nil;
    if (![im isKindOfClass:[NSArray class]]) im = nil;
    NSArray *ex = [body isKindOfClass:[NSDictionary class]] ? body[@"imageExtraInfo"] : nil;
    NSDictionary *legacy = [body isKindOfClass:[NSDictionary class]] ? body[@"legacyInfo"] : nil;
    if (![ex isKindOfClass:[NSArray class]] && [legacy isKindOfClass:[NSDictionary class]]) ex = legacy[@"imageExtraInfo"];
    if (![ex isKindOfClass:[NSArray class]]) ex = nil;
    *images = im; *extra = ex;
}
static inline NSString *MSBDBlameImageAt(NSArray *images, NSArray *extra, NSUInteger i, NSString **pathOut) {
    NSString *path = nil, *name = nil;
    for (NSArray *list in @[images ?: @[], extra ?: @[]]) {
        if (i >= list.count || ![list[i] isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *d = list[i];
        if (!path && [d[@"path"] isKindOfClass:[NSString class]]) path = d[@"path"];
        if (!name && [d[@"name"] isKindOfClass:[NSString class]]) name = d[@"name"];
    }
    if (pathOut) *pathOut = path;
    return name ?: path.lastPathComponent;
}
// The other tweaks a report shows loaded in SpringBoard (1.8.7.7, #14): any image of it, on any thread (an image with a frame anywhere is loaded),
// and for a watchdog report the named images on any SpringBoard thread of its stackshot (msbdStackshotOthers, MSBDBlameFromStackshot). In order,
// each once, library names only.
static inline NSArray<NSString *> *MSBDBlameOthersInReport(NSDictionary *body) {
    NSMutableOrderedSet<NSString *> *o = [NSMutableOrderedSet orderedSet];
    if (![body isKindOfClass:[NSDictionary class]]) return @[];
    NSArray *images = nil, *extra = nil;
    MSBDBlameImageLists(body, &images, &extra);
    for (NSUInteger i = 0, n = MAX(images.count, extra.count); i < n && i < 4096; i++) {
        NSString *path = nil, *name = MSBDBlameImageAt(images, extra, i, &path);
        NSString *other = MSBDBlameOtherTweakName(path, name);
        if (other) [o addObject:other];
    }
    NSArray *ss = body[@"msbdStackshotOthers"];
    if ([ss isKindOfClass:[NSArray class]]) for (id n in ss) if ([n isKindOfClass:[NSString class]]) [o addObject:n];
    return o.array;
}
// The crash map's target for (image, uuid, offset): its name, or nil if the image is not in the map. `how` says which way it was found; `partTitle`
// gets the part's "<where>|<what>" words. (Used by CrashFeature.h, and here for the "transparent" functions.)
static inline NSString *MSBDFeatureMapTarget(NSString *map, NSString *image, NSString *uuid, unsigned long long offset, NSDictionary<NSString *, NSArray *> **targets, NSString **how, NSString **partTitle) {
    NSMutableDictionary *t = [NSMutableDictionary dictionary];
    NSString *partTarget = nil, *mapped = nil;
    *partTitle = nil;
    BOOL inBlock = NO, sawMap = NO;
    unsigned long long prevStart = 0; NSString *prevTarget = nil;
    for (NSString *line in [map componentsSeparatedByString:@"\n"]) {
        NSArray *f = [line componentsSeparatedByString:@" "];
        if (f.count < 2) continue;
        NSString *kind = f[0];
        if ([kind isEqualToString:@"T"]) t[f[1]] = [f subarrayWithRange:NSMakeRange(2, f.count - 2)];
        else if ([kind isEqualToString:@"P"] && f.count >= 3 && [f[1] isEqualToString:image]) partTarget = f[2];
        else if ([kind isEqualToString:@"N"] && f.count >= 3 && [f[1] isEqualToString:image]) *partTitle = [[f subarrayWithRange:NSMakeRange(2, f.count - 2)] componentsJoinedByString:@" "];
        else if ([kind isEqualToString:@"U"] && f.count >= 3) {
            if (inBlock) break;   // (the block of our slice has ended)
            if ([f[1] isEqualToString:image]) sawMap = YES;
            inBlock = [f[1] isEqualToString:image] && uuid.length && [[f[2] lowercaseString] isEqualToString:uuid];
            prevTarget = nil;
        } else if ([kind isEqualToString:@"R"] && inBlock && f.count >= 3) {
            unsigned long long start = strtoull([f[1] UTF8String], NULL, 16);
            if (prevTarget && offset >= prevStart && offset < start) { mapped = prevTarget; break; }
            prevStart = start; prevTarget = f[2];
        }
    }
    *targets = t;
    if (mapped && ![mapped isEqualToString:@"-"]) { *how = @"function map"; return mapped; }
    *how = inBlock ? @"outside the mapped functions: the part's fallback" : sawMap ? @"no map for this build (UUID): the part's fallback" : @"the part as a whole";
    return partTarget;
}
// A pure pass-through hook of ours (the map's "transparent" target): it only forwards the call, so it is never the crash's cause by itself.
static inline BOOL MSBDBlameTransparent(NSString *map, NSDictionary *img, NSString *name, NSDictionary *frame) {
    if (!map.length || ![img isKindOfClass:[NSDictionary class]] || ![frame[@"imageOffset"] isKindOfClass:[NSNumber class]]) return NO;
    if ([name hasSuffix:@".dylib"]) name = [name substringToIndex:name.length - 6];
    NSString *uuid = [img[@"uuid"] isKindOfClass:[NSString class]] ? [img[@"uuid"] lowercaseString] : @"";
    NSDictionary *t = nil; NSString *how = nil, *title = nil;
    NSString *target = MSBDFeatureMapTarget(map, name, uuid, [frame[@"imageOffset"] unsignedLongLongValue], &t, &how, &title);
    return [how isEqualToString:@"function map"] && [target isEqualToString:@"transparent"];
}
// The first frame that belongs to the crash itself: after a signal handler's "_sigtramp", if there is one.
static inline NSUInteger MSBDBlameFirstFrame(NSArray *frames) {
    NSUInteger first = 0;
    for (NSUInteger i = 0; i < frames.count && i < 64; i++)
        if ([frames[i] isKindOfClass:[NSDictionary class]] && [frames[i][@"symbol"] isEqual:@"_sigtramp"]) first = i + 1;
    return first < frames.count ? first : 0;
}
// A stack overflow (a recursion that never ends): the crashing stack fills the report's frame limit (511 frames) with the same few frames over and
// over, and its top-most frames are only where the stack happened to run out -- any function the recursion calls on its way round. The cause is the
// cycle, so in such a stack only the frames that repeat decide whose crash it is and which feature (CrashFeature.h). Seen on 3 Oct 2026 (iPad 2):
// the desktop's hit-test recursion (DMFocusGuideHitTest -> -[SBHomeScreenWindow hitTest:] -> ... -> DMFocusGuideHitTest) ran out inside DMUsableArea,
// a window-layout helper the desktop's -dm_area had just called, and step 1b switched Windowing off instead of the desktop.
// Returns the keys ("<image index>:<offset>", MSBDBlameFrameKey) of the frames that repeat, or nil when the stack is not an overflow.
#define MSBD_BLAME_OVERFLOW_FRAMES 256   // (a SpringBoard stack is well under 150 frames; the reporter cuts an overflow at 511)
#define MSBD_BLAME_CYCLE_REPEATS 4
static inline NSString *MSBDBlameFrameKey(id f) {
    if (![f isKindOfClass:[NSDictionary class]] || ![f[@"imageIndex"] isKindOfClass:[NSNumber class]] || ![f[@"imageOffset"] isKindOfClass:[NSNumber class]]) return nil;
    return [NSString stringWithFormat:@"%@:%@", f[@"imageIndex"], f[@"imageOffset"]];
}
static inline NSSet<NSString *> *MSBDBlameRecursion(NSArray *frames) {
    if (![frames isKindOfClass:[NSArray class]] || frames.count < MSBD_BLAME_OVERFLOW_FRAMES) return nil;
    NSCountedSet *seen = [NSCountedSet set];
    for (id f in frames) { NSString *k = MSBDBlameFrameKey(f); if (k) [seen addObject:k]; }
    NSMutableSet *cycle = [NSMutableSet set];
    for (NSString *k in seen) if ([seen countForObject:k] >= MSBD_BLAME_CYCLE_REPEATS) [cycle addObject:k];
    return cycle.count ? cycle : nil;
}

// Our names in free text (exception reason, "asi" messages): identifier-like words starting MSB/MSBD + capital, DM + capital + lowercase (DMStageLights,
// DMLog; not Apple's DMF/DMC/DMD... classes, which go on in capitals), the few MS... settings classes, and our domains.
static inline NSString *MSBDBlameOurWordIn(NSString *text) {
    if (![text isKindOfClass:[NSString class]] || !text.length) return nil;
    for (NSString *marker in @[@"com.besiktasliseba.", @"MacStatusBarAndDock"]) if ([text containsString:marker]) return marker;
    static NSSet *msClasses;
    static NSCharacterSet *notWord;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        msClasses = [NSSet setWithArray:@[@"MSKeyboardListController", @"MSPointerListController", @"MSPointerRowValue"]];
        NSMutableCharacterSet *w = [NSMutableCharacterSet alphanumericCharacterSet]; [w addCharactersInString:@"_"];
        notWord = [w invertedSet];
    });
    for (NSString *word in [text componentsSeparatedByCharactersInSet:notWord]) {
        NSUInteger n = word.length;
        if (n < 4) continue;
        unichar c0 = [word characterAtIndex:0], c1 = [word characterAtIndex:1], c2 = [word characterAtIndex:2], c3 = [word characterAtIndex:3];
        BOOL up2 = c2 >= 'A' && c2 <= 'Z', up3 = c3 >= 'A' && c3 <= 'Z', low3 = c3 >= 'a' && c3 <= 'z';
        if (c0 == 'M' && c1 == 'S' && c2 == 'B' && up3) return word;   // (MSBRootListController, MSBDGuard...)
        if (c0 == 'D' && c1 == 'M' && up2 && low3) return word;
        if ([msClasses containsObject:word]) return word;
    }
    return nil;
}
static inline void MSBDBlameCollectText(id obj, NSMutableArray<NSString *> *out, int depth) {
    if (depth > 6 || out.count > 200) return;
    if ([obj isKindOfClass:[NSString class]]) [out addObject:obj];
    else if ([obj isKindOfClass:[NSArray class]]) for (id o in obj) MSBDBlameCollectText(o, out, depth + 1);
    else if ([obj isKindOfClass:[NSDictionary class]]) for (id k in obj) { MSBDBlameCollectText(k, out, depth + 1); MSBDBlameCollectText(((NSDictionary *)obj)[k], out, depth + 1); }
}

// The classifier on the report body (the JSON object after the header line). `blamed` gets a short description (image or word, and where).
// `map`: the crash map's text (CrashMap.txt), for the transparent hooks; nil = none known. `reason`: the exception's reason from our death record
// (CrashCause.h; nil = none), read for our names like the report's own crash text.
static inline int MSBDBlameReportBodyMapCore(NSDictionary *body, NSString *map, NSString *reason, NSString **blamed) {
    if (blamed) *blamed = @"unreadable";
    if (![body isKindOfClass:[NSDictionary class]]) return kMSBDBlameUnknown;
    // The images: "usedImages" (iOS 15/16) or "binaryImages" (older), entries {"path","name"}; names may also sit in "imageExtraInfo" (legacy).
    NSArray *images = body[@"usedImages"];
    if (![images isKindOfClass:[NSArray class]]) images = body[@"binaryImages"];
    if (![images isKindOfClass:[NSArray class]]) images = nil;
    NSArray *extra = body[@"imageExtraInfo"];
    NSDictionary *legacy = body[@"legacyInfo"];
    if (![extra isKindOfClass:[NSArray class]] && [legacy isKindOfClass:[NSDictionary class]]) extra = legacy[@"imageExtraInfo"];
    if (![extra isKindOfClass:[NSArray class]]) extra = nil;
    NSUInteger imageCount = MAX(images.count, extra.count);
    NSString *(^imageName)(NSUInteger, NSString **) = ^NSString *(NSUInteger i, NSString **pathOut) {
        NSString *path = nil, *name = nil;
        for (NSArray *list in @[images ?: @[], extra ?: @[]]) {
            if (i >= list.count || ![list[i] isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *d = list[i];
            if (!path && [d[@"path"] isKindOfClass:[NSString class]]) path = d[@"path"];
            if (!name && [d[@"name"] isKindOfClass:[NSString class]]) name = d[@"name"];
        }
        if (pathOut) *pathOut = path;
        return name ?: path.lastPathComponent;
    };
    // The stacks that matter: the faulting thread ("faultingThread" index, or the thread marked "triggered") and the last exception backtrace.
    NSArray *threads = body[@"threads"];
    if (![threads isKindOfClass:[NSArray class]]) threads = nil;
    NSArray *faultFrames = nil;
    id ft = body[@"faultingThread"];
    if ([ft isKindOfClass:[NSNumber class]] && [ft unsignedIntegerValue] < threads.count && [threads[[ft unsignedIntegerValue]] isKindOfClass:[NSDictionary class]])
        faultFrames = threads[[ft unsignedIntegerValue]][@"frames"];
    if (![faultFrames isKindOfClass:[NSArray class]]) {
        faultFrames = nil;
        for (NSDictionary *t in threads)
            if ([t isKindOfClass:[NSDictionary class]] && [t[@"triggered"] boolValue] && [t[@"frames"] isKindOfClass:[NSArray class]]) { faultFrames = t[@"frames"]; break; }
    }
    NSArray *excFrames = body[@"lastExceptionBacktrace"];
    if (![excFrames isKindOfClass:[NSArray class]]) excFrames = nil;
    if (!faultFrames && !excFrames) { if (blamed) *blamed = @"no crash stacks in the report"; return kMSBDBlameUnknown; }
    NSString *ourImage = nil, *otherImage = nil;
    int known = 0;
    // The top-most frame that is not Apple's decides, on the exception backtrace first (where it was thrown), else on the faulting thread. In a stack
    // overflow only the frames of the cycle count (MSBDBlameRecursion); a cycle of nothing but Apple code leaves it to the top-most frame, as before.
    for (int scan = 0; scan < 4 && !ourImage && !otherImage; scan++) {
        int pass = scan / 2;
        NSArray *frames = pass == 0 ? excFrames : faultFrames;
        NSSet<NSString *> *cycle = scan % 2 == 0 ? MSBDBlameRecursion(frames) : nil;
        if (scan % 2 == 0 && !cycle) continue;   // (no overflow: the plain scan below)
        NSString *where = pass == 0 ? @"exception backtrace" : @"faulting thread";
        if (cycle) where = [where stringByAppendingString:@", recursion"];
        NSString *engine = nil;   // (a window engine on top: ours only if our own code called it)
        NSString *passThrough = nil;   // (one of our pass-through hooks: ours only if no other non-Apple code is below it)
        for (NSUInteger k = MSBDBlameFirstFrame(frames); k < frames.count; k++) {
            NSDictionary *f = frames[k];
            if (![f isKindOfClass:[NSDictionary class]] || ![f[@"imageIndex"] isKindOfClass:[NSNumber class]]) continue;
            if (cycle && ![cycle containsObject:MSBDBlameFrameKey(f) ?: @""]) continue;   // (where the stack ran out: not the cause)
            NSUInteger i = [f[@"imageIndex"] unsignedIntegerValue];
            if (i >= imageCount) continue;
            NSString *path = nil, *name = imageName(i, &path);
            MSBDImgKind kind = MSBDBlameImageKind(path, name);
            if (kind != kMSBDImgUnknown) known++;
            if (kind == kMSBDImgOurs) {
                if (MSBDBlameTransparent(map, i < images.count ? images[i] : nil, name ?: path.lastPathComponent, f)) {   // (a pass-through hook)
                    if (!passThrough) passThrough = [NSString stringWithFormat:@"%@ (%@, pass-through hook)", name ?: path, where];
                    continue;
                }
                ourImage = engine ? [NSString stringWithFormat:@"%@ (%@, calling %@)", name ?: path, where, engine.lastPathComponent] : [NSString stringWithFormat:@"%@ (%@)", name ?: path, where];
                break;
            }
            if (kind != kMSBDImgOther || engine) continue;
            if (MSBDBlameIsEngine(name ?: path.lastPathComponent)) { engine = path ?: name; continue; }   // (look below it for our code)
            otherImage = [NSString stringWithFormat:@"%@ (%@)", path ?: name, where];   // (the path: Settings names its package)
            break;
        }
        if (!ourImage && !otherImage) {
            if (engine) otherImage = [NSString stringWithFormat:@"%@ (%@)", engine, where];   // (only our pass-through hooks, or nothing of ours, below it)
            else if (passThrough && !cycle) ourImage = passThrough;   // (nothing but Apple code besides it: as before, ours; in a cycle: the plain scan decides)
        }
    }
    if (ourImage) { if (blamed) *blamed = ourImage; return kMSBDBlameOurs; }
    // Our names in the crash text: the exception, the "asi" messages (the reason of an uncaught exception, assertion texts) and termination reasons.
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    for (NSString *key in @[@"exception", @"asi", @"termination", @"exceptionReason"]) MSBDBlameCollectText(body[key], texts, 0);
    if ([reason isKindOfClass:[NSString class]] && reason.length) [texts addObject:reason];   // (1.8.7.7: the reason our death record kept)
    for (NSString *text in texts) {
        NSString *word = MSBDBlameOurWordIn(text);
        if (word) { if (blamed) *blamed = [NSString stringWithFormat:@"%@ (crash text)", word]; return kMSBDBlameOurs; }
    }
    if (otherImage) { if (blamed) *blamed = otherImage; return kMSBDBlameOther; }
    if (!known) { if (blamed) *blamed = @"no named images on the crash stacks"; return kMSBDBlameUnknown; }
    if (blamed) *blamed = @"Apple code only";
    return kMSBDBlameApple;
}

static inline BOOL MSBDBlameIsWatchdog(NSDictionary *body);
// A watchdog report (SpringBoard stuck, killed by the system: MSBDBlameIsWatchdog) is judged on its stuck main thread like a crash on its faulting
// thread; what was blamed then starts with "watchdog:" (the pages and Report a Problem say "stuck" instead of "crashed", CrashExplain.h).
// 1.8.7.7 (#14): an APPLE verdict with another tweak loaded is UNPINNED -- the report's own images first (MSBDBlameOthersInReport); only when it
// shows none, `installed` (nil: not asked) -- the helper's look at the tweaks installed for SpringBoard (MSBDBlameOthersInstalled). Not a watchdog
// stackshot cut at an unnamed image: that one could be ours (msbdStackshotCut), it stays APPLE. `others` (NULL: not wanted) gets the tweaks found.
static inline int MSBDBlameReportBodyFull(NSDictionary *body, NSString *map, NSString *reason, NSArray<NSString *> *(^installed)(void), NSString **blamed, NSArray<NSString *> **others) {
    NSString *what = nil;
    int v = MSBDBlameReportBodyMapCore(body, map, reason, &what);
    NSArray<NSString *> *found = @[];
    if (v == kMSBDBlameApple && ![body[@"msbdStackshotCut"] boolValue]) {
        found = MSBDBlameOthersInReport(body);
        if (!found.count && installed) found = installed() ?: @[];
        if (found.count) {
            v = kMSBDBlameUnpinned;
            what = [NSString stringWithFormat:@"Apple code only; %lu other tweak%@ loaded", (unsigned long)found.count, found.count == 1 ? @"" : @"s"];
        }
    }
    if (MSBDBlameIsWatchdog(body)) what = [@"watchdog:" stringByAppendingString:[what stringByReplacingOccurrencesOfString:@"faulting thread" withString:@"stuck main thread"] ?: @""];
    if (blamed) *blamed = what;
    if (others) *others = found;
    return v;
}
static inline int MSBDBlameReportBodyMap(NSDictionary *body, NSString *map, NSString **blamed) { return MSBDBlameReportBodyFull(body, map, nil, nil, blamed, NULL); }
static inline int MSBDBlameReportBody(NSDictionary *body, NSString **blamed) { return MSBDBlameReportBodyMap(body, nil, blamed); }

// The length of the first complete JSON object at `p` (0 if none): lets a report with something after its body still be read.
static inline NSUInteger MSBDBlameObjectLength(const char *p, NSUInteger n) {
    NSUInteger i = 0;
    while (i < n && p[i] != '{') i++;
    int depth = 0; BOOL inString = NO;
    for (; i < n; i++) {
        char c = p[i];
        if (inString) { if (c == '\\') i++; else if (c == '"') inString = NO; continue; }
        if (c == '"') inString = YES;
        else if (c == '{' || c == '[') depth++;
        else if ((c == '}' || c == ']') && --depth == 0) return i + 1;
    }
    return 0;
}
static inline NSDictionary *MSBDBlameBodyFromDataRaw(NSData *data);
// ---- Watchdog reports (2026-09-28) --------------------------------------------------------------------------------------------------------------
// When SpringBoard stops answering (its main thread stuck ~60 s), the system kills it and writes a SpringBoard-<date>.ips with termination namespace
// WATCHDOG and NO "threads": the stacks are a "stackshot" -- processByPid.<pid>.threadById.<id>.userFrames = [[image index, offset], ...] and
// binaryImages = [[uuid, load address, kind], ...], kind S = the shared cache (Apple), K = kernel, P/A = other images, with NO names. Seen on the M1
// (28 Sep, 04:45): another tweak's network call at SpringBoard's start never returned, the watchdog killed it twice and the guard, reading "no crash
// stacks", switched us off. Such a report is turned into the usual shape: SpringBoard's main thread as the triggered thread, its images named by UUID
// from the tweak files (and the images loaded in this process). A P/A image that cannot be named ends the stack there (it could be our own code, so
// nothing below it may clear us: the stuck thread then counts as Apple's, i.e. against us, as before).
static NSDictionary<NSString *, NSString *> *gMSBDBlameUUIDOverride;   // (the Mac test: uuid -> path)
static inline void MSBDBlameAddUUIDsOfFile(NSString *path, NSMutableDictionary *out) {
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
    NSData *head = [fh readDataOfLength:65536];
    [fh closeFile];
    if (head.length < 32) return;
    const uint8_t *b = (const uint8_t *)head.bytes; NSUInteger n = head.length;
    uint32_t magic = *(const uint32_t *)b;
    NSMutableArray<NSNumber *> *slices = [NSMutableArray array];
    if (magic == 0xbebafecaU) {   // (FAT_CIGAM: a fat file, big-endian header)
        uint32_t count = CFSwapInt32BigToHost(*(const uint32_t *)(b + 4));
        for (uint32_t i = 0; i < count && i < 8 && 8 + (i + 1) * 20 <= n; i++) [slices addObject:@(CFSwapInt32BigToHost(*(const uint32_t *)(b + 8 + i * 20 + 8)))];
    } else [slices addObject:@0];
    for (NSNumber *off in slices) {
        NSUInteger o = off.unsignedIntegerValue;
        NSData *d = head;
        if (o + 32 > n) {   // (a slice beyond the first 64 KB: read its header there)
            NSFileHandle *f2 = [NSFileHandle fileHandleForReadingAtPath:path];
            [f2 seekToFileOffset:o]; d = [f2 readDataOfLength:65536]; [f2 closeFile]; o = 0;
            if (d.length < 32) continue;
        }
        const uint8_t *m = (const uint8_t *)d.bytes + o; NSUInteger left = d.length - o;
        if (*(const uint32_t *)m != 0xfeedfacfU) continue;   // (MH_MAGIC_64)
        uint32_t ncmds = *(const uint32_t *)(m + 16), size = *(const uint32_t *)(m + 20);
        NSUInteger p = 32, end = MIN(left, 32 + (NSUInteger)size);
        for (uint32_t c = 0; c < ncmds && p + 8 <= end; c++) {
            uint32_t cmd = *(const uint32_t *)(m + p), len = *(const uint32_t *)(m + p + 4);
            if (cmd == 0x1b && p + 24 <= end) {   // (LC_UUID)
                out[[[[NSUUID alloc] initWithUUIDBytes:m + p + 8].UUIDString lowercaseString]] = path;
                break;
            }
            if (len < 8) break;
            p += len;
        }
    }
}
static inline NSDictionary<NSString *, NSString *> *MSBDBlameUUIDPaths(void) {
    if (gMSBDBlameUUIDOverride) return gMSBDBlameUUIDOverride;
#ifdef MSBD_BLAME_UUID_MAP_FILE   // (the Mac tests' helper only: "<uuid> <path>" lines, 1.8.7.7)
    {
        NSMutableDictionary *m = [NSMutableDictionary dictionary];
        for (NSString *line in [[NSString stringWithContentsOfFile:@MSBD_BLAME_UUID_MAP_FILE encoding:NSUTF8StringEncoding error:nil] componentsSeparatedByString:@"\n"]) {
            NSRange sp = [line rangeOfString:@" "];
            if (sp.location != NSNotFound) m[[[line substringToIndex:sp.location] lowercaseString]] = [line substringFromIndex:sp.location + 1];
        }
        return m;
    }
#endif
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSString *dir in @[@"/var/jb/usr/lib/TweakInject", @"/var/jb/Library/MobileSubstrate/DynamicLibraries", @"/var/jb/usr/lib/MacStatusBarAndDock"]) {
        NSString *real = [dir stringByResolvingSymlinksInPath];
        if ([dir hasSuffix:@"DynamicLibraries"] && [real isEqualToString:[@"/var/jb/usr/lib/TweakInject" stringByResolvingSymlinksInPath]]) continue;   // (the same folder on rootless)
        for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil])
            if ([f hasSuffix:@".dylib"]) MSBDBlameAddUUIDsOfFile([dir stringByAppendingPathComponent:f], out);
    }
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {   // (loaded now: SpringBoard itself, frameworks outside the shared cache, ...)
        const struct mach_header_64 *h = (const struct mach_header_64 *)_dyld_get_image_header(i);
        const char *name = _dyld_get_image_name(i);
        if (!h || !name || h->magic != 0xfeedfacfU) continue;
        const uint8_t *p = (const uint8_t *)(h + 1);
        for (uint32_t c = 0; c < h->ncmds; c++) {
            const struct load_command *lc = (const struct load_command *)p;
            if (lc->cmd == 0x1b) {
                NSString *u = [[[NSUUID alloc] initWithUUIDBytes:p + 8].UUIDString lowercaseString];
                if (!out[u]) out[u] = [NSString stringWithUTF8String:name];
                break;
            }
            p += lc->cmdsize;
        }
    }
    return out;
}
static inline NSDictionary *MSBDBlameFromStackshot(NSDictionary *body) {
    NSDictionary *ss = body[@"stackshot"];
    if (![ss isKindOfClass:[NSDictionary class]] || ![ss[@"processByPid"] isKindOfClass:[NSDictionary class]] || ![ss[@"binaryImages"] isKindOfClass:[NSArray class]]) return body;
    NSDictionary *proc = nil;
    NSString *want = [body[@"procName"] isKindOfClass:[NSString class]] ? body[@"procName"] : @"SpringBoard";
    for (NSDictionary *p in [ss[@"processByPid"] allValues]) if ([p isKindOfClass:[NSDictionary class]] && [p[@"procname"] isEqual:want]) { proc = p; break; }
    NSDictionary *threads = [proc[@"threadById"] isKindOfClass:[NSDictionary class]] ? proc[@"threadById"] : nil;
    NSDictionary *main = nil;
    for (NSDictionary *t in threads.allValues) if ([t isKindOfClass:[NSDictionary class]] && [t[@"dispatch_queue_label"] isEqual:@"com.apple.main-thread"]) { main = t; break; }
    if (!main) for (NSDictionary *t in threads.allValues)   // (no queue label: the thread with the lowest id)
        if ([t isKindOfClass:[NSDictionary class]] && [t[@"id"] isKindOfClass:[NSNumber class]] && (!main || [t[@"id"] compare:main[@"id"]] == NSOrderedAscending)) main = t;
    NSArray *uf = [main[@"userFrames"] isKindOfClass:[NSArray class]] ? main[@"userFrames"] : nil;
    if (!uf.count) return body;
    NSArray *bin = ss[@"binaryImages"];
    NSDictionary<NSString *, NSString *> *byUUID = MSBDBlameUUIDPaths();
    NSMutableArray *images = [NSMutableArray array], *frames = [NSMutableArray array];
    NSMutableDictionary<NSNumber *, NSNumber *> *indexOf = [NSMutableDictionary dictionary];
    BOOL cut = NO;
    NSString *(^pathOf)(NSUInteger, NSString **) = ^NSString *(NSUInteger bi, NSString **uuidOut) {
        NSArray *img = bi < bin.count && [bin[bi] isKindOfClass:[NSArray class]] ? bin[bi] : nil;
        NSString *uuid = img.count >= 3 && [img[0] isKindOfClass:[NSString class]] ? [img[0] lowercaseString] : @"";
        NSString *kind = img.count >= 3 && [img[2] isKindOfClass:[NSString class]] ? img[2] : @"";
        if (uuidOut) *uuidOut = uuid;
        return [kind isEqualToString:@"S"] ? @"/System/Library/Caches/com.apple.dyld/dyld_shared_cache" : [kind isEqualToString:@"K"] ? @"/System/Library/Kernels/kernel" : byUUID[uuid];
    };
    for (NSArray *f in uf) {
        if (![f isKindOfClass:[NSArray class]] || f.count < 2 || ![f[0] isKindOfClass:[NSNumber class]] || ![f[1] isKindOfClass:[NSNumber class]]) continue;
        NSUInteger bi = [f[0] unsignedIntegerValue];
        NSString *uuid = nil, *path = pathOf(bi, &uuid);
        if (!path) { cut = YES; break; }   // (unnamed code: nothing below it may clear us -- nor may anyone else loaded, 1.8.7.7: msbdStackshotCut)
        NSNumber *key = @(bi);
        if (!indexOf[key]) { indexOf[key] = @(images.count); [images addObject:@{@"path": path, @"name": path.lastPathComponent, @"uuid": uuid}]; }
        [frames addObject:@{@"imageIndex": indexOf[key], @"imageOffset": f[1]}];
    }
    // (1.8.7.7, #14: the other tweaks loaded, for an APPLE verdict -- the named images on any SpringBoard thread of the stackshot)
    NSMutableOrderedSet<NSString *> *others = [NSMutableOrderedSet orderedSet];
    for (NSDictionary *t in threads.allValues) {
        NSArray *tf = [t isKindOfClass:[NSDictionary class]] && [t[@"userFrames"] isKindOfClass:[NSArray class]] ? t[@"userFrames"] : nil;
        for (NSArray *f in tf) {
            if (![f isKindOfClass:[NSArray class]] || f.count < 2 || ![f[0] isKindOfClass:[NSNumber class]]) continue;
            NSString *path = pathOf([f[0] unsignedIntegerValue], NULL), *other = path ? MSBDBlameOtherTweakName(path, path.lastPathComponent) : nil;
            if (other) [others addObject:other];
        }
    }
    NSMutableDictionary *out = [body mutableCopy];
    out[@"usedImages"] = images;
    out[@"threads"] = @[@{@"triggered": @YES, @"frames": frames, @"queue": @"com.apple.main-thread"}];
    out[@"msbdStackshot"] = @YES;
    if (cut) out[@"msbdStackshotCut"] = @YES;
    if (others.count) out[@"msbdStackshotOthers"] = others.array;
    return out;
}
static inline BOOL MSBDBlameIsWatchdog(NSDictionary *body) {
    NSDictionary *t = [body isKindOfClass:[NSDictionary class]] && [body[@"termination"] isKindOfClass:[NSDictionary class]] ? body[@"termination"] : nil;
    return [t[@"namespace"] isEqual:@"WATCHDOG"] || [body[@"msbdStackshot"] boolValue];
}

// A report's body from its raw bytes: header line + body (or a single JSON object); nil if unreadable. A watchdog report's stackshot is turned into
// the usual shape (MSBDBlameFromStackshot).
static inline NSDictionary *MSBDBlameBodyFromData(NSData *data) {
    NSDictionary *body = MSBDBlameBodyFromDataRaw(data);
    if (body && !body[@"threads"] && body[@"stackshot"]) body = MSBDBlameFromStackshot(body);
    return body;
}
static inline NSDictionary *MSBDBlameBodyFromDataRaw(NSData *data) {
    if (!data.length || data.length > MSBD_BLAME_MAX_BYTES) return nil;
    const char *bytes = (const char *)data.bytes;
    const char *nl = memchr(bytes, '\n', data.length);
    id body = nil;
    if (nl) {
        NSUInteger start = (NSUInteger)(nl - bytes) + 1;
        if (start < data.length) body = [NSJSONSerialization JSONObjectWithData:[data subdataWithRange:NSMakeRange(start, data.length - start)] options:0 error:nil];
        if (!body && start < data.length) {   // (trailing text after the body)
            NSUInteger len = MSBDBlameObjectLength(bytes + start, data.length - start);
            if (len) body = [NSJSONSerialization JSONObjectWithData:[data subdataWithRange:NSMakeRange(start, len)] options:0 error:nil];
        }
    }
    if (![body isKindOfClass:[NSDictionary class]] || !body[@"threads"]) {
        id whole = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([whole isKindOfClass:[NSDictionary class]]) body = whole;
    }
    return [body isKindOfClass:[NSDictionary class]] ? body : nil;
}
static inline int MSBDBlameReportData(NSData *data, NSString **blamed) {
    if (blamed) *blamed = @"unreadable";
    return MSBDBlameReportBody(MSBDBlameBodyFromData(data), blamed);
}
static inline int MSBDBlameReportFile(NSString *path, NSString **blamed) {
    if (blamed) *blamed = @"unreadable";
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if (!attrs || [attrs fileSize] == 0 || [attrs fileSize] > MSBD_BLAME_MAX_BYTES) { if (blamed && attrs) *blamed = @"too large or empty"; return kMSBDBlameUnknown; }
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingUncached error:nil];
    return MSBDBlameReportData(data, blamed);
}

// The crash guard's summary (only after it acted, CrashGuard.h): the top frames of OUR images on the crashing stack (the faulting thread, else the
// last exception backtrace), at most `max`, as "<image> <symbol> + <offset>" or "<image> + 0x<offset in image>". Nothing of anyone else: no other
// image, no path, no thread names, no text from the report.
static inline NSArray<NSString *> *MSBDBlameOurFrames(NSDictionary *body, NSUInteger max) {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    if (![body isKindOfClass:[NSDictionary class]]) return out;
    NSArray *images = [body[@"usedImages"] isKindOfClass:[NSArray class]] ? body[@"usedImages"] : ([body[@"binaryImages"] isKindOfClass:[NSArray class]] ? body[@"binaryImages"] : nil);
    NSArray *threads = [body[@"threads"] isKindOfClass:[NSArray class]] ? body[@"threads"] : nil;
    NSArray *fault = nil;
    id ft = body[@"faultingThread"];
    if ([ft isKindOfClass:[NSNumber class]] && [ft unsignedIntegerValue] < threads.count && [threads[[ft unsignedIntegerValue]] isKindOfClass:[NSDictionary class]]) fault = threads[[ft unsignedIntegerValue]][@"frames"];
    if (![fault isKindOfClass:[NSArray class]]) {
        fault = nil;
        for (NSDictionary *t in threads) if ([t isKindOfClass:[NSDictionary class]] && [t[@"triggered"] boolValue] && [t[@"frames"] isKindOfClass:[NSArray class]]) { fault = t[@"frames"]; break; }
    }
    NSArray *exc = [body[@"lastExceptionBacktrace"] isKindOfClass:[NSArray class]] ? body[@"lastExceptionBacktrace"] : nil;
    for (NSArray *frames in @[fault ?: @[], exc ?: @[]]) {
        // (a stack overflow: the frames of ours in the cycle, once each -- not where the stack ran out, MSBDBlameRecursion; a cycle with none of ours:
        //  as before)
        NSSet<NSString *> *cycle = MSBDBlameRecursion(frames);
        if (cycle) {
            BOOL oursInCycle = NO;
            for (id f in frames) {
                if (![cycle containsObject:MSBDBlameFrameKey(f) ?: @""]) continue;
                NSUInteger i = [f[@"imageIndex"] unsignedIntegerValue];
                NSDictionary *img = i < images.count && [images[i] isKindOfClass:[NSDictionary class]] ? images[i] : nil;
                NSString *p = [img[@"path"] isKindOfClass:[NSString class]] ? img[@"path"] : nil;
                if (MSBDBlameImageKind(p, [img[@"name"] isKindOfClass:[NSString class]] ? img[@"name"] : p.lastPathComponent) == kMSBDImgOurs) { oursInCycle = YES; break; }
            }
            if (!oursInCycle) cycle = nil;
        }
        NSMutableSet<NSString *> *listed = [NSMutableSet set];
        for (NSUInteger k = MSBDBlameFirstFrame(frames); k < frames.count; k++) {
            NSDictionary *f = frames[k];
            if (out.count >= max) break;
            if (![f isKindOfClass:[NSDictionary class]] || ![f[@"imageIndex"] isKindOfClass:[NSNumber class]]) continue;
            if (cycle) {
                NSString *key = MSBDBlameFrameKey(f) ?: @"";
                if (![cycle containsObject:key] || [listed containsObject:key]) continue;
                [listed addObject:key];
            }
            NSUInteger i = [f[@"imageIndex"] unsignedIntegerValue];
            NSDictionary *img = i < images.count && [images[i] isKindOfClass:[NSDictionary class]] ? images[i] : nil;
            NSString *path = [img[@"path"] isKindOfClass:[NSString class]] ? img[@"path"] : nil, *name = [img[@"name"] isKindOfClass:[NSString class]] ? img[@"name"] : path.lastPathComponent;
            if (!name.length || MSBDBlameImageKind(path, name) != kMSBDImgOurs) continue;
            NSString *symbol = [f[@"symbol"] isKindOfClass:[NSString class]] ? f[@"symbol"] : nil;
            NSString *line = symbol.length && ![symbol hasPrefix:@"("] && [f[@"symbolLocation"] isKindOfClass:[NSNumber class]]
                ? [NSString stringWithFormat:@"%@ %@ + %@", name, symbol, f[@"symbolLocation"]]
                : [NSString stringWithFormat:@"%@ + 0x%llx", name, [f[@"imageOffset"] isKindOfClass:[NSNumber class]] ? [f[@"imageOffset"] unsignedLongLongValue] : 0ULL];
            [out addObject:line.length > 150 ? [line substringToIndex:150] : line];
        }
        if (out.count) break;   // (the faulting thread's own frames when it has ours; else the exception's)
    }
    return out;
}

// ---- Another tweak installed for SpringBoard (1.8.7.7, GitHub #14) -------------------------------------------------------------------------------
// Only when an Apple-only report shows no other tweak's image (usedImages lists only the images some frame is in): the tweaks whose filter loads them
// into SpringBoard (MSBDBlameFilterLoadsInSpringBoard), whose .dylib is there (iCleaner Pro's switch-off renames it) and that Choicy does not keep
// out of SpringBoard (its global deny list, SpringBoard's own configuration: as common/OtherTweaks.h MSBDTweakPresent reads them). Not ours, the
// window engines, the infrastructure. A filter it cannot judge (one only a class could match) does not count: the crash then stays as careful as before.
// The helper only (MacCrashBlame, after an early start): about a hundred small plist reads.
#ifndef MSBD_CHOICY_PREFS   // (overridable for the Mac test)
#define MSBD_CHOICY_PREFS "/var/jb/var/mobile/Library/Preferences/com.opa334.choicyprefs.plist"
#endif
static NSArray<NSString *> *gMSBDBlameTweakDirsOverride;   // (the Mac test: the tweak folders)
// Does a tweak's filter load it into SpringBoard? As ElleKit's loader decides it (libinjector.dylib, the TweakLoader of the rootless jailbreaks we
// support; its code read from the iPads, ElleKit 1.1.3 and 1.2, 17 Nov 2026), not by Substrate's every-key rule (1.8.7.7~g01's device rows: that
// rule left out the 17.5's Snowboard.dylib, Bundles UIKit + Executables CarPlay..., and the iPad 2's RocketBootstrap.dylib, Bundles springboard +
// Executables MobileGestaltHelper; ElleKit loads both into SpringBoard, as it loads our own MacStatusBar.dylib, Bundles UIKit + Executables dasd...):
//  1. CoreFoundationVersion, a gate: one number -- loaded only from that version on; two -- never (that loader reads the first number twice, as
//     the lowest and as the highest version, and every version fails one of the two); none, or not a number first: no gate;
//  2. then ANY key that matches loads it -- one of its Bundles is loaded (as written or lowercased), one of its Classes exists, or one of its
//     Executables is the process (exactly). There is no "Mode": every filter is "Any". No key that matches: not loaded.
// Here, for SpringBoard: Bundles com.apple.springboard -- or SpringBoard's own frameworks --, FrontBoard's, com.apple.UIKit, com.apple.Foundation,
// com.apple.CoreFoundation; Executables SpringBoard. Classes are not judged: the helper runs in SpringBoard, but later than ElleKit read the
// filters (more tweaks and frameworks are loaded by then), so a class found here does not prove that the tweak was loaded. A filter only a class
// could match stays out (the crash then stays strong, as in 1.8.7.6), never in on a guess.
static inline BOOL MSBDBlameFilterLoadsInSpringBoard(NSDictionary *plist) {
    NSDictionary *filter = [plist isKindOfClass:[NSDictionary class]] ? plist[@"Filter"] : nil;
    if (![filter isKindOfClass:[NSDictionary class]]) return NO;
    NSArray *cf = [filter[@"CoreFoundationVersion"] isKindOfClass:[NSArray class]] ? filter[@"CoreFoundationVersion"] : nil;
    if (cf.count && CFGetTypeID((__bridge CFTypeRef)cf[0]) == CFNumberGetTypeID() && (cf.count == 2 || (cf.count == 1 && [cf[0] doubleValue] > kCFCoreFoundationVersionNumber))) return NO;
    for (id b in [filter[@"Bundles"] isKindOfClass:[NSArray class]] ? filter[@"Bundles"] : nil) {
        if (![b isKindOfClass:[NSString class]]) continue;
        NSString *l = [b lowercaseString];
        if ([@[@"com.apple.springboard", @"com.apple.uikit", @"com.apple.foundation", @"com.apple.corefoundation"] containsObject:l] || [l hasPrefix:@"com.apple.springboard"] || [l hasPrefix:@"com.apple.frontboard"]) return YES;
    }
    for (id e in [filter[@"Executables"] isKindOfClass:[NSArray class]] ? filter[@"Executables"] : nil) if ([e isKindOfClass:[NSString class]] && [e isEqualToString:@"SpringBoard"]) return YES;
    return NO;   // (no key that matches; or one only a class could match: not judged, above)
}
static inline BOOL MSBDBlameChoicyKeepsOut(NSDictionary *c, NSString *name) {
    if (![c isKindOfClass:[NSDictionary class]] || !name.length) return NO;
    if ([c[@"globalDeniedTweaks"] isKindOfClass:[NSArray class]] && [c[@"globalDeniedTweaks"] containsObject:name]) return YES;
    NSDictionary *sb = [c[@"appSettings"] isKindOfClass:[NSDictionary class]] ? c[@"appSettings"][@"com.apple.springboard"] : nil;
    if (![sb isKindOfClass:[NSDictionary class]] || ![sb[@"customTweakConfigurationEnabled"] boolValue]) return NO;
    if ([sb[@"tweakInjectionDisabled"] boolValue]) return YES;
    NSInteger mode = [sb[@"allowDenyMode"] isKindOfClass:[NSNumber class]] ? [sb[@"allowDenyMode"] integerValue] : 1;
    NSArray *list = mode == 2 ? sb[@"deniedTweaks"] : sb[@"allowedTweaks"];
    BOOL listed = [list isKindOfClass:[NSArray class]] && [list containsObject:name];
    return (mode == 2 && listed) || (mode == 1 && !listed);
}
static inline NSArray<NSString *> *MSBDBlameOthersInstalled(void) {
#ifdef MSBD_BLAME_TWEAK_DIR   // (the Mac tests' helper only, 1.8.7.7)
    if (!gMSBDBlameTweakDirsOverride) gMSBDBlameTweakDirsOverride = @[@MSBD_BLAME_TWEAK_DIR];
#endif
    NSArray *dirs = gMSBDBlameTweakDirsOverride ?: @[@"/var/jb/usr/lib/TweakInject", @"/var/jb/Library/MobileSubstrate/DynamicLibraries"];
    NSDictionary *choicy = [NSDictionary dictionaryWithContentsOfFile:@MSBD_CHOICY_PREFS];
    NSMutableSet<NSString *> *seenDirs = [NSMutableSet set];
    NSMutableOrderedSet<NSString *> *o = [NSMutableOrderedSet orderedSet];
    for (NSString *dir in dirs) {
        NSString *real = [dir stringByResolvingSymlinksInPath];
        if ([seenDirs containsObject:real]) continue;   // (the same folder on rootless)
        [seenDirs addObject:real];
        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSString *f in [[fm contentsOfDirectoryAtPath:dir error:nil] sortedArrayUsingSelector:@selector(compare:)]) {
            if (![f hasSuffix:@".plist"]) continue;
            NSString *base = [f stringByDeletingPathExtension], *lib = [base stringByAppendingString:@".dylib"], *libPath = [dir stringByAppendingPathComponent:lib];
            if (![fm fileExistsAtPath:libPath]) continue;   // (switched off by renaming, or a plist alone)
            if (MSBDBlameIsOurName(base) || ![MSBDBlameOtherTweakName(libPath, lib) length]) continue;
            if (!MSBDBlameFilterLoadsInSpringBoard([NSDictionary dictionaryWithContentsOfFile:[dir stringByAppendingPathComponent:f]])) continue;
            if (MSBDBlameChoicyKeepsOut(choicy, base) || MSBDBlameChoicyKeepsOut(choicy, [base stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]])) continue;
            [o addObject:[lib stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
        }
    }
    return o.array;
}

// ---- What crashed: the cause, where, and our death record (1.8.7.7, GitHub #14) ----------------------------------------------------------------------
// Before, nothing named the culprit of an Apple-only crash: neither we nor the user could tell. Now each judged report gets a cause and a place:
//  cause: the exception's reason from our death record (common/CrashCause.h: the only source on 15/16, whose reports carry none), else the report's
//         own "exceptionReason" (17/18, sometimes), else the stuck service of a watchdog report, else the exception type, signal and subtype (with an
//         Apple assertion text from "asi" if there is one);
//  where: the first frame of the exception backtrace past the throw itself, else of the crashing thread past abort and the waits, with its image.
// A reason of the "-[Class selector]: unrecognized selector" kind also names the library of that class when it is loaded here (the class of a
// listener that did not answer: crash 4 of #14). Library names only, never paths.
#ifndef MSBD_CAUSE_FILE   // (= CrashCause.h; overridable for the Mac test)
#define MSBD_CAUSE_FILE "/var/jb/var/mobile/Library/Preferences/MacStatusBarAndDock-CrashCauses.txt"
#endif
#define MSBD_CAUSE_KEEP_LINES 16
#define MSBD_CAUSE_TRIM_BYTES 8192
// The death record kept short: once it passes 8 KB, its last 16 lines (the guard when it judges, Settings when it shows a crash).
static inline void MSBDCauseTrim(void) {
    NSDictionary *a = [[NSFileManager defaultManager] attributesOfItemAtPath:@MSBD_CAUSE_FILE error:nil];
    if (!a || [a fileSize] <= MSBD_CAUSE_TRIM_BYTES) return;
    NSString *text = [[NSString alloc] initWithData:[NSData dataWithContentsOfFile:@MSBD_CAUSE_FILE] encoding:NSUTF8StringEncoding] ?: @"";
    NSMutableArray *lines = [[text componentsSeparatedByString:@"\n"] mutableCopy];
    [lines removeObject:@""];
    if (lines.count > MSBD_CAUSE_KEEP_LINES) [lines removeObjectsInRange:NSMakeRange(0, lines.count - MSBD_CAUSE_KEEP_LINES)];
    [[[lines componentsJoinedByString:@"\n"] stringByAppendingString:lines.count ? @"\n" : @""] writeToFile:@MSBD_CAUSE_FILE atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
// A report's time stamp ("2026-11-16 16:30:49.5186 +0800"): seconds since 1970, or 0.
static inline long MSBDBlameReportTime(id stamp) {
    if (![stamp isKindOfClass:[NSString class]]) return 0;
    NSArray *p = [stamp componentsSeparatedByString:@" "];
    if (p.count < 3) return 0;
    NSString *hms = [p[1] componentsSeparatedByString:@"."].firstObject;
    static NSDateFormatter *df; static dispatch_once_t once;
    dispatch_once(&once, ^{ df = [NSDateFormatter new]; df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]; df.dateFormat = @"yyyy-MM-dd HH:mm:ss Z"; });
    NSDate *d = nil;
    @synchronized (df) { d = [df dateFromString:[NSString stringWithFormat:@"%@ %@ %@", p[0], hms, p[2]]]; }
    return d ? (long)d.timeIntervalSince1970 : 0;
}
// Our death record's line for the SpringBoard a report tells about (its pid; the line written between that SpringBoard's launch and 10 s after
// the report's capture): @[pid, time, thread, name, reason, class], or nil. The last such line, if there are several.
static inline NSArray<NSString *> *MSBDCauseLineFor(NSDictionary *body) {
    if (![body isKindOfClass:[NSDictionary class]] || ![body[@"pid"] isKindOfClass:[NSNumber class]]) return nil;
    long pid = [body[@"pid"] longValue], launch = MSBDBlameReportTime(body[@"procLaunch"]), capture = MSBDBlameReportTime(body[@"captureTime"]);
    if (pid <= 0 || !capture) return nil;
    if (!launch || launch > capture) launch = capture - 86400;
    NSData *d = [NSData dataWithContentsOfFile:@MSBD_CAUSE_FILE options:NSDataReadingUncached error:nil];
    if (!d.length || d.length > 256 * 1024) return nil;
    NSString *text = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: [[NSString alloc] initWithData:d encoding:NSISOLatin1StringEncoding];
    NSArray *found = nil;
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSArray *f = [line componentsSeparatedByString:@"\t"];
        if (f.count < 6 || [f[0] longLongValue] != pid) continue;
        long t = (long)[f[1] longLongValue];
        if (t < launch - 1 || t > capture + 10) continue;
        found = f;
    }
    return found;
}
// The room of each part of the helper's cause line, in BYTES of UTF-8 (review of 1.8.7.7: in characters a non-ASCII reason took up to three times
// its room and the guard's buffers cut the other tweaks -- the suspects -- off the end; CrashGuard.h MSBD_GUARD_CAUSE_MAX holds all three).
#define MSBD_CAUSE_BYTES 420
#define MSBD_WHERE_BYTES 200
#define MSBD_OTHERS_BYTES 300
// One line of text: no tabs or line breaks, at most `max` bytes of UTF-8, cut at a whole character with "…".
static inline NSString *MSBDCauseOneLine(NSString *s, NSUInteger max) {
    if (![s isKindOfClass:[NSString class]]) return @"";
    NSString *one = [[s componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\t\r\n"]] componentsJoinedByString:@" "];
    one = [one stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([one lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= max) return one;
    NSUInteger room = max > 3 ? max - 3 : 0, used = 0, end = 0;   // ("…" takes 3 bytes)
    while (end < one.length) {
        NSRange r = [one rangeOfComposedCharacterSequenceAtIndex:end];
        NSUInteger b = [[one substringWithRange:r] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        if (used + b > room) break;
        used += b; end = NSMaxRange(r);
    }
    return [[one substringToIndex:end] stringByAppendingString:@"…"];
}
// The library of the class an "-[Class selector]: unrecognized selector" reason names, when that class is loaded here and not Apple's ("" if not).
// (Review of 1.8.7.7: at SpringBoard's start the tweaks after ours have not loaded yet, so the guard asks again 8 s later, CrashGuard.h
// MSBDGuardClassLook and the helper's MSBDCrashCauseClass.)
static inline NSString *MSBDCauseClassLibrary(NSString *reason) {
    NSRange r = [reason rangeOfString:@"[" options:0];
    if (r.location == NSNotFound || r.location == 0) return @"";
    unichar k = [reason characterAtIndex:r.location - 1];
    if (k != '-' && k != '+') return @"";
    NSUInteger s = NSMaxRange(r), e = s;
    while (e < reason.length && ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:[reason characterAtIndex:e]] || [reason characterAtIndex:e] == '_' || [reason characterAtIndex:e] == '.')) e++;
    if (e == s || e - s > 200) return @"";
    Class c = NSClassFromString([reason substringWithRange:NSMakeRange(s, e - s)]);
    const char *image = c ? class_getImageName(c) : NULL;
    if (!image) return @"";
    NSString *path = @(image), *name = path.lastPathComponent;
    MSBDImgKind kind = MSBDBlameImageKind(path, name);
    return kind == kMSBDImgOurs ? @"MacStatusBar&Dock" : kind == kMSBDImgOther ? name : @"";
}
// The cause with " (that class is in <library>)" at its end, the cause cut so that both fit MSBD_CAUSE_BYTES (the library is what it adds).
static inline NSString *MSBDCauseWithLibrary(NSString *cause, NSString *lib) {
    NSString *tail = MSBDCauseOneLine([NSString stringWithFormat:@"(that class is in %@)", lib ?: @"?"], MSBD_CAUSE_BYTES / 2);
    NSUInteger tb = [tail lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + 1;   // (with the space before it)
    return [NSString stringWithFormat:@"%@ %@", MSBDCauseOneLine(cause, MSBD_CAUSE_BYTES - tb), tail];
}
static inline NSString *MSBDBlameCauseText(NSDictionary *body, NSArray<NSString *> *death) {
    if (![body isKindOfClass:[NSDictionary class]]) return @"";
    NSString *cause = nil;
    if (death.count >= 6) {
        NSString *name = [death[3] isEqualToString:@"-"] ? @"" : death[3], *reason = [death[4] isEqualToString:@"-"] ? @"" : death[4];
        cause = name.length && reason.length ? [NSString stringWithFormat:@"%@: %@", name, reason] : name.length ? name : reason.length ? reason : nil;
    }
    NSDictionary *er = [body[@"exceptionReason"] isKindOfClass:[NSDictionary class]] ? body[@"exceptionReason"] : nil;
    if (!cause.length && er) {
        NSString *name = [er[@"name"] isKindOfClass:[NSString class]] ? er[@"name"] : @"", *msg = [er[@"composed_message"] isKindOfClass:[NSString class]] ? er[@"composed_message"] : @"";
        cause = name.length && msg.length ? [NSString stringWithFormat:@"%@: %@", name, msg] : name.length ? name : msg.length ? msg : nil;
    }
    NSDictionary *t = [body[@"termination"] isKindOfClass:[NSDictionary class]] ? body[@"termination"] : nil;
    if (!cause.length && [t[@"namespace"] isEqual:@"WATCHDOG"]) cause = [NSString stringWithFormat:@"stuck, ended by the watchdog: %@", [t[@"indicator"] isKindOfClass:[NSString class]] ? t[@"indicator"] : @"no answer"];
    if (!cause.length) {
        NSDictionary *e = [body[@"exception"] isKindOfClass:[NSDictionary class]] ? body[@"exception"] : nil;
        NSString *type = [e[@"type"] isKindOfClass:[NSString class]] ? e[@"type"] : @"", *sig = [e[@"signal"] isKindOfClass:[NSString class]] ? e[@"signal"] : @"";
        NSString *sub = [e[@"subtype"] isKindOfClass:[NSString class]] ? e[@"subtype"] : @"";
        NSMutableString *m = [NSMutableString stringWithString:type];
        if (sig.length) [m appendFormat:@"%@(%@)", m.length ? @" " : @"", sig];
        if (sub.length) [m appendFormat:@" %@", sub];
        if ([body[@"lastExceptionBacktrace"] isKindOfClass:[NSArray class]]) [m appendString:@": uncaught exception, its reason not in the report"];
        NSMutableArray<NSString *> *asi = [NSMutableArray array];   // (the messages, not the images they come from)
        if ([body[@"asi"] isKindOfClass:[NSDictionary class]]) for (id k in body[@"asi"]) MSBDBlameCollectText(((NSDictionary *)body[@"asi"])[k], asi, 0);
        for (NSString *a in asi) if (a.length && ![a isEqualToString:@"abort() called"]) { [m appendFormat:@" -- %@", a]; break; }
        cause = m.length ? m : @"not given in the report";
    }
    NSString *lib = MSBDCauseClassLibrary(cause);
    return lib.length ? MSBDCauseWithLibrary(cause, lib) : MSBDCauseOneLine(cause, MSBD_CAUSE_BYTES);
}
// Where: the first frame of the exception backtrace past the throw (or the forwarding of an unknown selector), else of the crashing thread past
// abort, the terminate handlers and the waits; "<symbol> (<image name>)" or "<image name> + 0x<offset>".
static inline NSString *MSBDBlameWhere(NSDictionary *body) {
    if (![body isKindOfClass:[NSDictionary class]]) return @"";
    static NSSet *machinery; static dispatch_once_t once;
    dispatch_once(&once, ^{
        machinery = [NSSet setWithArray:@[@"__exceptionPreprocess", @"objc_exception_throw", @"objc_exception_rethrow", @"-[NSException raise]", @"+[NSException raise:format:]",
            @"+[NSException raise:format:arguments:]", @"___forwarding___", @"_CF_forwarding_prep_0", @"-[NSObject(NSObject) doesNotRecognizeSelector:]", @"__pthread_kill",
            @"pthread_kill", @"abort", @"abort_message", @"demangling_terminate_handler()", @"_objc_terminate()", @"std::__terminate(void (*)())", @"std::terminate()",
            @"__cxa_rethrow", @"__cxa_throw", @"__psynch_cvwait", @"_pthread_cond_wait", @"mach_msg2_trap", @"mach_msg_trap", @"mach_msg2_internal", @"mach_msg_overwrite",
            @"mach_msg", @"__semwait_signal", @"semaphore_wait_trap", @"_dispatch_sema4_wait", @"_dispatch_semaphore_wait_slow", @"__abort_with_payload",
            @"abort_with_payload_wrapper_internal", @"abort_with_payload", @"_os_crash", @"_os_crash_callback", @"__assert_rtn", @"__CFRunLoopServiceMachPort",
            @"+[NSObject(NSObject) _copyDescription]", @"-[NSException initWithCoder:]", @"_userInfoForFileAndLine", @"-[NSException initWithName:reason:userInfo:]",
            @"+[NSException exceptionWithName:reason:userInfo:]", @"-[NSAssertionHandler handleFailureInMethod:object:file:lineNumber:description:]",
            @"-[NSAssertionHandler handleFailureInFunction:file:lineNumber:description:]", @"_NSAssertionFailure"]];
    });
    NSArray *images = nil, *extra = nil;
    MSBDBlameImageLists(body, &images, &extra);
    NSArray *threads = [body[@"threads"] isKindOfClass:[NSArray class]] ? body[@"threads"] : nil, *fault = nil;
    id ft = body[@"faultingThread"];
    if ([ft isKindOfClass:[NSNumber class]] && [ft unsignedIntegerValue] < threads.count && [threads[[ft unsignedIntegerValue]] isKindOfClass:[NSDictionary class]]) fault = threads[[ft unsignedIntegerValue]][@"frames"];
    if (![fault isKindOfClass:[NSArray class]]) {
        fault = nil;
        for (NSDictionary *t in threads) if ([t isKindOfClass:[NSDictionary class]] && [t[@"triggered"] boolValue] && [t[@"frames"] isKindOfClass:[NSArray class]]) { fault = t[@"frames"]; break; }
    }
    NSArray *exc = [body[@"lastExceptionBacktrace"] isKindOfClass:[NSArray class]] ? body[@"lastExceptionBacktrace"] : nil;
    for (NSArray *frames in @[exc ?: @[], fault ?: @[]]) {
        for (NSUInteger k = MSBDBlameFirstFrame(frames); k < frames.count; k++) {
            NSDictionary *f = frames[k];
            if (![f isKindOfClass:[NSDictionary class]]) continue;
            NSString *sym = [f[@"symbol"] isKindOfClass:[NSString class]] ? f[@"symbol"] : nil;
            if (sym && ([machinery containsObject:sym] || [sym rangeOfString:@".cold."].location != NSNotFound)) continue;   // (and an outlined throw path)
            NSUInteger i = [f[@"imageIndex"] isKindOfClass:[NSNumber class]] ? [f[@"imageIndex"] unsignedIntegerValue] : NSNotFound;
            NSString *image = i != NSNotFound ? MSBDBlameImageAt(images, extra, i, NULL) : nil;
            image = [image stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (sym.length && ![sym hasPrefix:@"("]) return MSBDCauseOneLine(image.length ? [NSString stringWithFormat:@"%@ (%@)", sym, image] : sym, MSBD_WHERE_BYTES);
            if (image.length) return MSBDCauseOneLine([NSString stringWithFormat:@"%@ + 0x%llx", image, [f[@"imageOffset"] isKindOfClass:[NSNumber class]] ? [f[@"imageOffset"] unsignedLongLongValue] : 0ULL], MSBD_WHERE_BYTES);
        }
    }
    return @"";
}
