// SidebarGroups.h -- Settings' sidebar decluttered (1.7.5 item 2, KT 31 Oct): Notifications and Sounds become one row, "Notifications & Sounds",
// Focus and Screen Time another, "Focus & Screen Time", each opening a page of ours with Apple's two rows at its top (macsettings/SidebarGroups.x;
// iPadOS 15-17, whose sidebar is a PSListController). The pure parts, tested on the Mac (tools/test-sidebargroups.sh): which rows make a group,
// how a list of Settings' row identifiers is grouped, and how a link to one of Apple's grouped pages is sent through our row.
// The identifiers are the main list's on 15.6.1, 16.7.7 and 17.5.1 (MacSettings' "list ids" log): NOTIFICATIONS_ID Sounds DO_NOT_DISTURB
// SCREEN_TIME, in that order, in their own group. Links name them in any case (prefs:root=SOUNDS, prefs:root=Sounds): matched without case.
// Foundation only.
#pragma once
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import "MainListRows.h"   // (the list's rows read once, never the row Settings fills in on its own queue: 1.7.9)

typedef struct { const char *ident, *title, *apple[2]; } MSSGGroup;
static const MSSGGroup kMSSGGroups[] = {
    {"MAC_NOTIFICATIONS_SOUNDS", "Notifications & Sounds", {"NOTIFICATIONS_ID", "Sounds"}},
    {"MAC_FOCUS_SCREEN_TIME", "Focus & Screen Time", {"DO_NOT_DISTURB", "SCREEN_TIME"}},
};
#define MSSG_COUNT ((int)(sizeof(kMSSGGroups) / sizeof(kMSSGGroups[0])))

// The group an identifier of Apple's belongs to (its index; *member: 0 or 1), else -1.
static inline int MSSGGroupOfApple(NSString *ident, int *member) {
    if (![ident isKindOfClass:[NSString class]]) return -1;
    for (int g = 0; g < MSSG_COUNT; g++) for (int m = 0; m < 2; m++)
        if ([ident caseInsensitiveCompare:@(kMSSGGroups[g].apple[m])] == NSOrderedSame) { if (member) *member = m; return g; }
    return -1;
}
// Our row's group by its identifier, else -1.
static inline int MSSGGroupOfOurs(NSString *ident) {
    if (![ident isKindOfClass:[NSString class]]) return -1;
    for (int g = 0; g < MSSG_COUNT; g++) if ([ident isEqualToString:@(kMSSGGroups[g].ident)]) return g;
    return -1;
}

// How a list (its rows' identifiers, in order) is grouped: for each group whose two rows of Apple's are both there and whose row of ours is not,
// one step -- @{@"group": g, @"first": index of Apple's first row (our row takes its place), @"second": index of Apple's second row (it goes),
// @"adjacent": whether the second comes right after the first (one replace)}. A group with only one of its rows stays as Apple has it.
static inline NSArray<NSDictionary *> *MSSGPlan(NSArray *ids) {
    NSMutableArray *steps = [NSMutableArray array];
    for (int g = 0; g < MSSG_COUNT; g++) {
        NSInteger at[2] = {NSNotFound, NSNotFound}; BOOL ours = NO;
        for (NSUInteger i = 0; i < ids.count; i++) {
            id ident = ids[i];
            if (MSSGGroupOfOurs(ident) == g) ours = YES;
            int m = -1;
            if (MSSGGroupOfApple(ident, &m) == g && at[m] == NSNotFound) at[m] = (NSInteger)i;
        }
        if (ours || at[0] == NSNotFound || at[1] == NSNotFound) continue;
        NSInteger first = MIN(at[0], at[1]), second = MAX(at[0], at[1]);
        [steps addObject:@{@"group": @(g), @"first": @(first), @"second": @(second), @"adjacent": @(second == first + 1)}];
    }
    return steps;
}

// The plan applied to a list through the list's own calls (-replaceContiguousSpecifiers:withSpecifiers:animated:, -removeSpecifier:animated:: the
// sidebar, or a stand-in in the Mac test). Apple's calls change the list in place, so the rows are taken from a copy made before any change (an
// index of the plan would point one row further after the first group's two rows became one: 1.7.5 review, the second group then took
// Screen Time and General's group header), and each one is looked for in the live list again right before its call: both still there, and
// next to each other for the single replace (else a replace of the first and a remove of the second). A row no longer there, or a call that
// throws: that group stays as it is. makeRow(g, members) makes our row; done(g, members) hears of each group made. Returns how many were made.
// The rows' identifiers are read once, never the row Settings fills in on its own queue (common/MainListRows.h: 1.7.9, 17.5.1 crash).
static inline NSUInteger MSSGApplyPlan(id list, id (^makeRow)(int g, NSArray *members), void (^done)(int g, NSArray *members)) {
    SEL specsSel = NSSelectorFromString(@"specifiers"), replace = NSSelectorFromString(@"replaceContiguousSpecifiers:withSpecifiers:animated:"),
        remove = NSSelectorFromString(@"removeSpecifier:animated:");
    if (!list || ![list respondsToSelector:specsSel] || ![list respondsToSelector:replace] || ![list respondsToSelector:remove]) return 0;
    id live = ((id (*)(id, SEL))objc_msgSend)(list, specsSel);
    if (![live isKindOfClass:[NSArray class]]) return 0;
    NSArray *before = [(NSArray *)live copy];
    NSMutableArray *ids = [NSMutableArray array];
    for (id i in MSBDMLIdentifiers(list, before)) [ids addObject:[i isKindOfClass:[NSString class]] ? i : @""];
    NSUInteger made = 0;
    for (NSDictionary *st in MSSGPlan(ids)) {
        NSUInteger fi = [st[@"first"] unsignedIntegerValue], si = [st[@"second"] unsignedIntegerValue];
        if (fi >= before.count || si >= before.count) continue;
        int g = [st[@"group"] intValue];
        id a = before[fi], b = before[si];
        int ma = 0; MSSGGroupOfApple(ids[fi], &ma);
        NSArray *members = ma == 0 ? @[a, b] : @[b, a];
        id now = ((id (*)(id, SEL))objc_msgSend)(list, specsSel);
        NSUInteger ia = [now isKindOfClass:[NSArray class]] ? [(NSArray *)now indexOfObjectIdenticalTo:a] : NSNotFound;
        NSUInteger ib = [now isKindOfClass:[NSArray class]] ? [(NSArray *)now indexOfObjectIdenticalTo:b] : NSNotFound;
        if (ia == NSNotFound || ib == NSNotFound) continue;   // (gone meanwhile: left as it is)
        id row = makeRow ? makeRow(g, members) : nil;
        if (!row) continue;
        @try {
            if (ib == ia + 1) ((void (*)(id, SEL, id, id, BOOL))objc_msgSend)(list, replace, @[a, b], @[row], NO);
            else { ((void (*)(id, SEL, id, id, BOOL))objc_msgSend)(list, replace, @[a], @[row], NO); ((void (*)(id, SEL, id, BOOL))objc_msgSend)(list, remove, b, NO); }
        } @catch (NSException *e) { continue; }
        made++;
        if (done) done(g, members);
    }
    return made;
}

// A Settings link to one of Apple's pages that sits in a group of ours now, sent through our row: prefs:root=<Apple's row>[&path=P][&...][#R]
// -> prefs:root=<our row>&path=<Apple's row>[/P][&...][#R] (also App-prefs:, the form without "root=" -- prefs:SOUNDS --, and an encoded "#" as
// %23). Always written as prefs:, also for an App-prefs: link: Settings reads everything after "App-prefs:" as the root and hands on
// prefs:root=<that>&thirdPartyBundleID=<that> (15.6.1), so an App-prefs: link with root= in it ends nowhere (App-prefs:SOUNDS, which other apps
// use, did after our rewrite: 1.7.5 R1). Settings selects our row, our page opens
// Apple's page by its row and hands it the rest -- the path and the row to show, as Apple's own nested pages are linked. `grouped`: whether a
// group is in Settings' sidebar now (only those are rewritten). Anything else as it is.
static inline NSString *MSSGRewrite(NSString *link, BOOL (^grouped)(int group)) {
    if (![link isKindOfClass:[NSString class]]) return link;
    NSString *scheme = nil;
    for (NSString *s in @[@"prefs:", @"App-prefs:"]) if (link.length > s.length && [[link substringToIndex:s.length] caseInsensitiveCompare:s] == NSOrderedSame) { scheme = [link substringToIndex:s.length]; break; }
    if (!scheme) return link;
    NSString *rest = [link substringFromIndex:scheme.length];
    if (rest.length >= 5 && [[rest substringToIndex:5] caseInsensitiveCompare:@"root="] == NSOrderedSame) rest = [rest substringFromIndex:5];
    else if ([rest hasPrefix:@"/"] || [rest rangeOfString:@"="].location < [rest rangeOfString:@"&"].location) return link;   // (prefs:SOUNDS&path=X, App-prefs:SOUNDS: the root without "root=")
    // the row after "#" (or %23) stays at the end; the root is up to the first "&"
    NSString *frag = @"";
    NSRange h = [rest rangeOfString:@"#"];
    if (h.location == NSNotFound) h = [rest rangeOfString:@"%23"];
    if (h.location != NSNotFound) { frag = [rest substringFromIndex:h.location]; rest = [rest substringToIndex:h.location]; }
    NSRange amp = [rest rangeOfString:@"&"];
    NSString *root = amp.location == NSNotFound ? rest : [rest substringToIndex:amp.location];
    NSString *params = amp.location == NSNotFound ? @"" : [rest substringFromIndex:amp.location];   // ("&path=..&other=..")
    int member = -1, g = MSSGGroupOfApple(root.stringByRemovingPercentEncoding ?: root, &member);
    if (g < 0 || (grouped && !grouped(g))) return link;
    NSString *apple = @(kMSSGGroups[g].apple[member]);   // (Apple's own spelling: the row is found by it on our page)
    NSString *path = nil, *others = @"";
    for (NSString *p in [params componentsSeparatedByString:@"&"]) {
        if (!p.length) continue;
        if (!path && p.length >= 5 && [[p substringToIndex:5] caseInsensitiveCompare:@"path="] == NSOrderedSame) path = [p substringFromIndex:5];
        else others = [others stringByAppendingFormat:@"&%@", p];
    }
    NSString *newPath = path.length ? [NSString stringWithFormat:@"%@/%@", apple, path] : apple;
    return [NSString stringWithFormat:@"prefs:root=%s&path=%@%@%@", kMSSGGroups[g].ident, newPath, others, frag];   // (always prefs: with root=, above)
}
