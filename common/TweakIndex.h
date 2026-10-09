// TweakIndex.h -- the index of tweak settings behind the Settings search (macsettings/TweakSearch.x, "Include Tweak Settings") and Spotlight
// ("Tweak Settings", donated into Settings' own CoreSpotlight index). One indexer for both (MacStatusBar&Dock 1.4.3).
//
// What it reads, and only reads: PreferenceLoader's entry plists (the rows tweaks add to Settings) and the plists and .strings files inside the
// preference bundles they name, exactly the files PreferenceLoader and Settings read to show those pages. No bundle is ever loaded and no tweak
// code runs: a page whose rows are made in code shows up with its title only. Our own pages (Status Bar, Dock) are read the same way from their
// Root.plist. Each result is one row of a page, with Apple's own breadcrumb (the pages above it joined by " → "), the page's identifier and the
// row's identifier as Settings knows them (a specifier's identifier is its "id", else its plist label, else its key -- -[PSSpecifier identifier]).
//
// How a result is opened: its identifier becomes Settings' own URL, in Apple's own form ("prefs:root=<page>&path=<page inside it>#<row>", as
// Apple's results say "prefs:root=ACCESSIBILITY&path=DISPLAY_AND_TEXT#AUTO_BRIGHTNESS": the pages in "path", the row after "#"): Settings finds the
// page (PreferenceLoader names a page's row after its plist label; Shuffle's own URL rewrite finds pages it moved), opens the pages on the way and
// scrolls to the row, as for Apple's search results. A link row opens its page.
//
// Foundation and the ObjC runtime only (tools/test-tweakindex.m runs it on the Mac against made-up tweak folders); thread safe (no shared state
// except the immutable results).
#pragma once
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>

#define kMTIPrefix @"msbd-tweaksetting:"                               // every identifier of ours starts with this (Settings search, Spotlight)
#define kMTIDomain @"com.besiktasliseba.msbd.tweaksettings"           // the CoreSpotlight domain of the donated items
#define kMTIFormat 1                                                    // (part of the content hash: a change of the index's format re-donates)

@interface MTIEntry : NSObject
@property (nonatomic, copy) NSString *uid;            // kMTIPrefix + "root=<page>[&path=<page>[/<page>]][#<row>][&msbdn=<k>]"
@property (nonatomic, copy) NSString *paneID;         // the page's identifier in Settings' main list ("ROOT" for a row of the main list itself)
@property (nonatomic, copy) NSString *category;       // kMTIPrefix + page identifier: one results section per page
@property (nonatomic, copy) NSString *title;          // what the row says
@property (nonatomic, copy) NSString *crumb;          // Apple's breadcrumb: the pages above the row ("Atria → General"), nil for a page itself
@property (nonatomic, copy) NSArray<NSString *> *keywords;   // the row's group title
@property (nonatomic, copy) NSArray<NSString *> *path;       // identifiers below the page (pages it passes through, then the row itself)
@property (nonatomic) BOOL opensPage;                  // the row is a link to a page of its own: a result opens that page (else: shown and highlighted)
@property (nonatomic) NSInteger depth;                 // 1 a page, 2 a row of it, 3 a row of a page inside it
@property (nonatomic, copy) NSString *iconPath;       // the page's icon file, or nil
@property (nonatomic, copy) NSString *paneTitle;      // the page's title
@property (nonatomic, copy) NSString *tokens;         // " token token ... " folded (case, accents, width), for the matching
@end
@implementation MTIEntry
@end

// ---- configuration ----------------------------------------------------------------------------------------------------------------------------
// plDirs: PreferenceLoader's folders of entry plists; bundleDirs: where "bundle" names are looked up (in this order, as libprefs does);
// supportDir: Application Support (some tweaks keep their strings in a bundle there, e.g. Choicy); own: our pages [{id, title, bundle, plist,
// icon}]; extras: rows of Settings' main list that are ours [{id, title, icon}] (switches: opened as Apple's main-list rows, "ROOT#<id>");
// languages: the user's languages, in order ([NSLocale preferredLanguages]); cfVersion: kCFCoreFoundationVersionNumber (pl_filter).
@interface MTIConfig : NSObject
@property (nonatomic, copy) NSArray<NSString *> *plDirs, *bundleDirs, *languages;
@property (nonatomic, copy) NSString *supportDir;
@property (nonatomic, copy) NSArray<NSDictionary *> *own, *extras;
@property (nonatomic, copy) NSArray<NSString *> *skipBundles;   // bundles (names) whose PreferenceLoader entries are left out (our own pages: indexed as "own")
@property (nonatomic) double cfVersion;
@property (nonatomic) NSUInteger maxPerPane, maxTotal;
@end
@implementation MTIConfig
@end

// ---- small helpers ------------------------------------------------------------------------------------------------------------------------------
// A tweak's own text without lone UTF-16 surrogates (half of an emoji cut by its author: a binary plist or a UTF-16 .strings file can hold one).
// Such a string has no UTF-8 form: -UTF8String is NULL, percent-encoding gives nil, and CoreSpotlight cannot take it (1.4.3 external test H-1).
// Every plist and .strings value the index reads passes through MTIStr, so the index never holds one.
static NSString *MTIClean(NSString *s) {
    NSUInteger n = s.length;
    if (!n) return s;
    unichar small[256], *buf = n <= 256 ? small : (unichar *)malloc(n * sizeof(unichar));
    if (!buf) return @"";
    [s getCharacters:buf range:NSMakeRange(0, n)];
    NSUInteger w = 0;
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = buf[i];
        if (CFStringIsSurrogateHighCharacter(c) && i + 1 < n && CFStringIsSurrogateLowCharacter(buf[i + 1])) { buf[w++] = c; buf[w++] = buf[++i]; continue; }
        if (CFStringIsSurrogateHighCharacter(c) || CFStringIsSurrogateLowCharacter(c)) continue;   // (a lone half: left out)
        buf[w++] = c;
    }
    NSString *out = w == n ? s : [NSString stringWithCharacters:buf length:w];
    if (buf != small) free(buf);
    return out;
}
static NSString *MTIStr(id v) { return [v isKindOfClass:[NSString class]] && [(NSString *)v length] ? MTIClean(v) : nil; }
// RFC 3986 unreserved characters stay, everything else is percent-encoded (so "&", "=", "/", "#" and spaces inside a label never split the URL;
// Settings decodes them back, as it does for its own identifiers).
static NSString *MTIEnc(NSString *s) {
    static NSCharacterSet *ok;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ ok = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"]; });
    return [s stringByAddingPercentEncodingWithAllowedCharacters:ok] ?: @"";
}
static NSString *MTIFold(NSString *s) {
    if (!s.length) return @"";
    return [[s stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch locale:nil] lowercaseString];
}
// The words of a text, folded; with camel case words split as well ("AppHider" -> apphider app hider).
static void MTIAddTokens(NSString *text, NSMutableOrderedSet *into) {
    if (!text.length) return;
    NSCharacterSet *sep = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
    for (NSString *w in [text componentsSeparatedByCharactersInSet:sep]) {
        if (!w.length) continue;
        [into addObject:MTIFold(w)];
        NSMutableArray *parts = [NSMutableArray array];
        NSUInteger start = 0;
        for (NSUInteger i = 1; i < w.length; i++) {
            unichar p = [w characterAtIndex:i - 1], c = [w characterAtIndex:i];
            BOOL up = [[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:c], lowBefore = [[NSCharacterSet lowercaseLetterCharacterSet] characterIsMember:p];
            if (up && lowBefore) { [parts addObject:[w substringWithRange:NSMakeRange(start, i - start)]]; start = i; }
        }
        if (parts.count) {
            [parts addObject:[w substringFromIndex:start]];
            for (NSString *p in parts) if (p.length) [into addObject:MTIFold(p)];
        }
    }
}
static NSString *MTITokens(NSString *title, NSArray<NSString *> *keywords) {
    NSMutableOrderedSet *t = [NSMutableOrderedSet orderedSet];
    MTIAddTokens(title, t);
    for (NSString *k in keywords) MTIAddTokens(k, t);
    return t.count ? [NSString stringWithFormat:@" %@ ", [t.array componentsJoinedByString:@" "]] : @"";
}
static NSDictionary *MTIPlist(NSString *path) {
    NSDictionary *d = nil;
    @try { d = [NSDictionary dictionaryWithContentsOfFile:path]; } @catch (NSException *e) { d = nil; }
    return [d isKindOfClass:[NSDictionary class]] ? d : nil;
}
static BOOL MTIIsDir(NSString *p) { BOOL d = NO; return p.length && [[NSFileManager defaultManager] fileExistsAtPath:p isDirectory:&d] && d; }

// PreferenceLoader's filter (pl_filter / filter): CoreFoundationVersion [min] or [min, max]; the Classes test is left to Settings (a class
// that is not there makes PreferenceLoader drop the row; here the row is kept and its page is not found when opened -- nothing breaks).
static BOOL MTIFilterPasses(id f, double cf) {
    if (![f isKindOfClass:[NSDictionary class]]) return YES;
    id v = ((NSDictionary *)f)[@"CoreFoundationVersion"];
    if (![v isKindOfClass:[NSArray class]] || ![(NSArray *)v count]) return YES;
    NSArray *a = v;
    if ([a[0] respondsToSelector:@selector(doubleValue)] && cf < [a[0] doubleValue]) return NO;
    if (a.count > 1 && [a[1] respondsToSelector:@selector(doubleValue)] && cf >= [a[1] doubleValue]) return NO;
    return YES;
}

// ---- localization (the bundle's own .strings files, read directly: no NSBundle cache, the same in Settings and on the Mac) ----------------------
@interface MTIStrings : NSObject
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *cache;   // "bundle|table" -> NSDictionary or NSNull
@property (nonatomic, copy) NSArray<NSString *> *languages;
@property (nonatomic, copy) NSString *supportDir;
@end
@implementation MTIStrings
- (NSArray<NSString *> *)lprojsIn:(NSString *)bundle {   // the bundle's localizations, best first (the user's languages), then English/Base
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:bundle error:nil] ?: @[])
        if ([f.pathExtension isEqualToString:@"lproj"]) [names addObject:f.stringByDeletingPathExtension];
    NSMutableArray *order = [NSMutableArray array];
    if (names.count) for (NSString *l in [NSBundle preferredLocalizationsFromArray:names forPreferences:self.languages ?: @[@"en"]]) if (![order containsObject:l]) [order addObject:l];
    for (NSString *l in @[@"en", @"English", @"Base", @"en_US", @"en-US"]) if ([names containsObject:l] && ![order containsObject:l]) [order addObject:l];
    return order;
}
- (NSArray<NSDictionary *> *)tables:(NSString *)table inBundle:(NSString *)bundle {
    if (!bundle.length || !table.length) return @[];
    NSString *k = [NSString stringWithFormat:@"%@|%@", bundle, table];
    id hit = self.cache[k];
    if (hit) return hit == [NSNull null] ? @[] : hit;
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *l in [self lprojsIn:bundle]) {
        NSDictionary *d = MTIPlist([[bundle stringByAppendingPathComponent:[l stringByAppendingPathExtension:@"lproj"]] stringByAppendingPathComponent:[table stringByAppendingPathExtension:@"strings"]]);
        if (d.count) [out addObject:d];
    }
    NSDictionary *flat = MTIPlist([bundle stringByAppendingPathComponent:[table stringByAppendingPathExtension:@"strings"]]);   // (an unlocalized table)
    if (flat.count) [out addObject:flat];
    self.cache[k] = out.count ? out : (id)[NSNull null];
    return out;
}
- (NSString *)lookup:(NSString *)key bundle:(NSString *)bundle table:(NSString *)table {
    for (NSDictionary *d in [self tables:table inBundle:bundle]) { NSString *v = MTIStr(d[key]); if (v) return v; }
    return nil;
}
// A label as Settings shows it: the plist's table, then Localizable, then (a page whose strings live elsewhere) the same-named bundle in
// Application Support; a key never found becomes words ("GLOBAL_TWEAK_CONFIGURATION" -> "Global Tweak Configuration").
- (NSString *)localize:(NSString *)raw bundle:(NSString *)bundle table:(NSString *)table supportName:(NSString *)supportName {
    if (!raw.length) return nil;
    NSString *v = [self lookup:raw bundle:bundle table:table] ?: [self lookup:raw bundle:bundle table:@"Localizable"];
    if (!v && supportName.length && self.supportDir.length) {
        NSString *sb = [self.supportDir stringByAppendingPathComponent:[supportName stringByAppendingPathExtension:@"bundle"]];
        if (MTIIsDir(sb)) v = [self lookup:raw bundle:sb table:@"Localizable"] ?: [self lookup:raw bundle:sb table:table];
    }
    if (v.length) return v;
    static NSRegularExpression *keyLike;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ keyLike = [NSRegularExpression regularExpressionWithPattern:@"^[A-Z][A-Z0-9]*(_[A-Z0-9]+)+$" options:0 error:nil]; });
    if ([keyLike numberOfMatchesInString:raw options:0 range:NSMakeRange(0, raw.length)]) {
        NSMutableArray *w = [NSMutableArray array];
        for (NSString *p in [raw componentsSeparatedByString:@"_"]) if (p.length) [w addObject:[[p substringToIndex:1] stringByAppendingString:[[p substringFromIndex:1] lowercaseString]]];
        return [w componentsJoinedByString:@" "];
    }
    return raw;
}
@end

// ---- the walk ---------------------------------------------------------------------------------------------------------------------------------
@interface MTIBuilder : NSObject
@property (nonatomic, strong) MTIConfig *cfg;
@property (nonatomic, strong) MTIStrings *strings;
@property (nonatomic, strong) NSMutableArray<MTIEntry *> *out;
@property (nonatomic, strong) NSMutableSet<NSString *> *panes, *uids;
@property (nonatomic, copy) NSString *arrow;   // " → ", or " ← " for a right-to-left language (as Apple's breadcrumbs)
@end

static NSString *MTISupportName(NSString *bundleName) {   // "ChoicyPrefs" -> "Choicy"
    for (NSString *suffix in @[@"Preferences", @"Preference", @"PrefBundle", @"Settings", @"Prefs", @"Pref"])
        if (bundleName.length > suffix.length && [bundleName.lowercaseString hasSuffix:suffix.lowercaseString]) return [bundleName substringToIndex:bundleName.length - suffix.length];
    return bundleName;
}
// Plists inside a bundle that hold a page (an "items" array), by name without .plist.
static NSDictionary<NSString *, NSDictionary *> *MTIPagePlists(NSString *bundle) {
    NSMutableDictionary *m = [NSMutableDictionary dictionary];
    for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:bundle error:nil] ?: @[]) {
        if (![f.pathExtension isEqualToString:@"plist"] || [f isEqualToString:@"Info.plist"]) continue;
        NSDictionary *d = MTIPlist([bundle stringByAppendingPathComponent:f]);
        if ([d[@"items"] isKindOfClass:[NSArray class]] && [(NSArray *)d[@"items"] count]) m[f.stringByDeletingPathExtension] = d;
    }
    return m;
}
// Which plist a page's own controller loads (its code decides; only the usual names are trusted): Root, the bundle's name, the entry's name, the
// only one there, Prefs / Preferences / Settings / Main, a light/dark pair's light one. Anything else: the page with its title only.
static NSString *MTIMainPlist(NSDictionary<NSString *, NSDictionary *> *pages, NSString *bundleName, NSString *entryName) {
    if (pages[@"Root"]) return @"Root";
    if (bundleName && pages[bundleName]) return bundleName;
    if (entryName && pages[entryName]) return entryName;
    if (pages.count == 1) return pages.allKeys.firstObject;
    for (NSString *n in @[@"Prefs", @"Preferences", @"Settings", @"Main"]) if (pages[n]) return n;
    for (NSString *n in pages) if ([n hasSuffix:@"-Light"] && pages[[[n substringToIndex:n.length - 6] stringByAppendingString:@"-Dark"]]) return n;
    return nil;
}
static NSString *MTICamelFromKey(NSString *raw) {   // "GLOBAL_TWEAK_CONFIGURATION" -> "GlobalTweakConfiguration"
    if (![raw containsString:@"_"] || ![raw isEqualToString:raw.uppercaseString]) return nil;
    NSMutableString *s = [NSMutableString string];
    for (NSString *p in [raw componentsSeparatedByString:@"_"]) if (p.length) [s appendFormat:@"%@%@", [p substringToIndex:1], [[p substringFromIndex:1] lowercaseString]];
    return s;
}
static NSString *MTIAlnum(NSString *s) {
    NSMutableString *o = [NSMutableString string];
    NSCharacterSet *an = [NSCharacterSet alphanumericCharacterSet];
    for (NSUInteger i = 0; i < s.length; i++) { unichar c = [s characterAtIndex:i]; if ([an characterIsMember:c]) [o appendFormat:@"%C", c]; }
    return o;
}
// The plist a link row opens, when its controller loads one of this bundle's plists in a recognisable way: a row property naming the plist
// ("child": "General"), the controller's class name containing it (CHPGlobalTweakConfigurationController -> GlobalTweakConfiguration), its label
// written without spaces ("App Settings" -> AppSettings) or a SNAKE_CASE key as words (GLOBAL_TWEAK_CONFIGURATION -> GlobalTweakConfiguration).
static NSString *MTISubPlist(NSDictionary *item, NSString *title, NSArray<NSString *> *free) {
    static NSSet *notNames;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ notNames = [NSSet setWithArray:@[@"cell", @"label", @"id", @"key", @"defaults", @"PostNotification", @"detail", @"icon", @"cellClass", @"action", @"url", @"subtitle", @"footerText", @"default", @"bundle", @"isController", @"systemIcon", @"cellSubtitleText", @"systemTintColor"]]; });
    NSString *(^named)(NSString *) = ^NSString *(NSString *want) {
        if (!want.length) return nil;
        for (NSString *n in free) if ([n caseInsensitiveCompare:want] == NSOrderedSame) return n;
        return nil;
    };
    for (NSString *k in item) {
        if ([notNames containsObject:k]) continue;
        NSString *hit = named(MTIStr(item[k]));
        if (hit) return hit;
    }
    NSString *detail = MTIStr(item[@"detail"]);
    if (detail) {
        NSString *best = nil;
        for (NSString *n in free) if (n.length >= 4 && [detail rangeOfString:n options:NSCaseInsensitiveSearch].location != NSNotFound && n.length > best.length) best = n;
        if (best) return best;
    }
    NSString *raw = MTIStr(item[@"label"]);
    return named(MTIAlnum(raw ?: @"")) ?: named(MTICamelFromKey(raw)) ?: named(MTIAlnum(title ?: @""));
}

// A label written for a value ("Number of bars: %i"): the words without the placeholder.
static NSString *MTICleanTitle(NSString *t) {
    if (![t containsString:@"%"]) return t;
    static NSRegularExpression *fmt;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ fmt = [NSRegularExpression regularExpressionWithPattern:@"%[-+ #0]*[0-9]*(\\.[0-9]+)?(hh|h|ll|l|q|L|z|j|t)?[@diouxXeEfgGcsSp]" options:0 error:nil]; });
    NSString *o = [fmt stringByReplacingMatchesInString:t options:0 range:NSMakeRange(0, t.length) withTemplate:@""];
    while ([o containsString:@"  "]) o = [o stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    o = [o stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    while ([o hasSuffix:@":"] || [o hasSuffix:@"="]) o = [[o substringToIndex:o.length - 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    return o;
}

@implementation MTIBuilder
- (BOOL)full { return self.out.count >= (self.cfg.maxTotal ?: 6000); }
- (NSString *)uidForPane:(NSString *)pane path:(NSArray<NSString *> *)path rootRow:(BOOL)rootRow opensPage:(BOOL)opensPage {
    NSMutableString *u = [NSMutableString stringWithString:kMTIPrefix];
    if (rootRow) [u appendFormat:@"root=ROOT%%23%@", MTIEnc(path.firstObject ?: @"")];   // (a row of the main list: Apple's "ROOT#<row>")
    else {
        [u appendFormat:@"root=%@", MTIEnc(pane)];
        NSArray *pages = opensPage ? path : (path.count ? [path subarrayWithRange:NSMakeRange(0, path.count - 1)] : @[]);
        if (pages.count) {
            NSMutableArray *enc = [NSMutableArray array];
            for (NSString *p in pages) [enc addObject:MTIEnc(p)];
            [u appendFormat:@"&path=%@", [enc componentsJoinedByString:@"/"]];
        }
        if (!opensPage && path.count) [u appendFormat:@"#%@", MTIEnc(path.lastObject)];
    }
    NSString *base = [u copy];
    for (NSUInteger n = 2; [self.uids containsObject:u]; n++) u = [NSMutableString stringWithFormat:@"%@&msbdn=%lu", base, (unsigned long)n];   // (two rows with one identifier: the first is the one Settings finds)
    [self.uids addObject:u];
    return u;
}
- (void)addPane:(NSString *)pane title:(NSString *)title icon:(NSString *)icon {
    MTIEntry *e = [MTIEntry new];
    e.paneID = pane; e.paneTitle = title; e.title = title; e.depth = 1; e.path = @[]; e.keywords = @[]; e.iconPath = icon;
    e.category = [kMTIPrefix stringByAppendingString:pane];
    e.uid = [self uidForPane:pane path:@[] rootRow:NO opensPage:YES];
    e.tokens = MTITokens(title, nil);
    [self.out addObject:e];
}
// The rows of one page (plist items), and of the pages its link rows open inside the same bundle (two levels at most).
- (void)walkItems:(NSArray *)items pane:(NSString *)pane paneTitle:(NSString *)paneTitle icon:(NSString *)icon bundle:(NSString *)bundle
            table:(NSString *)table support:(NSString *)support crumbs:(NSArray<NSString *> *)crumbs path:(NSArray<NSString *> *)path
            pages:(NSDictionary<NSString *, NSDictionary *> *)pages free:(NSMutableArray<NSString *> *)free depth:(NSInteger)depth count:(NSUInteger *)count {
    static NSRegularExpression *social, *noise;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        social = [NSRegularExpression regularExpressionWithPattern:@"twitter|mastodon|reddit|discord|telegram|paypal|donat|patreon|ko-?fi|sponsor|github|sourcecode|source_code|sourcelink|email|mail|addrepo|repository|\\brepo\\b|follow|website|payment|credit|youtube|instagram|support" options:NSRegularExpressionCaseInsensitive error:nil];
        noise = [NSRegularExpression regularExpressionWithPattern:@"header|banner|logo|twitter|credit|spacer|footer|donat|avatar|social" options:NSRegularExpressionCaseInsensitive error:nil];
    });
    BOOL (^hits)(NSRegularExpression *, NSString *) = ^BOOL(NSRegularExpression *re, NSString *s) { return s.length && [re numberOfMatchesInString:s options:0 range:NSMakeRange(0, s.length)] > 0; };
    NSString *group = nil;
    NSUInteger max = self.cfg.maxPerPane ?: 400;
    for (id raw in items) {
        if (*count >= max || [self full]) return;
        if (![raw isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *it = raw;
        if (!MTIFilterPasses(it[@"pl_filter"], self.cfg.cfVersion)) continue;
        NSString *cell = MTIStr(it[@"cell"]) ?: @"";
        NSString *rawLabel = MTIStr(it[@"label"]);
        if ([cell isEqualToString:@"PSGroupCell"]) { group = [self.strings localize:rawLabel bundle:bundle table:table supportName:support]; continue; }
        if (it[@"url"] || it[@"user"] || hits(noise, MTIStr(it[@"cellClass"]))) continue;                      // (links out, credits, headers: not settings)
        if ([@[@"PSStaticTextCell", @"PSSpinnerCell", @"PSTitleValueCell", @"PSTitleCell", @"PSGiantIconCell", @"PSGiantCell"] containsObject:cell]) continue;
        if ([cell isEqualToString:@"PSButtonCell"] && (hits(social, MTIStr(it[@"action"])) || hits(social, rawLabel))) continue;
        if ([it[@"isStaticText"] boolValue]) continue;
        NSString *title = MTICleanTitle([self.strings localize:rawLabel bundle:bundle table:table supportName:support]);
        BOOL valueCell = [cell isEqualToString:@"PSSliderCell"] || [cell isEqualToString:@"PSSegmentCell"] || it[@"min"] != nil;
        if (!title.length && valueCell) title = group;                                                       // (a slider is named by its group)
        if (!title.length || title.length > 80) continue;
        NSString *rowID = MTIStr(it[@"id"]) ?: rawLabel ?: MTIStr(it[@"key"]) ?: title;
        NSMutableArray *kw = [NSMutableArray array];
        if (group.length && ![group isEqualToString:title]) [kw addObject:group];
        MTIEntry *e = [MTIEntry new];
        e.paneID = pane; e.paneTitle = paneTitle; e.title = title; e.depth = depth; e.iconPath = icon;
        e.path = [path arrayByAddingObject:rowID];
        e.crumb = [crumbs componentsJoinedByString:self.arrow];
        e.keywords = kw;
        // a link row (a page of its own: the result opens it); a picker -- Apple's list of values -- is shown as the row it is; a PSLinkListCell
        // with its own controller and no values is a link
        NSString *detail = MTIStr(it[@"detail"]);
        BOOL picker = it[@"validValues"] || it[@"validTitles"] || it[@"values"] || it[@"titles"] || [detail hasSuffix:@"ListItemsController"] || ([cell isEqualToString:@"PSLinkListCell"] && !detail);
        BOOL link = !picker && !it[@"bundle"] && ([cell isEqualToString:@"PSLinkCell"] || [cell isEqualToString:@"PSLinkListCell"] || (!cell.length && detail));
        e.opensPage = link;
        e.category = [kMTIPrefix stringByAppendingString:pane];
        e.uid = [self uidForPane:pane path:e.path rootRow:NO opensPage:link];
        e.tokens = MTITokens(title, kw);
        [self.out addObject:e];
        (*count)++;
        // the page a link row opens, when it is one of this bundle's plists (found as MTISubPlist says): its rows too
        if (depth < 3 && pages.count && link) {
            NSString *sub = MTISubPlist(it, title, free);
            NSArray *subItems = sub ? pages[sub][@"items"] : nil;
            if (subItems) {
                [free removeObject:sub];
                NSString *subTable = MTIStr(pages[sub][@"stringsTable"]) ?: MTIStr(pages[sub][@"localizationTable"]) ?: sub;
                [self walkItems:subItems pane:pane paneTitle:paneTitle icon:icon bundle:bundle table:subTable support:support crumbs:[crumbs arrayByAddingObject:title]
                           path:e.path pages:pages free:free depth:depth + 1 count:count];
            }
        }
    }
}
// One page: its row in Settings' main list, then the rows of its plist.
- (void)addPage:(NSString *)pane title:(NSString *)title icon:(NSString *)icon bundle:(NSString *)bundle items:(NSArray *)items table:(NSString *)table
        support:(NSString *)support pages:(NSDictionary *)pages mainName:(NSString *)mainName {
    if (!pane.length || !title.length || [self.panes containsObject:pane] || [self full]) return;   // (the same identifier twice: Settings finds the first)
    [self.panes addObject:pane];
    [self addPane:pane title:title icon:icon];
    if (![items isKindOfClass:[NSArray class]]) return;
    NSMutableArray *free = [NSMutableArray arrayWithArray:pages.allKeys ?: @[]];
    if (mainName) [free removeObject:mainName];
    [free removeObject:@"entry"];
    NSUInteger count = 0;
    [self walkItems:items pane:pane paneTitle:title icon:icon bundle:bundle table:table support:support crumbs:@[title] path:@[] pages:pages free:free depth:2 count:&count];
}
// An icon file in a folder: the name as given, then with .png and the @2x / @3x versions (the largest found).
static NSString *MTIIcon(NSString *dir, NSString *name) {
    if (!dir.length || !name.length) return nil;
    NSString *base = [name.pathExtension isEqualToString:@"png"] ? name.stringByDeletingPathExtension : name;
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *n in @[[base stringByAppendingString:@"@3x.png"], [base stringByAppendingString:@"@2x.png"], [base stringByAppendingString:@".png"], name]) {
        NSString *p = [dir stringByAppendingPathComponent:n];
        if ([fm fileExistsAtPath:p]) return p;
    }
    return nil;
}
- (void)addEntryPlist:(NSString *)full relative:(NSString *)rel {
    NSDictionary *plist = MTIPlist(full);
    NSDictionary *entry = [plist[@"entry"] isKindOfClass:[NSDictionary class]] ? plist[@"entry"] : nil;
    if (!entry) return;
    if (!MTIFilterPasses(plist[@"filter"] ?: plist[@"pl_filter"], self.cfg.cfVersion) || !MTIFilterPasses(entry[@"pl_filter"], self.cfg.cfVersion)) return;
    NSString *cell = MTIStr(entry[@"cell"]) ?: @"PSLinkCell";
    if (![cell isEqualToString:@"PSLinkCell"] && ![cell isEqualToString:@"PSLinkListCell"]) return;    // (a page link; a switch put straight into the list is not a page)
    NSString *name = rel.lastPathComponent.stringByDeletingPathExtension;                                // (PreferenceLoader's "title": the strings table of the entry)
    NSString *entryDir = full.stringByDeletingLastPathComponent;
    NSString *bundleName = MTIStr(entry[@"bundle"]), *bundle = nil;
    if (bundleName && [self.cfg.skipBundles containsObject:bundleName]) return;
    if (bundleName) {
        NSString *given = MTIStr(entry[@"bundlePath"]);
        if (MTIIsDir(given)) bundle = given;
        for (NSString *d in self.cfg.bundleDirs) {
            if (bundle) break;
            NSString *p = [d stringByAppendingPathComponent:[bundleName stringByAppendingPathExtension:@"bundle"]];
            if (MTIIsDir(p)) bundle = p;
        }
        if (!bundle) return;                                                                              // (PreferenceLoader drops it too)
    }
    NSString *locBundle = bundle ?: entryDir, *support = bundleName ? MTISupportName(bundleName) : nil;
    NSString *rawLabel = MTIStr(entry[@"label"]);
    NSString *title = [self.strings localize:rawLabel bundle:locBundle table:name supportName:support] ?: name;
    NSString *pane = MTIStr(entry[@"id"]) ?: rawLabel ?: MTIStr(entry[@"key"]) ?: title;
    NSString *icon = MTIIcon(locBundle, MTIStr(entry[@"icon"]));
    if (!bundle) {   // a page made of this plist alone (its "items"), localized from its own folder
        [self addPage:pane title:title icon:icon bundle:entryDir items:plist[@"items"] table:name support:nil pages:nil mainName:nil];
        return;
    }
    if (![entry[@"isController"] boolValue]) { [self addPage:pane title:title icon:icon bundle:bundle items:nil table:nil support:nil pages:nil mainName:nil]; return; }
    NSDictionary *pages = MTIPagePlists(bundle);
    NSString *main = MTIMainPlist(pages, bundleName, name);
    NSString *table = main ? (MTIStr(pages[main][@"stringsTable"]) ?: MTIStr(pages[main][@"localizationTable"]) ?: main) : nil;
    [self addPage:pane title:title icon:icon bundle:bundle items:main ? pages[main][@"items"] : nil table:table support:support pages:pages mainName:main];
}
@end

// Builds the whole index (a few hundred files; run it off the main thread). Never throws.
static NSArray<MTIEntry *> *MTIBuild(MTIConfig *cfg) {
    MTIBuilder *b = [MTIBuilder new];
    b.cfg = cfg; b.out = [NSMutableArray array]; b.panes = [NSMutableSet set]; b.uids = [NSMutableSet set];
    b.strings = [MTIStrings new]; b.strings.cache = [NSMutableDictionary dictionary]; b.strings.languages = cfg.languages; b.strings.supportDir = cfg.supportDir;
    NSString *lang = cfg.languages.firstObject;
    BOOL rtl = lang && [NSLocale characterDirectionForLanguage:lang] == NSLocaleLanguageDirectionRightToLeft;
    b.arrow = rtl ? @" ← " : @" → ";
    @try {
        for (NSDictionary *o in cfg.own) {   // our pages first (their rows are Settings rows Apple's index lacks)
            NSString *bundle = MTIStr(o[@"bundle"]), *plistName = MTIStr(o[@"plist"]) ?: @"Root";
            if (!MTIIsDir(bundle)) continue;
            NSDictionary *pages = MTIPagePlists(bundle);
            [b addPage:MTIStr(o[@"id"]) title:MTIStr(o[@"title"]) icon:MTIIcon(bundle, MTIStr(o[@"icon"]) ?: @"icon") bundle:bundle items:pages[plistName][@"items"]
                 table:plistName support:nil pages:pages mainName:plistName];
        }
        for (NSDictionary *x in cfg.extras) {   // our rows of the main list itself (a page: opened as a page; a switch: as Apple's main-list rows)
            NSString *rid = MTIStr(x[@"id"]), *title = MTIStr(x[@"title"]);
            if (!rid || !title || [b.panes containsObject:rid]) continue;
            [b.panes addObject:rid];
            if ([x[@"page"] boolValue]) { [b addPane:rid title:title icon:MTIStr(x[@"icon"])]; continue; }
            MTIEntry *e = [MTIEntry new];
            e.paneID = @"ROOT"; e.paneTitle = title; e.title = title; e.depth = 1; e.path = @[rid]; e.keywords = @[]; e.iconPath = MTIStr(x[@"icon"]);
            e.category = [kMTIPrefix stringByAppendingString:rid];
            e.uid = [b uidForPane:@"ROOT" path:@[rid] rootRow:YES opensPage:NO];
            e.tokens = MTITokens(title, nil);
            [b.out addObject:e];
        }
        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSString *dir in cfg.plDirs) {
            NSArray *subs = [[fm subpathsOfDirectoryAtPath:dir error:nil] sortedArrayUsingSelector:@selector(compare:)];
            NSUInteger seen = 0;
            for (NSString *rel in subs) {
                if (![rel.pathExtension isEqualToString:@"plist"] || ++seen > 2000 || [b full]) continue;
                @autoreleasepool { [b addEntryPlist:[dir stringByAppendingPathComponent:rel] relative:rel]; }
            }
        }
    } @catch (NSException *e) {}
    for (MTIEntry *e in b.out) {   // (a last check over what a row carries: nothing without a UTF-8 form leaves the index, whichever way it came in)
        e.title = MTIClean(e.title); e.crumb = MTIClean(e.crumb); e.paneTitle = MTIClean(e.paneTitle); e.uid = MTIClean(e.uid); e.tokens = MTIClean(e.tokens);
        NSMutableArray *kw = [NSMutableArray array]; for (NSString *k in e.keywords) [kw addObject:MTIClean(k)]; e.keywords = kw;
    }
    return [b.out copy];
}

// ---- matching (the Settings search): every word typed starts a word of the row's title or group --------------------------------------------
static NSArray<MTIEntry *> *MTIMatch(NSArray<MTIEntry *> *all, NSString *query, NSUInteger limit) {
    NSMutableArray *words = [NSMutableArray array];
    for (NSString *w in [MTIFold(query) componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]]) if (w.length) [words addObject:[@" " stringByAppendingString:w]];
    if (!words.count) return @[];
    NSMutableArray *hits = [NSMutableArray array];
    for (MTIEntry *e in all) {
        BOOL ok = YES;
        for (NSString *w in words) if ([e.tokens rangeOfString:w].location == NSNotFound) { ok = NO; break; }
        if (ok) [hits addObject:e];
    }
    [hits sortUsingComparator:^NSComparisonResult(MTIEntry *a, MTIEntry *b) {
        if (a.depth != b.depth) return a.depth < b.depth ? NSOrderedAscending : NSOrderedDescending;
        return [a.title localizedCaseInsensitiveCompare:b.title];
    }];
    if (limit && hits.count > limit) [hits removeObjectsInRange:NSMakeRange(limit, hits.count - limit)];
    return hits;
}

// ---- identifiers ------------------------------------------------------------------------------------------------------------------------------
// Settings' own URL for one of our identifiers ("msbd-tweaksetting:root=X&path=Y&msbdn=2" -> "prefs:root=X&path=Y"), nil for anything else.
static NSString *MTIPrefsURL(NSString *uid) {
    if (![uid isKindOfClass:[NSString class]] || ![uid hasPrefix:kMTIPrefix]) return nil;
    NSString *rest = [uid substringFromIndex:kMTIPrefix.length];
    NSRange n = [rest rangeOfString:@"&msbdn="];
    if (n.location != NSNotFound) rest = [rest substringToIndex:n.location];
    if (![rest hasPrefix:@"root="]) return nil;
    return [@"prefs:" stringByAppendingString:rest];
}
// The page identifier inside one of our identifiers, or nil. Decoded first: a URL made from an identifier may carry its "#" as "%23" (Apple's results
// controller hands over "...MAC_STATUS_BAR%23Show%20Seconds"), and a main-list row keeps Apple's "ROOT#<row>".
static NSString *MTIPaneOf(NSString *uid) {
    NSString *u = MTIPrefsURL(uid);
    if (!u) return nil;
    NSString *root = [u substringFromIndex:@"prefs:root=".length];
    NSRange amp = [root rangeOfString:@"&"];   // (a literal "&" always ends the value: one inside a name is encoded, %26)
    if (amp.location != NSNotFound) root = [root substringToIndex:amp.location];
    root = root.stringByRemovingPercentEncoding ?: root;
    if ([root hasPrefix:@"ROOT#"]) return root;
    NSRange hash = [root rangeOfString:@"#"];
    return hash.location == NSNotFound ? root : [root substringToIndex:hash.location];
}
// Two identifiers of the same row (the same text once encoding is taken off).
static BOOL MTISameUID(NSString *a, NSString *b) {
    if (![a isKindOfClass:[NSString class]] || ![b isKindOfClass:[NSString class]]) return NO;
    return [a isEqualToString:b] || [(a.stringByRemovingPercentEncoding ?: a) isEqualToString:(b.stringByRemovingPercentEncoding ?: b)];
}
static void MTIHashLine(CC_SHA256_CTX *c, NSString *line) {   // (its bytes, never -UTF8String: NULL for a string without a UTF-8 form -- H-1)
    NSData *d = [line dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
    if (d.length) CC_SHA256_Update(c, d.bytes, (CC_LONG)d.length);
}
// One hash over everything a donation carries (a change -> donated again).
static NSString *MTIContentHash(NSArray<MTIEntry *> *all) {
    CC_SHA256_CTX c; CC_SHA256_Init(&c);
    MTIHashLine(&c, [NSString stringWithFormat:@"format %d\n", kMTIFormat]);
    for (MTIEntry *e in all)
        MTIHashLine(&c, [NSString stringWithFormat:@"%@\t%@\t%@\t%@\t%@\n", e.uid, e.title, e.crumb ?: @"", [e.keywords componentsJoinedByString:@","], e.iconPath ?: @""]);
    unsigned char d[CC_SHA256_DIGEST_LENGTH]; CC_SHA256_Final(d, &c);
    NSMutableString *h = [NSMutableString string];
    for (int i = 0; i < 12; i++) [h appendFormat:@"%02x", d[i]];
    return h;
}
