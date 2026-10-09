// MacSpotlightMatch.h -- which of our rows the typed text matches, and in what order (MacSpotlight.x; plain Foundation, Mac test
// tools/test-spotmatch.sh). A row matches when every word typed starts one of its words (its title's, or its extra keywords': "lock" finds
// "Lock Screen", "desk 2" finds "Desktop 2", "new fi" finds "New Finder Window"), ignoring case, accents and width. One letter matches nothing:
// a row of ours shows only once the text says what it is (shown only when the typed text matches). Order: the title starting with the
// text first, then a title word starting with the first word, then the rest; ties keep SpringBoard's order (this desktop's windows first).
#pragma once
#import <Foundation/Foundation.h>

static NSString *MSPFold(NSString *s) {
    return [[s ?: @"" stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch locale:nil] lowercaseString];
}
static NSArray<NSString *> *MSPWords(NSString *folded) {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *w in [folded componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]]) if (w.length) [out addObject:w];
    return out;
}
// 0: no match; 3: the title starts with the text; 2: a word of the title starts with the first word typed; 1: the words match elsewhere.
static int MSPScore(NSString *query, NSString *title, NSString *keywords) {
    NSString *q = [MSPFold(query) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray<NSString *> *qw = MSPWords(q);
    if (q.length < 2 || !qw.count) return 0;
    NSString *t = MSPFold(title);
    NSArray<NSString *> *tw = MSPWords(t);
    NSArray<NSString *> *all = [tw arrayByAddingObjectsFromArray:MSPWords(MSPFold(keywords))];
    for (NSString *w in qw) {
        BOOL found = NO;
        for (NSString *c in all) if ([c hasPrefix:w]) { found = YES; break; }
        if (!found) return 0;
    }
    if ([t hasPrefix:q]) return 3;
    for (NSString *c in tw) if ([c hasPrefix:qw[0]]) return 2;
    return 1;
}
// The rows (dictionaries with "t" title, "k" keywords; "m" the words matched instead of the title, when the title names something the row is
// not found by -- "Force Quit Clock…" is found by "force quit", not by "clock") of one group that match, best first, at most `limit`; their
// places in `rows` come back.
static NSArray<NSNumber *> *MSPMatches(NSString *query, NSArray<NSDictionary *> *rows, NSString *group, NSUInteger limit) {
    NSMutableArray<NSArray *> *hits = [NSMutableArray array];   // @[score, place]
    for (NSUInteger i = 0; i < rows.count; i++) {
        NSDictionary *r = rows[i];
        if (![r isKindOfClass:[NSDictionary class]] || ![r[@"g"] isEqual:group] || ![r[@"t"] isKindOfClass:[NSString class]]) continue;
        int s = MSPScore(query, [r[@"m"] isKindOfClass:[NSString class]] ? r[@"m"] : r[@"t"], [r[@"k"] isKindOfClass:[NSString class]] ? r[@"k"] : nil);
        if (s > 0) [hits addObject:@[@(s), @(i)]];
    }
    [hits sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [b[0] compare:a[0]]; }];
    NSMutableArray<NSNumber *> *out = [NSMutableArray array];
    for (NSArray *h in hits) { if (out.count >= limit) break; [out addObject:h[1]]; }
    return out;
}
