// UpdateCheck.h -- "MacStatusBar&Dock Update…" in the Apple menu, shown only while a newer version of this package is waiting (2026-09-30).
// Nothing is downloaded by us (README/SECURITY: the tweak never contacts a server). The package managers download our repo's package list
// whenever they refresh; that local copy is read here and compared with the installed version (dpkg's status file). So the row appears once
// Sileo or Zebra has seen the update, and goes away as soon as it is installed. A tap opens our package in the first package manager
// installed: Sileo, then Zebra, then Cydia. Objective-C (Foundation); CrashExplain.h's MSBD_DPKG_DIR / MSBDPackageVersion.
#pragma once
#import <Foundation/Foundation.h>
#include <sys/stat.h>
#include "CrashExplain.h"   // (MSBD_DPKG_DIR, MSBDPackageVersion)

#define MSBD_PACKAGE_ID @"com.besiktasliseba.macstatusbaranddock"

// dpkg's own version order (epoch:upstream-revision; letters sort before non-letters, "~" before everything), so "1.1.7-4+debug" > "1.1.7".
static inline int MSBDVerOrder(unichar c) {
    if (c >= '0' && c <= '9') return 0;
    if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')) return c;
    if (c == '~') return -1;
    return c ? c + 256 : 0;
}
static inline int MSBDVerRevCmp(NSString *a, NSString *b) {
    NSUInteger i = 0, j = 0, la = a.length, lb = b.length;
    while (i < la || j < lb) {
        int first = 0;
        while ((i < la && !isdigit([a characterAtIndex:i])) || (j < lb && !isdigit([b characterAtIndex:j]))) {
            int ac = i < la ? MSBDVerOrder([a characterAtIndex:i]) : 0, bc = j < lb ? MSBDVerOrder([b characterAtIndex:j]) : 0;
            if (ac != bc) return ac - bc;
            i++; j++;
        }
        while (i < la && [a characterAtIndex:i] == '0') i++;
        while (j < lb && [b characterAtIndex:j] == '0') j++;
        while (i < la && isdigit([a characterAtIndex:i]) && j < lb && isdigit([b characterAtIndex:j])) {
            if (!first) first = [a characterAtIndex:i] - [b characterAtIndex:j];
            i++; j++;
        }
        if (i < la && isdigit([a characterAtIndex:i])) return 1;
        if (j < lb && isdigit([b characterAtIndex:j])) return -1;
        if (first) return first;
    }
    return 0;
}
static inline void MSBDVerSplit(NSString *v, long *epoch, NSString **up, NSString **rev) {
    *epoch = 0; NSRange c = [v rangeOfString:@":"];
    if (c.location != NSNotFound) { *epoch = [[v substringToIndex:c.location] integerValue]; v = [v substringFromIndex:c.location + 1]; }
    NSRange d = [v rangeOfString:@"-" options:NSBackwardsSearch];
    *up = d.location != NSNotFound ? [v substringToIndex:d.location] : v;
    *rev = d.location != NSNotFound ? [v substringFromIndex:d.location + 1] : @"";
}
static inline int MSBDVersionCompare(NSString *a, NSString *b) {   // <0, 0, >0 like dpkg --compare-versions
    long ea, eb; NSString *ua, *ra, *ub, *rb;
    MSBDVerSplit(a ?: @"", &ea, &ua, &ra); MSBDVerSplit(b ?: @"", &eb, &ub, &rb);
    if (ea != eb) return ea < eb ? -1 : 1;
    int r = MSBDVerRevCmp(ua, ub);
    return r ? r : MSBDVerRevCmp(ra, rb);
}

// The package lists the package managers downloaded for our repo: Sileo's (APT's lists) and Zebra's own copy.
static inline NSArray<NSString *> *MSBDRepoListFiles(void) {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *dir in @[@"/var/jb/var/lib/apt/lists", @"/var/mobile/Library/Application Support/xyz.willy.Zebra/lists"]) {
        for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil])
            if ([f hasPrefix:@"besiktasliseba.github.io_repo"] && [f hasSuffix:@"Packages"]) [out addObject:[dir stringByAppendingPathComponent:f]];
    }
    return out;
}
// The newest version of this package in those lists, or nil. Cached until one of the files (or dpkg's status) changes.
static inline NSString *MSBDNewestListedVersion(void) {
    NSString *best = nil;
    for (NSString *path in MSBDRepoListFiles()) {
        NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        for (NSString *block in [text componentsSeparatedByString:@"\n\n"]) {
            if (![block containsString:@"Package: " MSBD_PACKAGE_ID "\n"] && ![block hasSuffix:@"Package: " MSBD_PACKAGE_ID]) continue;
            for (NSString *line in [block componentsSeparatedByString:@"\n"]) {
                if (![line hasPrefix:@"Version: "]) continue;
                NSString *v = [[line substringFromIndex:9] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if (v.length && (!best || MSBDVersionCompare(v, best) > 0)) best = v;
            }
        }
    }
    return best;
}
static inline NSString *MSBDUpdateAvailable(NSString *installed) {   // the newer version waiting, or nil (none, or not installed through dpkg)
    static NSString *cachedKey, *cachedResult;
    NSMutableString *key = [NSMutableString stringWithString:installed ?: @""];
    for (NSString *path in [MSBDRepoListFiles() arrayByAddingObject:@MSBD_DPKG_DIR "/status"]) {
        struct stat st; if (stat(path.fileSystemRepresentation, &st) == 0) [key appendFormat:@"|%@:%ld.%ld", path.lastPathComponent, (long)st.st_mtimespec.tv_sec, (long)st.st_size];
    }
    if ([key isEqualToString:cachedKey]) return cachedResult;
    NSString *listed = installed.length ? MSBDNewestListedVersion() : nil;
    cachedKey = key;
    cachedResult = (listed && MSBDVersionCompare(listed, installed) > 0) ? listed : nil;
    return cachedResult;
}
// Our package page in the first package manager installed (Sileo, Zebra, Cydia): its URL, or nil when none of them is there.
static inline NSURL *MSBDPackageManagerURL(BOOL (^installed)(NSString *bundleID), NSString **bundleOut) {
    NSArray *managers = @[
        @[@"org.coolstar.SileoStore", @"sileo://package/" MSBD_PACKAGE_ID],
        @[@"ml.singlekeycap.sileo", @"sileo://package/" MSBD_PACKAGE_ID],
        @[@"xyz.willy.Zebra", @"zbra://packages/" MSBD_PACKAGE_ID],
        @[@"com.saurik.Cydia", @"cydia://package/" MSBD_PACKAGE_ID],
    ];
    for (NSArray *m in managers) if (installed(m[0])) { if (bundleOut) *bundleOut = m[0]; return [NSURL URLWithString:m[1]]; }
    return nil;
}
