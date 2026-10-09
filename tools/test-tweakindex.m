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
        NSArray *wantPanes = @[@"Status Bar", @"SSH", @"Pointer", @"Alpha", @"Delta", @"Epsilon", @"Eta", @"Gamma Tweak", @"Iota", @"Theta", @"Zeta"];
        Expect([panes.array isEqualToArray:wantPanes], [NSString stringWithFormat:@"pages in order: %@", [panes.array componentsJoinedByString:@", "]]);

        // our own page, read from its Root.plist; its PreferenceLoader entry (iPadOS 17) left out
        MTIEntry *e = Find(all, @"Status Bar", @"Show Seconds");
        Expect([e.uid isEqualToString:@"msbd-tweaksetting:root=MAC_STATUS_BAR#Show%20Seconds"] && !e.opensPage, [NSString stringWithFormat:@"own row uid %@", e.uid]);
        Expect([e.crumb isEqualToString:@"Status Bar"] && [e.keywords isEqualToArray:@[@"Clock"]] && e.depth == 2, @"own row crumb, group keyword, depth");
        Expect([MTIPrefsURL(e.uid) isEqualToString:@"prefs:root=MAC_STATUS_BAR#Show%20Seconds"] && [MTIPaneOf(e.uid) isEqualToString:@"MAC_STATUS_BAR"], @"own row Settings URL");
        Expect(Find(all, @"Status Bar", @"Status Bar").iconPath != nil, @"own page icon found");
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

        printf("test-tweakindex: %d/%d passed (%lu rows)\n", gN - gFail, gN, (unsigned long)all.count);
    }
    return gFail ? 1 : 0;
}
