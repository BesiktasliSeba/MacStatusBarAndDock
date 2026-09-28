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
//  APPLE  only Apple code (and the hooking platform: ElleKit, systemhook, ...) on those stacks -- counted: our actions can crash Apple code without
//         a single frame of ours on the stack (the FBSceneMonitor dealloc assert seen before), so this stays as careful as before;
//  OTHER  another tweak's library is the top-most non-Apple image -- NOT counted (another tweak's crash must not switch us off), even when one of
//         our hooks is lower on the stack: -[UIApplication sendEvent:] and -[UIResponder pressesBegan:withEvent:] (the Dock, the volume keys)
//         are on nearly every touch and key stack. Such pass-through hooks are marked "transparent" in the crash map
//         (tools/crashmap-rules.txt): they give way to any other non-Apple code below them (a tweak that called through them), and count as ours
//         only when nothing but Apple code is around them;
//  UNKNOWN the report could not be read or understood -- counted (the old behaviour).
// Frames above "_sigtramp" belong to a signal handler (a crash reporter, our own test builds' death log), not to the crash: they are skipped.
// Cost: one read of at most 3 MB and one JSON parse, only for a crash report found after an early start; the verdict is cached by the caller.
#pragma once
#import <Foundation/Foundation.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>

enum { kMSBDBlameUnknown = 0, kMSBDBlameOurs = 1, kMSBDBlameApple = 2, kMSBDBlameOther = 3 };
#define MSBD_BLAME_MAX_BYTES (3 * 1024 * 1024)

// Our libraries by name (for a report that gives only names): the two loaders and the parts (Makefile PAYLOADS, MacCrashBlame).
static inline BOOL MSBDBlameIsOurName(NSString *name) {
    static NSSet *ours;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ours = [NSSet setWithArray:@[@"MacStatusBar", @"MacDock", @"MacCrashBlame", @"BrightnessKeyTweak", @"DockMagnification", @"DockMagnificationSettings",
            @"ForceQuitMenu", @"GraveEscapeTweak", @"MacAppBridge", @"MacAppSizeMenu", @"MacCCGrabber", @"MacCrashNotice", @"MacEthernetFix", @"MacFolderMenu", @"MacHomeBar",
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
// `map`: the crash map's text (CrashMap.txt), for the transparent hooks; nil = none known.
static inline int MSBDBlameReportBodyMapCore(NSDictionary *body, NSString *map, NSString **blamed) {
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
    // The top-most frame that is not Apple's decides, on the exception backtrace first (where it was thrown), else on the faulting thread.
    for (int pass = 0; pass < 2 && !ourImage && !otherImage; pass++) {
        NSArray *frames = pass == 0 ? excFrames : faultFrames;
        NSString *where = pass == 0 ? @"exception backtrace" : @"faulting thread";
        NSString *engine = nil;   // (a window engine on top: ours only if our own code called it)
        NSString *passThrough = nil;   // (one of our pass-through hooks: ours only if no other non-Apple code is below it)
        for (NSUInteger k = MSBDBlameFirstFrame(frames); k < frames.count; k++) {
            NSDictionary *f = frames[k];
            if (![f isKindOfClass:[NSDictionary class]] || ![f[@"imageIndex"] isKindOfClass:[NSNumber class]]) continue;
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
            else if (passThrough) ourImage = passThrough;   // (nothing but Apple code besides it: as before, ours)
        }
    }
    if (ourImage) { if (blamed) *blamed = ourImage; return kMSBDBlameOurs; }
    // Our names in the crash text: the exception, the "asi" messages (the reason of an uncaught exception, assertion texts) and termination reasons.
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    for (NSString *key in @[@"exception", @"asi", @"termination"]) MSBDBlameCollectText(body[key], texts, 0);
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
static inline int MSBDBlameReportBodyMap(NSDictionary *body, NSString *map, NSString **blamed) {
    NSString *what = nil;
    int v = MSBDBlameReportBodyMapCore(body, map, &what);
    if (MSBDBlameIsWatchdog(body)) what = [@"watchdog:" stringByAppendingString:[what stringByReplacingOccurrencesOfString:@"faulting thread" withString:@"stuck main thread"] ?: @""];
    if (blamed) *blamed = what;
    return v;
}
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
    for (NSArray *f in uf) {
        if (![f isKindOfClass:[NSArray class]] || f.count < 2 || ![f[0] isKindOfClass:[NSNumber class]] || ![f[1] isKindOfClass:[NSNumber class]]) continue;
        NSUInteger bi = [f[0] unsignedIntegerValue];
        NSArray *img = bi < bin.count && [bin[bi] isKindOfClass:[NSArray class]] ? bin[bi] : nil;
        NSString *uuid = img.count >= 3 && [img[0] isKindOfClass:[NSString class]] ? [img[0] lowercaseString] : @"";
        NSString *kind = img.count >= 3 && [img[2] isKindOfClass:[NSString class]] ? img[2] : @"";
        NSString *path = [kind isEqualToString:@"S"] ? @"/System/Library/Caches/com.apple.dyld/dyld_shared_cache" : [kind isEqualToString:@"K"] ? @"/System/Library/Kernels/kernel" : byUUID[uuid];
        if (!path) break;   // (unnamed code: nothing below it may clear us)
        NSNumber *key = @(bi);
        if (!indexOf[key]) { indexOf[key] = @(images.count); [images addObject:@{@"path": path, @"name": path.lastPathComponent, @"uuid": uuid}]; }
        [frames addObject:@{@"imageIndex": indexOf[key], @"imageOffset": f[1]}];
    }
    NSMutableDictionary *out = [body mutableCopy];
    out[@"usedImages"] = images;
    out[@"threads"] = @[@{@"triggered": @YES, @"frames": frames, @"queue": @"com.apple.main-thread"}];
    out[@"msbdStackshot"] = @YES;
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
        for (NSUInteger k = MSBDBlameFirstFrame(frames); k < frames.count; k++) {
            NSDictionary *f = frames[k];
            if (out.count >= max) break;
            if (![f isKindOfClass:[NSDictionary class]] || ![f[@"imageIndex"] isKindOfClass:[NSNumber class]]) continue;
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
