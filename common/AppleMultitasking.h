// AppleMultitasking.h -- Apple's multitasking settings on our Windows & Multitasking page (1.6.0): the Settings side of AppleMultitaskingTable.h.
// Our page (statusbar/macstatusbarprefs MSBWindowsListController) shows each entry's rows, live and still Apple's (common/NativeEmbed.h); the row
// part that is always in Settings (statusbar/macstatusbarsettings/StatusBarSettingsRow.x) takes Apple's rows that lead there out of their page,
// sends links into them to our page, and passes an entry's own reloads on to our page. Both sides decide with the same two answers, so a setting
// is never in neither place:
//   MSAMWanted(rowListed) -- our page shows Apple's rows at all: it is in Settings' list, MacStatusBar&Dock runs (not an untested iPadOS or safe
//     mode), MacStatusBar is on and the Mac status bar is in use (otherwise the page shows only a note, or greyed rows);
//   MSAMEntryOK(i) -- that entry's page is there on this iPadOS build with every row it must have (made once to look, never shown).
// Includers import common/LineSwitch.h first (MSBDGateWanted, MSBDLineEnabled).
#pragma once
#import <dlfcn.h>
#import "NativeEmbed.h"
#import "General18Group.h"   // (MSBDG18Types: a method's types as expected)
#import "AppleMultitaskingTable.h"

static inline int MSAMOS(void) { return (int)[NSProcessInfo processInfo].operatingSystemVersion.majorVersion; }
// "Use Stock Status Bar" as stored (com.besiktasliseba.macstatusbar stockStatusBar; on: our page shows only its note).
static inline BOOL MSAMStockBar(void) {
    CFPreferencesAppSynchronize(CFSTR("com.besiktasliseba.macstatusbar"));
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("stockStatusBar"), CFSTR("com.besiktasliseba.macstatusbar"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    BOOL on = v && CFGetTypeID(v) == CFBooleanGetTypeID() && CFBooleanGetValue(v);
    if (v) CFRelease(v);
    return on;
}
// Our page shows its rows at all (otherwise it shows only a note, or greyed rows): MacStatusBar&Dock runs, MacStatusBar is on, the Mac status bar.
static inline BOOL MSAMPageLive(void) { return MSBDGateWanted() && MSBDLineEnabled(@"MacStatusBar") && !MSAMStockBar(); }
// ...and it is the place for Apple's rows, which are taken out of Apple's pages for it: it is in Settings' list too.
static inline BOOL MSAMWanted(BOOL rowListed) { return rowListed && MSAMSourcesFor(MSAMOS()).count && MSAMPageLive(); }
// The pages of Apple's made for our page carry this mark (StatusBarSettingsRow.x passes their own reloads on to the page that shows their rows).
static inline const void *MSAMEmbeddedKey(void) { return (const void *)sel_registerName("msbdAppleMultitasking"); }
static inline BOOL MSAMIsEntryPage(id page) { return page && objc_getAssociatedObject(page, MSAMEmbeddedKey()) != nil; }
// Entry i's rows made for `host` (nil: only to look at them), its page kept alive in `keep`; nil when the page is missing or lacks a row it must have.
static inline NSArray *MSAMEntryRows(int i, UIViewController *host, NSMutableArray *keep) {
    if (i < 0 || i >= MSAM_SOURCE_COUNT) return nil;
    const MSAMSource *s = &kMSAMSources[i];
    NSMutableArray *k = keep ?: [NSMutableArray array];
    NSUInteger before = k.count;
    NSArray *specs = MSNESpecifiers(host, @(s->page), s->bundle ? @[@(s->bundle)] : @[], s->title ? @(s->title) : nil, k, s->only ? MSAMList(s->only) : nil);
    if (k.count > before) objc_setAssociatedObject(k.lastObject, MSAMEmbeddedKey(), @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!specs.count) return nil;
    NSMutableSet *ids = [NSMutableSet set];
    for (id sp in specs) { id ident = [sp respondsToSelector:@selector(identifier)] ? [sp identifier] : nil; if ([ident isKindOfClass:[NSString class]]) [ids addObject:ident]; }
    for (NSString *e in MSAMList(s->expect)) if (![ids containsObject:e]) return nil;
    SEL cellType = NSSelectorFromString(@"cellType"), setName = NSSelectorFromString(@"setName:");
    id first = specs.firstObject;
    if (host && s->title && [first respondsToSelector:cellType] && ((long long (*)(id, SEL))objc_msgSend)(first, cellType) == 0 && [first respondsToSelector:setName]) {
        NSString *name = [first respondsToSelector:@selector(name)] ? [first name] : nil;   // (only where Apple's group has no header of its own)
        if (!name.length) ((void (*)(id, SEL, id))objc_msgSend)(first, setName, @(s->title));
    }
    return specs;
}
static inline BOOL MSAMEntryOK(int i) {   // (MSAMRows entries)
    static signed char verdict[MSAM_SOURCE_COUNT];   // (0 not looked at, 1 yes, 2 no: once per process)
    if (i < 0 || i >= MSAM_SOURCE_COUNT || kMSAMSources[i].kind != MSAMRows) return NO;
    if (!verdict[i]) verdict[i] = MSAMEntryRows(i, nil, nil).count ? 1 : 2;
    return verdict[i] == 1;
}
// The rows our page has from entry i (the identifiers of MSAMEntryRows, as made to look): for MSAMRedirect.
static inline NSArray<NSString *> *MSAMEntryRowIDs(int i) {
    NSMutableArray *out = [NSMutableArray array];
    for (id sp in MSAMEntryOK(i) ? MSAMEntryRows(i, nil, nil) : @[]) { id ident = [sp identifier]; if ([ident isKindOfClass:[NSString class]]) [out addObject:ident]; }
    return out;
}
// The rows to take out of Apple's page `list` now (nil: none): the rows leading to each entry our page shows.
static inline NSArray<NSString *> *MSAMHiddenOn(UIViewController *list, BOOL rowListed) {
    NSString *c = NSStringFromClass([list class]);
    NSMutableArray *out = nil;
    for (NSNumber *n in MSAMSourcesFor(MSAMOS())) {
        const MSAMSource *s = &kMSAMSources[n.intValue];
        if (s->kind != MSAMRows || !s->from || ![c isEqualToString:@(s->from)]) continue;   // (a link row takes nothing of Apple's)
        if (!out) { if (!MSAMWanted(rowListed)) return nil; out = [NSMutableArray array]; }
        if (MSAMEntryOK(n.intValue)) [out addObjectsFromArray:MSAMList(s->fromRows)];
    }
    return out.count ? out : nil;
}

// ---- link rows (MSAMLink, MSAMPage): a row of ours that opens Apple's page; Apple's row stays ----
// Apple's row of Settings' main list with that identifier (15-17; nil on 18 or where it is not there): StatusBarSettingsRow.x, which has the list.
static inline id MSAMMainListRow(NSString *ident) {
    id (*row)(NSString *) = (id (*)(NSString *))dlsym(RTLD_DEFAULT, "MSBDMainListRow");
    return row && ident.length ? row(ident) : nil;
}
// Settings' own URL handler, as its search results and Spotlight open a page (TweakSearchCheck.h MTSCheckOpening): there, with its types.
static inline BOOL MSAMURLHandlerOK(void) {
    Class app = objc_getClass("PreferencesAppController");
    return app && [app isSubclassOfClass:[UIApplication class]] && [[UIApplication sharedApplication] isKindOfClass:app]
        && (MSBDG18Types(app, NSSelectorFromString(@"processURL:animated:fromSearch:withCompletion:"), "v", @[@"@", @"B", @"B", @"@?"])   // (16.7.7: v40@0:8@16B24B28@?32)
            || MSBDG18Types(app, NSSelectorFromString(@"processURL:animated:fromSearch:withCompletion:"), "v", @[@"@", @"B", @"B", @"@"]));
}
// Entry i's way to Apple's page is there on this build (else no row): MSAMLink -- the URL handler and Apple's row in the main list that the link
// selects; MSAMPage -- Apple's page class, from its bundle, a view controller.
static inline BOOL MSAMRouteOK(int i) {
    if (i < 0 || i >= MSAM_SOURCE_COUNT) return NO;
#if DEBUG
    if (access("/tmp/msb-amroute-off", F_OK) == 0) return NO;   // (debug: as if the way to Apple's page were missing -- our page then has no such row)
#endif
    const MSAMSource *s = &kMSAMSources[i];
    if (s->kind == MSAMLink) return s->link && s->linkRow && MSAMURLHandlerOK() && MSAMMainListRow(@(s->linkRow)) != nil;
    if (s->kind == MSAMPage) { Class c = MSNEClass(@(s->page), s->bundle ? @[@(s->bundle)] : @[]); return c && [c isSubclassOfClass:[UIViewController class]]; }
    return NO;
}
// The row: Apple's title and icon where its main-list row has them (MSAMLink), else the table's title and no icon. MSAMLink rows carry the link
// (property msbdAppleLink: our page opens it when the row is picked, MSAMOpenLink); MSAMPage rows show Apple's page as their detail.
// 17.5's main list loads that row's icon lazily (useLazyIcons, iconUTTypeIdentifier "com.apple.graphic-icon.stage-manager"): until Settings has
// drawn Apple's row it has no iconImage, and our row then came without one -- and Settings greys out a link row with no page and no icon
// (cellEnabled 0, the tap did nothing: 17.5 RC check, 28 Oct). So the row takes Apple's lazy-icon keys too (its cell loads the same icon the
// way Settings' own cell does) and says it is enabled.
static inline id MSAMLinkRowSpecifier(int i, id target) {
    if (!MSAMRouteOK(i)) return nil;
    const MSAMSource *s = &kMSAMSources[i];
    Class specClass = objc_getClass("PSSpecifier");
    SEL make = NSSelectorFromString(@"preferenceSpecifierNamed:target:set:get:detail:cell:edit:");
    if (!specClass || ![specClass respondsToSelector:make]) return nil;
    NSString *title = s->title ? @(s->title) : nil;
    UIImage *icon = nil;
    NSMutableDictionary *lazyIcon = [NSMutableDictionary dictionary];
    if (s->kind == MSAMLink) {
        id row = MSAMMainListRow(@(s->linkRow));
        NSString *name = [row respondsToSelector:@selector(name)] ? [row name] : nil;
        id img = [row respondsToSelector:@selector(propertyForKey:)] ? [row propertyForKey:@"iconImage"] : nil;
        if ([name isKindOfClass:[NSString class]] && name.length) title = name;
        if ([img isKindOfClass:[UIImage class]]) icon = img;
        else if ([row respondsToSelector:@selector(propertyForKey:)])   // (not drawn yet: its lazy icon, as Settings' own cell loads it)
            for (NSString *k in @[@"useLazyIcons", @"iconUTTypeIdentifier", @"dontUnloadLazyIcon"]) { id v = [row propertyForKey:k]; if (v) lazyIcon[k] = v; }
    }
    Class detail = s->kind == MSAMPage ? MSNEClass(@(s->page), s->bundle ? @[@(s->bundle)] : @[]) : Nil;
    id spec = ((id (*)(id, SEL, id, id, SEL, SEL, Class, long long, Class))objc_msgSend)(specClass, make, title ?: @"", target, NULL, NULL, detail, 1, Nil);   // (1: PSLinkCell)
    if (!spec) return nil;
    MSNECall1(spec, @"setIdentifier:", [NSString stringWithFormat:@"MSAM_LINK_%d", i]);
    SEL setProp = NSSelectorFromString(@"setProperty:forKey:");
    if (icon) ((void (*)(id, SEL, id, id))objc_msgSend)(spec, setProp, icon, @"iconImage");
    for (NSString *k in lazyIcon) ((void (*)(id, SEL, id, id))objc_msgSend)(spec, setProp, lazyIcon[k], k);
    ((void (*)(id, SEL, id, id))objc_msgSend)(spec, setProp, @YES, @"enabled");   // (never greyed: see above)
    if (s->kind == MSAMLink) ((void (*)(id, SEL, id, id))objc_msgSend)(spec, setProp, @(s->link), @"msbdAppleLink");
    return spec;
}
// A link row picked: Apple's link through Settings' own URL handler, as a search result opens it.
static inline void MSAMOpenLink(NSString *link) {
    NSURL *url = [link isKindOfClass:[NSString class]] ? [NSURL URLWithString:link] : nil;
    if (!url || !MSAMURLHandlerOK()) return;
    ((void (*)(id, SEL, id, BOOL, BOOL, id))objc_msgSend)([UIApplication sharedApplication], NSSelectorFromString(@"processURL:animated:fromSearch:withCompletion:"), url, YES, NO, nil);
}
