// EngineBuilds.h -- the window-engine builds our integration is tested with, and the default engine (MacStatusBar&Dock, 2026-09-26). One list for
// SpringBoard (StatusBar.x), Settings (MSBRootListController.m) and the root helper (sshtoggled), so they can never disagree.
// A build is known by the Mach-O UUIDs of its library's slices (`dwarfdump --uuid` on the dylib from its deb). To support a new build: test it on
// every engine path, then add its UUIDs here.
#pragma once
#import <Foundation/Foundation.h>
#include <mach-o/loader.h>
#include <libkern/OSByteOrder.h>

typedef struct { const char *uuid, *lib, *label; } MSBDEngineBuild;
static const MSBDEngineBuild kMSBDEngineBuilds[] = {
    { "568387C3-2FE1-462F-BA83-EE6106D17B6A", "Aerial", "3.0 arm64" },    { "AC58C835-40C3-4296-B2E8-9563162C5DDD", "Aerial", "3.0 arm64e" },
    { "6F9F6C99-29EC-3942-8F61-80B303352B77", "Aerial", "5.0 arm64" },    { "1950C538-AD6B-3BC4-B693-3610F17CC9E9", "Aerial", "5.0 arm64e" },
    { "3D644D4C-2038-35E6-A128-A4061306E793", "Zetsu", "1.6.2 arm64" },   { "3518C322-674E-3ADD-8397-561EBCA731F6", "Zetsu", "1.6.2 arm64e" },
    { "6B98C0C5-D07B-36CC-828A-AE17C7F0CABA", "Zetsu", "1.6.6 arm64" },   { "BFAC898D-9182-3D0E-AC4C-85EF13063477", "Zetsu", "1.6.6 arm64e" },
    { "193A0C73-A67B-30A3-BC48-6D0BB5195532", "MilkyWay4", "0.1.1 arm64" }, { "1FD3346D-4025-3E55-8A87-DFAC6673888F", "MilkyWay4", "0.1.1 arm64e" },
};

// The tested build a UUID belongs to for that engine library ("5.0 arm64e"), nil if none.
static inline NSString *MSBDEngineBuildLabel(NSString *lib, NSString *uuid) {
    for (size_t i = 0; i < sizeof(kMSBDEngineBuilds) / sizeof(kMSBDEngineBuilds[0]); i++)
        if ([lib isEqualToString:@(kMSBDEngineBuilds[i].lib)] && [uuid caseInsensitiveCompare:@(kMSBDEngineBuilds[i].uuid)] == NSOrderedSame) return @(kMSBDEngineBuilds[i].label);
    return nil;
}

// The Mach-O UUIDs of a library file (every slice of a fat file), read without loading it.
static inline NSSet<NSString *> *MSBDDylibUUIDs(NSString *path) {
    NSData *d = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (d.length < sizeof(struct mach_header_64)) return nil;
    const uint8_t *b = d.bytes; NSMutableSet *out = [NSMutableSet set];
    void (^slice)(uint64_t) = ^(uint64_t off) {
        if (off + sizeof(struct mach_header_64) > d.length) return;
        const struct mach_header_64 *mh = (const struct mach_header_64 *)(b + off);
        if (mh->magic != MH_MAGIC_64) return;
        uint64_t p = off + sizeof(struct mach_header_64);
        for (uint32_t i = 0; i < mh->ncmds && p + sizeof(struct load_command) <= d.length; i++) {
            const struct load_command *lc = (const struct load_command *)(b + p);
            if (lc->cmd == LC_UUID && p + sizeof(struct uuid_command) <= d.length) { [out addObject:[[[NSUUID alloc] initWithUUIDBytes:((const struct uuid_command *)lc)->uuid] UUIDString]]; return; }
            if (!lc->cmdsize) return;
            p += lc->cmdsize;
        }
    };
    if (OSSwapBigToHostInt32(*(const uint32_t *)b) == 0xcafebabe) {   // FAT_MAGIC (big-endian header)
        uint32_t n = OSSwapBigToHostInt32(*(const uint32_t *)(b + 4));
        for (uint32_t i = 0; i < n && 8 + (i + 1) * 20 <= d.length; i++) slice(OSSwapBigToHostInt32(*(const uint32_t *)(b + 8 + i * 20 + 8)));
    } else slice(0);
    return out;
}

// Every slice of the file is a tested build of that engine.
static inline BOOL MSBDEngineFileTested(NSString *lib, NSString *path) {
    NSSet *uuids = MSBDDylibUUIDs(path);
    if (!uuids.count) return NO;
    for (NSString *u in uuids) if (!MSBDEngineBuildLabel(lib, u)) return NO;
    return YES;
}

// The engine used when none is picked (or the picked one is not installed), the same order as DMActiveEngineUncached in SpringBoard: Aerial (any
// build: an untested one runs on its own, still the engine), else MilkyWay4 (iPadOS 15 only, a tested build), else Zetsu (a tested build).
// `installed` says whether an engine's package is installed; nil = none.
static inline NSString *MSBDDefaultEngine(BOOL (^installed)(NSString *engine), NSString *(^libraryPath)(NSString *lib)) {
    if (installed(@"aerial")) return @"aerial";
    if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion < 16 && installed(@"milkyway") && MSBDEngineFileTested(@"MilkyWay4", libraryPath(@"MilkyWay4"))) return @"milkyway";
    if (installed(@"zetsu") && MSBDEngineFileTested(@"Zetsu", libraryPath(@"Zetsu"))) return @"zetsu";
    return nil;
}
