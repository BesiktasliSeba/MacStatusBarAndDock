// MacSpotlightMove.h -- search-143's Settings items (S-3 #1, "Tweak Settings": CoreSpotlight items of Settings whose identifiers start with
// "msbd-tweaksetting:") taken out of Apple's sections and its Top Hit, for MacSpotlight.x to show after Apple's results. Plain Foundation and
// the ObjC runtime (Mac test tools/test-spotmove.sh, with stand-ins for Apple's section and result classes).
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
