// FinderOpenWith.h -- Open With, as a Mac's Finder has it (1.8.8.1 B67, KT 21 Nov: "ipa's etc should be able to be opened in trollstore"): which
// apps open a file, read from the apps' own Info.plists, and where the copy handed to the chosen app goes. The file goes as iOS's own Open In hands
// one over (a copy in the app's Documents/Inbox, the file itself never), and the app opens the way its Dock icon opens it: a window when apps open
// as windows (Finder.h DMFinderOpenWith). Foundation only: Finder.h runs it, tools/test-finderopenwith.m checks it on the Mac.
#pragma once
#import <Foundation/Foundation.h>
#include <string.h>

// Catch-all types: an app that opens any file at all (Files, a file manager) is not offered for every file -- a Mac keeps those under Other...
// (No blocks in this file: a block's symbol (___DMFinder...) is not Finder's by the crash map's symbol rule -- every function here is a DMFinder... one.)
static BOOL DMFinderOpenWithCatchAll(NSString *type) {
    if (![type isKindOfClass:[NSString class]] || !type.length) return YES;
    static const char *const all[] = {"public.item", "public.data", "public.content", "public.composite-content", "public.directory", "public.folder", "*"};
    const char *t = type.lowercaseString.UTF8String;
    for (size_t i = 0; t && i < sizeof all / sizeof all[0]; i++) if (!strcmp(t, all[i])) return YES;
    return NO;
}
// LSHandlerRank as LaunchServices reads it: Owner 3, Default 2 (also when none is given), Alternate 1, None 0 (the app does not open that type).
static int DMFinderOpenWithRankOf(id rank) {
    if (![rank isKindOfClass:[NSString class]]) return 2;
    NSString *r = [(NSString *)rank lowercaseString];
    return [r isEqualToString:@"owner"] ? 3 : [r isEqualToString:@"alternate"] ? 1 : [r isEqualToString:@"none"] ? 0 : 2;
}
// The best claim an app's Info.plist makes on a file, 0 for none. `ext`: the file's extension; `types`: every type this system declares with that
// extension and each one's parents (an .ipa is Apple's ipa type and, on the iPad 2, Filza's too: which one ".ipa" alone gives depends on the order
// the apps were installed, FinderIPA.h -- TrollStore claims Apple's). A document type (CFBundleDocumentTypes) claims the file by one of its types
// (LSItemContentTypes, case does not matter) or, an older app's, by the extension itself (CFBundleTypeExtensions); a catch-all claims nothing here.
static int DMFinderOpenWithRank(NSDictionary *info, NSString *ext, NSArray<NSString *> *types) {
    id docs = [info isKindOfClass:[NSDictionary class]] ? info[@"CFBundleDocumentTypes"] : nil;
    if (![docs isKindOfClass:[NSArray class]]) return 0;
    NSString *e = [ext isKindOfClass:[NSString class]] ? ext.lowercaseString : @"";
    NSMutableSet<NSString *> *want = [NSMutableSet set];
    for (id t in [types isKindOfClass:[NSArray class]] ? types : @[]) if ([t isKindOfClass:[NSString class]] && !DMFinderOpenWithCatchAll(t)) [want addObject:[(NSString *)t lowercaseString]];
    int best = 0;
    for (id d in (NSArray *)docs) {
        if (![d isKindOfClass:[NSDictionary class]]) continue;
        BOOL claims = NO;
        id its = d[@"LSItemContentTypes"];
        if ([its isKindOfClass:[NSArray class]]) for (id t in (NSArray *)its) if ([t isKindOfClass:[NSString class]] && [want containsObject:[(NSString *)t lowercaseString]]) claims = YES;
        id exts = d[@"CFBundleTypeExtensions"];
        if (!claims && e.length && ![e isEqualToString:@"*"] && [exts isKindOfClass:[NSArray class]])
            for (id x in (NSArray *)exts) if ([x isKindOfClass:[NSString class]] && [[(NSString *)x lowercaseString] isEqualToString:e]) claims = YES;
        if (!claims) continue;
        int r = DMFinderOpenWithRankOf(d[@"LSHandlerRank"]);
        if (r > best) best = r;
    }
    return best;
}
// (the list's order: an owner before the others, then by name, then by bundle id)
static NSInteger DMFinderOpenWithCompare(NSDictionary *x, NSDictionary *y, void *context) {
    BOOL ox = [x[@"r"] intValue] >= 3, oy = [y[@"r"] intValue] >= 3;
    if (ox != oy) return ox ? NSOrderedAscending : NSOrderedDescending;
    NSComparisonResult c = [x[@"t"] localizedStandardCompare:y[@"t"]];
    return c != NSOrderedSame ? c : [x[@"b"] compare:y[@"b"]];
}
// The Open With list from the apps that claim the file (@{b: bundle id, t: name, r: its rank}): the owners first (a Mac's default app heads its
// list), then the others, each by name; one row per app, none without a bundle id or a claim.
static NSArray<NSDictionary *> *DMFinderOpenWithOrder(NSArray<NSDictionary *> *apps) {
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id a in [apps isKindOfClass:[NSArray class]] ? apps : @[]) {
        if (![a isKindOfClass:[NSDictionary class]]) continue;
        NSString *b = a[@"b"]; id r = a[@"r"];
        if (![b isKindOfClass:[NSString class]] || !b.length || ![r respondsToSelector:@selector(intValue)] || [r intValue] <= 0 || [seen containsObject:b]) continue;
        [seen addObject:b];
        NSString *t = [a[@"t"] isKindOfClass:[NSString class]] && [a[@"t"] length] ? a[@"t"] : b;
        [out addObject:@{@"b": b, @"t": t, @"r": @([r intValue] >= 3 ? 3 : [r intValue])}];
    }
    [out sortUsingFunction:DMFinderOpenWithCompare context:NULL];
    return out;
}
// Where the copy goes: the app's Documents/Inbox in its data container, where iOS's own Open In puts a file it hands an app -- the app may move or
// delete it there (TrollStore deletes it once it is installed or the install cancelled). A data container is .../Containers/Data/Application/<id>;
// anything else is none: LaunchServices names the user's home (/var/mobile) for an app that has no container of its own (the jailbreak's apps), and
// its Documents is nobody's Inbox. No container: `fallback` (Finder's own folder for that app, in SpringBoard's tmp). Never the file's own folder:
// only a copy is handed over.
static NSString *DMFinderOpenWithInbox(NSString *container, NSString *fallback) {
    NSString *c = [container isKindOfClass:[NSString class]] && [container hasPrefix:@"/"] ? container.stringByStandardizingPath : nil;
    NSString *id_ = c.lastPathComponent;
    if (c && id_.length && ![id_ isEqualToString:@"/"] && ![id_ isEqualToString:@"Application"] && [c.stringByDeletingLastPathComponent hasSuffix:@"/Containers/Data/Application"])
        return [[c stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:@"Inbox"];
    return fallback;
}
