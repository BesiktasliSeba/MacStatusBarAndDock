// test-tweakindex.m -- Mac test of common/TweakIndex.h (the tweak settings index behind the Settings search and Spotlight) against the made-up
// tweak folders of tools/make-tweakindex-fixture.py: which pages and rows it finds, their titles in the user's language, breadcrumbs, identifiers
// and Settings URLs, what it leaves out, the matching, and the content hash. test-tweakindex <fixture folder>.
#import <Foundation/Foundation.h>
#import "../common/TweakIndex.h"

static int gFail = 0, gN = 0;
static void Expect(BOOL ok, NSString *what) { gN++; if (!ok) { gFail++; printf("  FAIL %s\n", what.UTF8String); } }
static MTIConfig *Config(NSString *root, NSArray *langs) {
    MTIConfig *c = [MTIConfig new];
    c.plDirs = @[[root stringByAppendingPathComponent:@"PreferenceLoader/Preferences"]];
    c.bundleDirs = @[[root stringByAppendingPathComponent:@"PreferenceBundles"], [root stringByAppendingPathComponent:@"NoSuchDir"]];
    c.supportDir = [root stringByAppendingPathComponent:@"Application Support"];
    c.languages = langs; c.cfVersion = 1953.1; c.maxPerPane = 400; c.maxTotal = 6000;
    c.own = @[@{@"id": @"MAC_STATUS_BAR", @"title": @"Status Bar", @"bundle": [root stringByAppendingPathComponent:@"PreferenceBundles/MacStatusBarPrefs.bundle"]},
              @{@"id": @"MAC_DESKTOP", @"title": @"Desktop", @"bundle": [root stringByAppendingPathComponent:@"PreferenceBundles/MacStatusBarPrefs.bundle"], @"plist": @"Desktop", @"icon": @"desktop"},
              @{@"id": @"MAC_WINDOWS", @"title": @"Windows & Multitasking", @"bundle": [root stringByAppendingPathComponent:@"PreferenceBundles/MacStatusBarPrefs.bundle"], @"plist": @"Windows", @"icon": @"windows"},
              @{@"id": @"DOCK_MAGNIFICATION", @"title": @"Dock", @"bundle": [root stringByAppendingPathComponent:@"PreferenceBundles/NotInstalled.bundle"]}];
    c.skipBundles = @[@"MacStatusBarPrefs", @"DockMagnificationPrefs"];
    c.extras = @[@{@"id": @"SSH_TOGGLE", @"title": @"SSH"}, @{@"id": @"MAC_POINTER", @"title": @"Pointer", @"page": @YES}];
    return c;
}
static MTIEntry *Find(NSArray<MTIEntry *> *all, NSString *pane, NSString *title) {
    for (MTIEntry *e in all) if ([e.paneTitle isEqualToString:pane] && [e.title isEqualToString:title]) return e;
    return nil;
}
static NSArray<NSString *> *Titles(NSArray<MTIEntry *> *a) { NSMutableArray *t = [NSMutableArray array]; for (MTIEntry *e in a) [t addObject:e.title]; return t; }

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 2) { fprintf(stderr, "usage: test-tweakindex <fixture folder>\n"); return 2; }
        NSString *root = @(argv[1]);
        NSArray<MTIEntry *> *all = MTIBuild(Config(root, @[@"en-US"]));
        NSMutableOrderedSet *panes = [NSMutableOrderedSet orderedSet]; for (MTIEntry *e in all) [panes addObject:e.paneTitle];
        NSArray *wantPanes = @[@"Status Bar", @"Desktop", @"Windows & Multitasking", @"SSH", @"Pointer", @"Alpha", @"Delta", @"Epsilon", @"Eta", @"Gamma Tweak", @"Iota", @"Theta", @"Zeta"];
        Expect([panes.array isEqualToArray:wantPanes], [NSString stringWithFormat:@"pages in order: %@", [panes.array componentsJoinedByString:@", "]]);

        // our own page, read from its Root.plist; its PreferenceLoader entry (iPadOS 17) left out
        MTIEntry *e = Find(all, @"Status Bar", @"Show Seconds");
        Expect([e.uid isEqualToString:@"msbd-tweaksetting:root=MAC_STATUS_BAR#Show%20Seconds"] && !e.opensPage, [NSString stringWithFormat:@"own row uid %@", e.uid]);
        Expect([e.crumb isEqualToString:@"Status Bar"] && [e.keywords isEqualToArray:@[@"Clock"]] && e.depth == 2, @"own row crumb, group keyword, depth");
        Expect([MTIPrefsURL(e.uid) isEqualToString:@"prefs:root=MAC_STATUS_BAR#Show%20Seconds"] && [MTIPaneOf(e.uid) isEqualToString:@"MAC_STATUS_BAR"], @"own row Settings URL");
        Expect(Find(all, @"Status Bar", @"Status Bar").iconPath != nil, @"own page icon found");
        // the second page of the same bundle (1.6.0: Windows & Multitasking, Windows.plist): its own page, rows, Settings URL and icon
        e = Find(all, @"Windows & Multitasking", @"Mac Switcher");
        Expect([e.uid isEqualToString:@"msbd-tweaksetting:root=MAC_WINDOWS#Mac%20Switcher"] && [e.crumb isEqualToString:@"Windows & Multitasking"] && [e.keywords isEqualToArray:@[@"Multitasking"]], [NSString stringWithFormat:@"second own page row uid %@", e.uid]);
        Expect([MTIPrefsURL(e.uid) isEqualToString:@"prefs:root=MAC_WINDOWS#Mac%20Switcher"] && [MTIPaneOf(e.uid) isEqualToString:@"MAC_WINDOWS"], @"second own page Settings URL");
        Expect([Find(all, @"Windows & Multitasking", @"Windows & Multitasking").iconPath hasSuffix:@"windows@2x.png"], @"second own page icon found");
        Expect(Find(all, @"Status Bar", @"Mac Switcher") == nil, @"its rows not on the first page");
        // the third page of the same bundle (1.7.5: Desktop, Desktop.plist): its rows, a slider named by its group, its Settings URL and icon
        e = Find(all, @"Desktop", @"Show Desktop Icons");
        Expect([e.uid isEqualToString:@"msbd-tweaksetting:root=MAC_DESKTOP#Show%20Desktop%20Icons"] && [e.crumb isEqualToString:@"Desktop"], [NSString stringWithFormat:@"desktop page row uid %@", e.uid]);
        Expect([MTIPrefsURL(e.uid) isEqualToString:@"prefs:root=MAC_DESKTOP#Show%20Desktop%20Icons"] && [MTIPaneOf(e.uid) isEqualToString:@"MAC_DESKTOP"], @"desktop page Settings URL");
        e = Find(all, @"Desktop", @"Icon Size");
        Expect([MTIPrefsURL(e.uid) isEqualToString:@"prefs:root=MAC_DESKTOP#DESKTOP_ICON_SIZE"], [NSString stringWithFormat:@"the Icon Size slider, named by its group: %@", e.uid]);
        Expect([Find(all, @"Desktop", @"Desktop").iconPath hasSuffix:@"desktop@2x.png"], @"desktop page icon found");
        Expect(Find(all, @"Status Bar", @"Show Desktop Icons") == nil && Find(all, @"Windows & Multitasking", @"Show Desktop Icons") == nil, @"its rows on no other page");
        BOOL plOurs = NO; for (MTIEntry *x in all) if ([x.paneID isEqualToString:@"MSBD_PL_MacStatusBarPrefs"]) plOurs = YES;
        Expect(!plOurs, @"our page's PreferenceLoader entry left out");
        // our rows of the main list
        e = Find(all, @"SSH", @"SSH");
        Expect([e.uid isEqualToString:@"msbd-tweaksetting:root=ROOT%23SSH_TOGGLE"] && [MTIPrefsURL(e.uid) isEqualToString:@"prefs:root=ROOT%23SSH_TOGGLE"] && [e.category isEqualToString:@"msbd-tweaksetting:SSH_TOGGLE"], [NSString stringWithFormat:@"main-list switch uid %@", e.uid]);
        Expect([MTIPaneOf(e.uid) isEqualToString:@"ROOT#SSH_TOGGLE"], @"main-list switch page decoded");
        e = Find(all, @"Pointer", @"Pointer");
        Expect([e.uid isEqualToString:@"msbd-tweaksetting:root=MAC_POINTER"] && e.depth == 1, @"main-list page uid");

        // Alpha: localized (en), group keywords, slider named by its group, picker kept as a row, sub-page, duplicates, left-out rows
        NSArray *alpha = [all filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"paneTitle == 'Alpha'"]];
        NSArray *wantAlpha = @[@"Alpha", @"Enabled", @"Hide Labels & Dots", @"Speed", @"Style", @"Advanced Options", @"Turbo Mode", @"Number of Items", @"Enabled", @"Respring"];
        Expect([Titles(alpha) isEqualToArray:wantAlpha], [NSString stringWithFormat:@"Alpha rows: %@", [Titles(alpha) componentsJoinedByString:@" | "]]);
        e = alpha.firstObject;
        Expect(e.depth == 1 && [e.uid isEqualToString:@"msbd-tweaksetting:root=Alpha"] && [e.iconPath hasSuffix:@"icon@2x.png"] && !e.crumb, @"Alpha page entry (uid, icon, no crumb)");
        e = Find(all, @"Alpha", @"Hide Labels & Dots");
        Expect([e.uid isEqualToString:@"msbd-tweaksetting:root=Alpha#HIDE_LABELS"] && [e.keywords isEqualToArray:@[@"General"]], [NSString stringWithFormat:@"row id used: %@", e.uid]);
        e = Find(all, @"Alpha", @"Speed");
        Expect([e.uid hasSuffix:@"#speed"] && e.keywords.count == 0, [NSString stringWithFormat:@"slider by its group, key as id: %@", e.uid]);
        e = Find(all, @"Alpha", @"Turbo Mode");
        Expect([e.crumb isEqualToString:@"Alpha → Advanced Options"] && e.depth == 3 && [e.uid isEqualToString:@"msbd-tweaksetting:root=Alpha&path=Advanced%20Options#Turbo%20Mode"], [NSString stringWithFormat:@"sub-page row: %@ / %@", e.crumb, e.uid]);
        NSMutableArray *enabled = [NSMutableArray array]; for (MTIEntry *x in alpha) if ([x.title isEqualToString:@"Enabled"]) [enabled addObject:x.uid];
        Expect(enabled.count == 2 && [enabled[0] isEqualToString:@"msbd-tweaksetting:root=Alpha#ENABLED"] && [enabled[1] isEqualToString:@"msbd-tweaksetting:root=Alpha#ENABLED&msbdn=2"], [NSString stringWithFormat:@"duplicate rows: %@", enabled]);
        Expect([MTIPrefsURL(enabled.lastObject) isEqualToString:@"prefs:root=Alpha#ENABLED"], @"duplicate's Settings URL without the counter");
        e = Find(all, @"Alpha", @"Advanced Options");
        Expect(e.opensPage && [e.uid isEqualToString:@"msbd-tweaksetting:root=Alpha&path=Advanced%20Options"], [NSString stringWithFormat:@"a link row opens its page: %@", e.uid]);
        e = Find(all, @"Alpha", @"Style");
        Expect(!e.opensPage && [e.uid hasSuffix:@"#Style"], @"a picker is shown as its row");
        BOOL styleSub = NO; for (MTIEntry *x in alpha) if ([x.path.firstObject isEqualToString:@"Style"] && x.depth == 3) styleSub = YES;
        Expect(e && !styleSub, @"picker is a row, no page under it");
        // Turkish first: tr.lproj (UTF-16 strings)
        NSArray<MTIEntry *> *tr = MTIBuild(Config(root, @[@"tr-TR", @"en-US"]));
        Expect(Find(tr, @"Alpha", @"Etkin") != nil && [Find(tr, @"Alpha", @"Hide Labels & Dots").keywords isEqualToArray:@[@"Genel"]], @"Turkish strings (UTF-16 .strings) used first");
        // right-to-left language: Apple's other arrow
        NSArray<MTIEntry *> *ar = MTIBuild(Config(root, @[@"ar"]));
        Expect([Find(ar, @"Alpha", @"Turbo Mode").crumb isEqualToString:@"Alpha ← Advanced Options"], @"right-to-left breadcrumb arrow");

        // Gamma: entry id, bundle-named plist, sub-page from the controller's class name
        e = Find(all, @"Gamma Tweak", @"Deep Switch");
        Expect([e.uid isEqualToString:@"msbd-tweaksetting:root=GAMMA_ID&path=More#Deep%20Switch"] && [e.crumb isEqualToString:@"Gamma Tweak → More"], [NSString stringWithFormat:@"Gamma sub-page: %@", e.uid]);
        Expect(Find(all, @"Gamma Tweak", @"Use Gestures") != nil, @"Gamma page plist named after the bundle");
        // Delta: keys localized from Application Support, a key without a string made into words, sub-page from the class name
        Expect(Find(all, @"Delta", @"Global Configuration") != nil && Find(all, @"Delta", @"Disable Everywhere") != nil, @"Delta strings from Application Support");
        Expect(Find(all, @"Delta", @"Unknown Key Here") != nil, @"a key without a string becomes words");
        e = Find(all, @"Delta", @"Disable Everywhere");
        Expect([e.path isEqualToArray:@[@"GLOBAL_TWEAK_CONFIGURATION", @"DISABLE_EVERYWHERE"]] && [e.keywords isEqualToArray:@[@"Global"]], @"Delta sub-page path keeps the raw identifiers");
        // Epsilon: a page in the entry plist, localized from its own folder
        e = Find(all, @"Epsilon", @"Epsilon Switch");
        Expect(e && [e.keywords isEqualToArray:@[@"EPS GROUP"]] && [Find(all, @"Epsilon", @"Epsilon").iconPath hasSuffix:@"eps.png"], @"simple page in the entry plist");
        // Eta: the light plist; Zeta: no usual name -> page only; Theta: no plist -> page only
        Expect(Find(all, @"Eta", @"Light Row") && !Find(all, @"Eta", @"Dark Row"), @"light/dark pair: light");
        Expect(!Find(all, @"Zeta", @"Zeta One") && !Find(all, @"Zeta", @"Zeta Two") && Find(all, @"Zeta", @"Zeta"), @"ambiguous plists: page only");
        Expect(Find(all, @"Theta", @"Theta") != nil, @"code-only page: title only");
        // left out
        NSSet *gone = [NSSet setWithArray:@[@"Filtered", @"Missing", @"Switchy", @"Old Option", @"Follow me", @"Our other tweak", @"Alpha by someone"]];
        BOOL leak = NO; for (MTIEntry *x in all) if ([gone containsObject:x.title] || [gone containsObject:x.paneTitle]) leak = YES;
        Expect(!leak, @"filtered, missing, non-page entries, credits, link-outs and headers left out");

        // matching
        Expect([Titles(MTIMatch(all, @"seconds", 10)) isEqualToArray:@[@"Show Seconds"]], @"match a word start");
        Expect([Titles(MTIMatch(all, @"sec", 10)) isEqualToArray:@[@"Show Seconds"]], @"match a prefix");
        Expect(MTIMatch(all, @"conds", 10).count == 0, @"no match inside a word");
        Expect([Titles(MTIMatch(all, @"clock", 10)) isEqualToArray:@[@"Show Seconds"]], @"match the group title");
        Expect([Titles(MTIMatch(all, @"show sp", 10)) isEqualToArray:@[@"Show Spotlight Search"]], @"every word must match");
        NSArray *ga = Titles(MTIMatch(all, @"gamma", 10));
        Expect([ga isEqualToArray:@[@"Gamma Tweak"]], [NSString stringWithFormat:@"page name finds the page (not all its rows): %@", ga]);
        Expect([Titles(MTIMatch(tr, @"ETKİN", 10)) containsObject:@"Etkin"] || [Titles(MTIMatch(tr, @"etkin", 10)) containsObject:@"Etkin"], @"case-insensitive match");
        Expect(MTIMatch(all, @"s", 0).count > 3 && MTIMatch(all, @"s", 3).count == 3, @"limit");
        Expect([Titles(MTIMatch(all, @"labels dots", 10)) isEqualToArray:@[@"Hide Labels & Dots"]], @"punctuation ignored");

        // content hash: stable, and changes with a title
        Expect([MTIContentHash(all) isEqualToString:MTIContentHash(MTIBuild(Config(root, @[@"en-US"])))], @"hash stable");
        Expect(![MTIContentHash(all) isEqualToString:MTIContentHash(tr)], @"hash follows the titles");
        // as Apple's results controller hands them back (its URL carries "#" as "%23"), and main-list rows (Apple's "ROOT#<row>")
        Expect([MTIPaneOf(@"msbd-tweaksetting:root=MAC_STATUS_BAR%23Show%20Seconds") isEqualToString:@"MAC_STATUS_BAR"], @"page of an identifier with %23");
        Expect([MTIPaneOf(@"msbd-tweaksetting:root=Alpha&path=Advanced%20Options%23Turbo%20Mode") isEqualToString:@"Alpha"], @"page of a sub-page row");
        Expect([MTIPaneOf(@"msbd-tweaksetting:root=Hide%20%26%20Seek%23x") isEqualToString:@"Hide & Seek"], @"page name with an encoded &");
        Expect([MTIPaneOf(@"msbd-tweaksetting:root=ROOT%23SSH_TOGGLE") isEqualToString:@"ROOT#SSH_TOGGLE"], @"main-list row");
        Expect(MTISameUID(@"msbd-tweaksetting:root=MAC_STATUS_BAR#Show%20Seconds", @"msbd-tweaksetting:root=MAC_STATUS_BAR%23Show%20Seconds"), @"same row, encoded or not");
        Expect(!MTISameUID(@"msbd-tweaksetting:root=A#x", @"msbd-tweaksetting:root=A#y"), @"different rows");
        Expect([MTIPrefsURL(@"msbd-tweaksetting:root=MAC_STATUS_BAR%23Show%20Seconds&msbdn=3") isEqualToString:@"prefs:root=MAC_STATUS_BAR%23Show%20Seconds"], @"Settings URL keeps Apple's encoding, drops the counter");
        // identifiers of others pass untouched
        Expect(MTIPrefsURL(@"prefs:root=General") == nil && MTIPrefsURL(nil) == nil && MTIPrefsURL(@"msbd-tweaksetting:junk") == nil, @"other identifiers are not ours");
        // half an emoji in a tweak's own text (H-1): the half is left out, so every string has a UTF-8 form, and the hash works
        MTIEntry *ir = Find(all, @"Iota", @"Iota Raw "), *il = Find(all, @"Iota", @"Iota Strings ");
        Expect(ir != nil, [NSString stringWithFormat:@"lone surrogate in a binary plist label left out: %@", Titles(all)]);
        Expect(il != nil, @"lone surrogate in a UTF-16 .strings title left out");
        BOOL utf8 = YES;
        for (MTIEntry *x in all) for (NSString *t in @[x.uid ?: @"", x.title ?: @"", x.crumb ?: @"", x.paneTitle ?: @"", x.tokens ?: @"", [x.keywords componentsJoinedByString:@","]]) if (!t.UTF8String) utf8 = NO;
        Expect(utf8, @"every string of every row has a UTF-8 form");
        Expect(MTIContentHash(all).length == 24, @"hash of an index built from a tree with lone surrogates");
        MTIEntry *cut = [MTIEntry new]; cut.uid = @"msbd-tweaksetting:root=X"; cut.title = [NSString stringWithFormat:@"Cut %C", (unichar)0xD83D];
        Expect(cut.title.UTF8String == NULL && MTIContentHash(@[cut]).length == 24, @"hash of a row that still holds a lone surrogate (no crash)");
        Expect([MTIClean(cut.title) isEqualToString:@"Cut "] && [MTIClean([NSString stringWithFormat:@"%Cx", (unichar)0xDE00]) isEqualToString:@"x"], @"MTIClean leaves a lone high or low half out");
        Expect([MTIClean(@"A\U0001F600B") isEqualToString:@"A\U0001F600B"] && MTIClean(nil) == nil && [MTIClean(@"") isEqualToString:@""], @"MTIClean keeps whole emoji, nil and empty");

        // our rows made in code on a page (1.7.8: the Home Screen page's Swipe Past Last Page Opens App Library): that page, at the row, with its group
        MTIConfig *oc = Config(root, @[@"en-US"]);
        oc.ownRows = @[@{@"pane": @"HOME_SCREEN_DOCK", @"paneTitle": @"Home Screen & Multitasking", @"row": @"MSBD_LAST_PAGE_LIBRARY", @"title": @"Swipe Past Last Page Opens App Library", @"group": @"App Library"},
                       @{@"pane": @"HOME_SCREEN_DOCK", @"row": @"NO_TITLE"}];
        NSArray<MTIEntry *> *withRows = MTIBuild(oc);
        e = Find(withRows, @"Home Screen & Multitasking", @"Swipe Past Last Page Opens App Library");
        Expect([e.uid isEqualToString:@"msbd-tweaksetting:root=HOME_SCREEN_DOCK#MSBD_LAST_PAGE_LIBRARY"] && !e.opensPage && e.depth == 2, [NSString stringWithFormat:@"a code-made row: uid %@", e.uid]);
        Expect([MTIPrefsURL(e.uid) isEqualToString:@"prefs:root=HOME_SCREEN_DOCK#MSBD_LAST_PAGE_LIBRARY"] && [MTIPaneOf(e.uid) isEqualToString:@"HOME_SCREEN_DOCK"], @"  ... Apple's page by its identifier, at the row");
        Expect([e.crumb isEqualToString:@"Home Screen & Multitasking"] && [e.keywords isEqualToArray:@[@"App Library"]], @"  ... the page as its breadcrumb, its group as a keyword");
        Expect([MTIMatch(withRows, @"last page", 0) containsObject:e] && [MTIMatch(withRows, @"app library", 0) containsObject:e], @"  ... found by its words and its group's");
        Expect(withRows.count == all.count + 1, @"  ... one row: a row without a title is left out");
        // a row of ours on a page inside Apple's page (1.7.9: Sleep Guard on Battery > Battery Health), opened by our own link at its group
        MTIConfig *pc = Config(root, @[@"en-US"]);
        pc.ownRows = @[@{@"pane": @"BATTERY_USAGE", @"paneTitle": @"Battery", @"page": @"BATTERY_HEALTH", @"pageTitle": @"Battery Health", @"row": @"MSBD_SLEEP_GUARD",
                         @"title": @"Sleep Guard", @"group": @"Battery Use", @"link": @"BATTERY_HEALTH/MSBD_BATTERY_USE_GROUP"},
                       @{@"pane": @"BATTERY_USAGE", @"paneTitle": @"Battery", @"page": @"BATTERY_HEALTH", @"row": @"MSBD_NO_LINK", @"title": @"No Link Row"},
                       @{@"pane": @"BATTERY_USAGE", @"paneTitle": @"Battery", @"row": @"MSBD_TOP", @"title": @"Top Row", @"link": @"IGNORED"}];
        NSArray<MTIEntry *> *withPage = MTIBuild(pc);
        e = Find(withPage, @"Battery", @"Sleep Guard");
        Expect([e.uid isEqualToString:@"msbd-tweaksetting:root=BATTERY_USAGE&path=BATTERY_HEALTH/MSBD_BATTERY_USE_GROUP"] && e.depth == 3 && !e.opensPage,
               [NSString stringWithFormat:@"a row on a page inside Apple's page, with a link: the link's path (uid %@)", e.uid]);
        Expect([MTIPrefsURL(e.uid) isEqualToString:@"prefs:root=BATTERY_USAGE&path=BATTERY_HEALTH/MSBD_BATTERY_USE_GROUP"] && [MTIPaneOf(e.uid) isEqualToString:@"BATTERY_USAGE"],
               @"  ... Settings' own URL: the pane, then the page and the group (the battery menu's Sleep Guard link)");
        Expect([e.crumb isEqualToString:@"Battery → Battery Health"] && [e.keywords isEqualToArray:@[@"Battery Use"]] && [e.path isEqualToArray:@[@"BATTERY_HEALTH", @"MSBD_SLEEP_GUARD"]],
               [NSString stringWithFormat:@"  ... both pages as its breadcrumb (%@), its group as a keyword, the row last in its path", e.crumb]);
        Expect([MTIMatch(withPage, @"sleep", 0) containsObject:e] && [MTIMatch(withPage, @"sleep guard", 0) containsObject:e] && [MTIMatch(withPage, @"battery use", 0) containsObject:e]
               && ![MTIMatch(withPage, @"guards sleep", 0) containsObject:e], @"  ... found by its words and its group's");
        MTIEntry *e2 = Find(withPage, @"Battery", @"No Link Row"), *e3 = Find(withPage, @"Battery", @"Top Row");
        Expect([e2.uid isEqualToString:@"msbd-tweaksetting:root=BATTERY_USAGE&path=BATTERY_HEALTH#MSBD_NO_LINK"] && [e2.crumb isEqualToString:@"Battery → BATTERY_HEALTH"] && e2.depth == 3,
               [NSString stringWithFormat:@"  ... without a link: the page, at the row (uid %@, crumb %@)", e2.uid, e2.crumb]);
        Expect([e3.uid isEqualToString:@"msbd-tweaksetting:root=BATTERY_USAGE#MSBD_TOP"] && e3.depth == 2, @"  ... a link without a page inside: not taken (the row on the pane itself, as before)");
        Expect(MTIWithout(withPage, @"BATTERY_USAGE", @"MSBD_SLEEP_GUARD").count == withPage.count - 1 && withPage.count == all.count + 3, @"  ... left out by its row's identifier like any row");
        // 1.7.9 (KT): the Settings search lists our own pages and rows always, other tweaks' only with Include Tweak Settings -- each row says whose
        NSSet *ourPanes = [NSSet setWithArray:@[@"Status Bar", @"Desktop", @"Windows & Multitasking", @"SSH", @"Pointer"]];
        NSUInteger oursN = 0, wrong = 0;
        for (MTIEntry *x in all) { if (x.ours) oursN++; if (x.ours != [ourPanes containsObject:x.paneTitle]) wrong++; }
        Expect(oursN > 0 && oursN < all.count && !wrong, [NSString stringWithFormat:@"ours: every row of our pages and our main-list rows, no other tweak's (%lu of %lu, %lu wrong)", (unsigned long)oursN, (unsigned long)all.count, (unsigned long)wrong]);
        e = Find(withRows, @"Home Screen & Multitasking", @"Swipe Past Last Page Opens App Library");
        Expect(e.ours && Find(withPage, @"Battery", @"Sleep Guard").ours && Find(withPage, @"Battery", @"Top Row").ours, @"  ... and our rows made in code on Apple's pages (Swipe Past Last Page, Sleep Guard)");
        NSArray<MTIEntry *> *own = MTIListed(all, YES, NO), *others = MTIListed(all, NO, YES);
        BOOL ownOK = own.count == oursN, othersOK = others.count == all.count - oursN;
        for (MTIEntry *x in own) if (!x.ours) ownOK = NO;
        for (MTIEntry *x in others) if (x.ours) othersOK = NO;
        Expect(ownOK && [own.firstObject.title isEqualToString:@"Status Bar"], [NSString stringWithFormat:@"listed, Include Tweak Settings off: our rows alone (%lu)", (unsigned long)own.count]);
        Expect(othersOK && [others.firstObject.title isEqualToString:@"Alpha"], [NSString stringWithFormat:@"listed, ours left out by the guard: the other tweaks' rows alone (%lu)", (unsigned long)others.count]);
        Expect(MTIListed(all, YES, YES) == all && MTIListed(all, NO, NO).count == 0, @"listed: both, everything as it is; neither, nothing");
        Expect([MTIListed(MTIMatch(withPage, @"sleep guard", 0), YES, NO) containsObject:Find(withPage, @"Battery", @"Sleep Guard")]
               && [MTIListed(MTIMatch(all, @"show seconds", 0), YES, NO) containsObject:Find(all, @"Status Bar", @"Show Seconds")], @"  ... a search finds our rows with Include Tweak Settings off");
        Expect(MTIListed(MTIMatch(all, @"turbo", 0), YES, NO).count == 0 && [MTIListed(MTIMatch(all, @"turbo", 0), YES, YES) containsObject:Find(all, @"Alpha", @"Turbo Mode")],
               @"  ... and another tweak's row only with it on");
        // our own rows alone, as TweakSearch.x builds them with both switches off: no PreferenceLoader folder read, the same rows as in the full index
        MTIConfig *oc2 = Config(root, @[@"en-US"]); oc2.plDirs = @[];
        NSArray<MTIEntry *> *ownOnly = MTIBuild(oc2);
        BOOL sameRows = ownOnly.count == own.count;
        for (NSUInteger i = 0; sameRows && i < own.count; i++) if (![ownOnly[i].uid isEqualToString:own[i].uid] || !ownOnly[i].ours) sameRows = NO;
        Expect(sameRows, [NSString stringWithFormat:@"our rows built alone (no PreferenceLoader folder): the full index's own rows (%lu / %lu)", (unsigned long)ownOnly.count, (unsigned long)own.count]);
        // the loop guard's mark (TweakSearch.x): which kind of build a start ended in
        Expect(MTIGuardKind(nil) == 0 && MTIGuardKind(@NO) == 0 && MTIGuardKind(@0) == 0 && MTIGuardKind(@"1") == 0, @"guard mark: none (no mark, false, 0, not a number)");
        Expect(MTIGuardKind(@1) == 1 && MTIGuardKind(@2) == 2 && MTIGuardKind(@YES) == 2 && MTIGuardKind(@7) == 2,
               @"guard mark: 1 our own rows alone, 2 other tweaks' pages too; an older build's true and an unknown number count as 2");
        printf("test-tweakindex: %d/%d passed (%lu rows)\n", gN - gFail, gN, (unsigned long)all.count);
    }
    return gFail ? 1 : 0;
}
