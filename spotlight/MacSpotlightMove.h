// MacSpotlightMove.h -- search-143's Settings items (S-3 #1, "Tweak Settings": CoreSpotlight items of Settings whose identifiers start with
// "msbd-tweaksetting:") taken out of Apple's sections and its Top Hit, for MacSpotlight.x to show after Apple's results, and where each of our
// sections goes among Apple's (MSPPlaceOurs). Plain Foundation and the ObjC runtime (Mac test tools/test-spotmove.sh, with stand-ins for Apple's
// section and result classes).
#pragma once
#import <Foundation/Foundation.h>
#import <objc/message.h>

#define MSP_TWEAKS  @"msbd-tweaksetting:"      // (search-143's Settings items)

static id MSPCall(id o, const char *sel) {   // (a getter, only on an object that has it)
    SEL s = sel_registerName(sel);
    return o && [o respondsToSelector:s] ? ((id (*)(id, SEL))objc_msgSend)(o, s) : nil;
}
static void MSPSet(id o, const char *sel, id v) { ((void (*)(id, SEL, id))objc_msgSend)(o, sel_registerName(sel), v); }
// search-143's Settings items out of Apple's sections (copies of the sections that had them: Apple's own objects are never changed), in Apple's
// order, each once (its first place: the Top Hit's, when it was one); a section left empty goes. Returns what was taken.
static NSArray *MSPTakeTweakSettings(NSMutableArray *sections) {
    NSMutableArray *moved = [NSMutableArray array];
    NSMutableSet *ids = [NSMutableSet set];
    NSMutableIndexSet *gone = [NSMutableIndexSet indexSet];
    for (NSUInteger i = 0; i < sections.count; i++) {
        id sec = sections[i];
        NSArray *rs = MSPCall(sec, "results");
        if (![rs isKindOfClass:[NSArray class]]) continue;
        NSMutableArray *keep = [NSMutableArray array];
        BOOL took = NO;
        for (id r in rs) {
            NSString *ident = MSPCall(r, "identifier"), *app = MSPCall(r, "applicationBundleIdentifier");
            BOOL ours = [ident isKindOfClass:[NSString class]] && [ident hasPrefix:MSP_TWEAKS] && (![app isKindOfClass:[NSString class]] || [app isEqualToString:@"com.apple.Preferences"]);
            if (!ours) { [keep addObject:r]; continue; }
            took = YES;
            if (![ids containsObject:ident]) { [ids addObject:ident]; [moved addObject:r]; }
        }
        if (!took) continue;
        if (keep.count) { id copy = [sec copy]; MSPSet(copy, "setResults:", keep); sections[i] = copy; }
        else [gone addIndex:i];
    }
    [sections removeObjectsAtIndexes:gone];
    return moved;
}
// Apple's Top Hit section among the sections shown now (NSNotFound: none): SearchUI's com.apple.spotlight.tophits (15.6.1: its bundle identifier;
// its identifier is a UUID -- either is looked at). Not by the results' -topHit flags: Apple sets them in other sections too (15.6.1, "settings":
// the first results of its Settings and Files sections). With a Top Hit, Spotlight's keyboard highlight (and the field's "Open" for Return) goes
// to the list's first row: with our Actions above it "app" highlighted our Force Quit row, not App Store, so the Top Hit stays first (MSPPlaceOurs).
static NSUInteger MSPTopHitAt(NSArray *sections) {
    for (NSUInteger i = 0; i < sections.count; i++) {
        id sec = sections[i];
        for (NSString *ident in @[MSPCall(sec, "bundleIdentifier") ?: @"", MSPCall(sec, "identifier") ?: @""])
            if ([ident isKindOfClass:[NSString class]] && [ident caseInsensitiveCompare:@"com.apple.spotlight.tophits"] == NSOrderedSame) return i;
    }
    return NSNotFound;
}
// Where our sections go among Apple's (1.7.0, KT): the Actions before Apple's results when the typed text names one of them (lead:
// MacSpotlightMatch.h MSPNamesOne -- "activ" shows Activity Monitor at the top, not below Apple's results and "Show More Results") -- after
// Apple's Top Hit when it has one (topAt: MSPTopHitAt; the Top Hit keeps the first place, its highlight and the Return key, as before) --, else
// after Apple's results as before (an action found by an extra word only, "cpu", leaves a few letters of an app's name to Apple); then the
// Windows; Tweak Settings last (Apple's own settings stay above them, search-143). `apple`: the sections shown now, Apple's, with a Tweak Settings
// section made for an earlier pass at tweakAt (NSNotFound: none) -- it stays where it is and our Actions / Windows go before it, as made; `tweak`
// is a new one (only when none is kept). nil sections are left out.
static NSMutableArray *MSPPlaceOurs(NSArray *apple, NSUInteger tweakAt, NSUInteger topAt, id actions, BOOL lead, id windows, id tweak) {
    NSMutableArray *out = [NSMutableArray arrayWithArray:apple ?: @[]];
    NSMutableArray *after = [NSMutableArray array];
    if (actions && !lead) [after addObject:actions];
    if (windows) [after addObject:windows];
    NSUInteger at = tweakAt < out.count ? tweakAt : out.count;
    [out insertObjects:after atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(at, after.count)]];
    if (tweak && tweakAt == NSNotFound) [out addObject:tweak];
    if (actions && lead) [out insertObject:actions atIndex:topAt < at ? topAt + 1 : 0];   // (a Top Hit is one of Apple's, before ours and Tweak Settings)
    return out;
}
