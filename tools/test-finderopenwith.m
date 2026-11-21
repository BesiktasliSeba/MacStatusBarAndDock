// Mac test of statusbar/FinderOpenWith.h (the code Finder.h runs, 1.8.8.1 B67): which apps Open With offers for a file -- an app's claim from its
// Info.plist's document types (its types against every type declared with the extension and their parents, or the extension itself; catch-alls and
// LSHandlerRank None claim nothing), the list's order (owners first, then by name, one row per app) -- and where the copy goes (the app's
// Documents/Inbox, else Finder's own folder). The Info.plists here are shaped as the real apps' are (TrollStore's .ipa / .tipa, a file manager's
// catch-all, Sileo's and Zebra's .deb, an older app's extension list). Run by test-finderopenwith.sh.
#import <Foundation/Foundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <stdio.h>
#include "../statusbar/FinderOpenWith.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

static NSDictionary *Docs(NSArray *entries) { return @{@"CFBundleDocumentTypes": entries}; }
static NSDictionary *Entry(NSArray *types, NSString *rank) { NSMutableDictionary *d = [@{@"CFBundleTypeName": @"T"} mutableCopy]; if (types) d[@"LSItemContentTypes"] = types; if (rank) d[@"LSHandlerRank"] = rank; return d; }

int main(void) { @autoreleasepool {
    // The types an .ipa has here: Apple's ipa type and, on the iPad 2, Filza's (its own declaration of the extension), with their parents.
    NSArray *ipaApple = @[@"com.apple.itunes.ipa", @"public.data", @"public.item"];
    NSArray *ipaBoth = @[@"com.tigisoftware.filza.ipa", @"public.data", @"public.item", @"com.apple.itunes.ipa", @"public.zip-archive", @"public.archive"];
    NSArray *ipaFilzaOnly = @[@"com.tigisoftware.filza.ipa", @"public.data", @"public.item"];
    NSArray *tipa = @[@"com.opa334.trollstore.tipa", @"public.data", @"public.item"];
    NSArray *deb = @[@"org.debian.deb-archive", @"public.archive", @"public.data", @"public.item"];
    NSArray *txt = @[@"public.plain-text", @"public.text", @"public.data", @"public.content", @"public.item"];

    NSDictionary *trollstore = Docs(@[Entry(@[@"com.apple.itunes.ipa", @"com.opa334.trollstore.tipa"], @"Owner")]);
    NSDictionary *trollNoRank = Docs(@[Entry(@[@"com.apple.itunes.ipa", @"com.opa334.trollstore.tipa"], nil)]);
    NSDictionary *fileManager = Docs(@[Entry(@[@"public.data", @"public.item", @"public.content"], @"Alternate")]);
    NSDictionary *sileo = Docs(@[Entry(@[@"org.debian.deb-archive"], @"Owner")]);
    NSDictionary *zebra = Docs(@[Entry(@[@"ORG.DEBIAN.DEB-ARCHIVE"], @"Alternate")]);
    NSDictionary *legacy = Docs(@[@{@"CFBundleTypeName": @"IPA", @"CFBundleTypeExtensions": @[@"IPA"]}]);
    NSDictionary *legacyStar = Docs(@[@{@"CFBundleTypeName": @"Any", @"CFBundleTypeExtensions": @[@"*"]}]);
    NSDictionary *saysNone = Docs(@[Entry(@[@"com.apple.itunes.ipa"], @"None")]);
    NSDictionary *mixed = Docs(@[Entry(@[@"com.apple.itunes.ipa"], @"Alternate"), Entry(@[@"com.apple.itunes.ipa"], @"Owner"), Entry(@[@"public.data"], @"Owner")]);

    // ---- an app's claim on a file
    CHECK(DMFinderOpenWithRank(trollstore, @"ipa", ipaApple) == 3, "TrollStore owns an .ipa (Apple's type)");
    CHECK(DMFinderOpenWithRank(trollstore, @"ipa", ipaBoth) == 3, "TrollStore owns an .ipa where Filza declares the extension too (the iPad 2): every type of the extension counts, not only the one \".ipa\" gives");
    CHECK(DMFinderOpenWithRank(trollstore, @"ipa", ipaFilzaOnly) == 0, "  ... but not a file whose types are none of its own (Filza's type alone, no Apple type declared)");
    CHECK(DMFinderOpenWithRank(trollstore, @"tipa", tipa) == 3, "TrollStore owns a .tipa (its own type)");
    CHECK(DMFinderOpenWithRank(trollNoRank, @"ipa", ipaApple) == 2, "no LSHandlerRank: Default (2)");
    CHECK(DMFinderOpenWithRank(trollstore, @"IPA", ipaApple) == 3, "the extension's case does not matter");
    CHECK(DMFinderOpenWithRank(trollstore, @"deb", deb) == 0, "TrollStore makes no claim on a .deb");
    CHECK(DMFinderOpenWithRank(fileManager, @"ipa", ipaBoth) == 0, "a file manager's catch-all (public.data / item / content) claims nothing: never offered for every file");
    CHECK(DMFinderOpenWithRank(fileManager, @"txt", txt) == 0, "  ... a text file either");
    CHECK(DMFinderOpenWithRank(sileo, @"deb", deb) == 3 && DMFinderOpenWithRank(zebra, @"deb", deb) == 1, "Sileo (Owner) and Zebra (Alternate, its type in capitals) claim a .deb: a type's case does not matter");
    CHECK(DMFinderOpenWithRank(sileo, @"ipa", ipaBoth) == 0, "Sileo makes no claim on an .ipa");
    CHECK(DMFinderOpenWithRank(legacy, @"ipa", @[]) == 2 && DMFinderOpenWithRank(legacy, @"ipa", ipaBoth) == 2, "an older app's extension list (CFBundleTypeExtensions IPA) claims an .ipa, case apart");
    CHECK(DMFinderOpenWithRank(legacy, @"zip", @[@"public.zip-archive"]) == 0, "  ... and nothing else");
    CHECK(DMFinderOpenWithRank(legacyStar, @"ipa", ipaBoth) == 0 && DMFinderOpenWithRank(legacyStar, @"*", @[]) == 0, "an extension list of \"*\" (any file) claims nothing, as a catch-all");
    CHECK(DMFinderOpenWithRank(saysNone, @"ipa", ipaApple) == 0, "LSHandlerRank None: the app does not open it");
    CHECK(DMFinderOpenWithRank(mixed, @"ipa", ipaApple) == 3, "several document types: the best claim wins (a catch-all Owner one apart)");
    CHECK(DMFinderOpenWithRank(mixed, @"txt", txt) == 0, "  ... and the catch-all Owner one claims no text file");
    CHECK(DMFinderOpenWithRank(nil, @"ipa", ipaApple) == 0 && DMFinderOpenWithRank((id)@"x", @"ipa", ipaApple) == 0 && DMFinderOpenWithRank(@{}, @"ipa", ipaApple) == 0, "no Info.plist, not a dictionary, no document types: 0");
    CHECK(DMFinderOpenWithRank(Docs((id)@[@"x", @3, @{@"LSItemContentTypes": @"com.apple.itunes.ipa"}, @{@"LSItemContentTypes": @[@4, @"com.apple.itunes.ipa"], @"LSHandlerRank": @7}]), @"ipa", (id)@[@5, @"com.apple.itunes.ipa"]) == 2,
          "entries of the wrong kind are passed over, a rank that is not a word reads as Default");
    CHECK(DMFinderOpenWithRank(trollstore, nil, nil) == 0 && DMFinderOpenWithRank(trollstore, (id)@5, (id)@"x") == 0, "no extension, no types: no claim, no crash");
    CHECK(DMFinderOpenWithCatchAll(@"PUBLIC.DATA") && DMFinderOpenWithCatchAll(@"public.item") && DMFinderOpenWithCatchAll(nil) && DMFinderOpenWithCatchAll(@"") && !DMFinderOpenWithCatchAll(@"public.zip-archive") && !DMFinderOpenWithCatchAll(@"public.text"),
          "the catch-alls: public.data, item, content (any case); a zip or text type is not one");
    // (this Mac's own types for real extensions, the way Finder.h asks the iPad's: every type of the extension and their parents)
    {
        NSMutableArray *pdf = [NSMutableArray array];
        for (UTType *t in [UTType typesWithTag:@"pdf" tagClass:UTTagClassFilenameExtension conformingToType:nil]) { [pdf addObject:t.identifier]; for (UTType *s in t.supertypes) [pdf addObject:s.identifier]; }
        CHECK([pdf containsObject:@"com.adobe.pdf"] && DMFinderOpenWithRank(Docs(@[Entry(@[@"com.adobe.pdf"], nil)]), @"pdf", pdf) == 2 && DMFinderOpenWithRank(fileManager, @"pdf", pdf) == 0,
              "this Mac's own types for .pdf: a PDF app claims it, the file manager not (%s)", [[pdf componentsJoinedByString:@","] UTF8String]);
    }

    // ---- the list
    NSArray *list = DMFinderOpenWithOrder(@[@{@"b": @"xyz.willy.Zebra", @"t": @"Zebra", @"r": @1}, @{@"b": @"org.coolstar.SileoStore", @"t": @"Sileo", @"r": @3},
                                            @{@"b": @"com.tigisoftware.Filza", @"t": @"Filza", @"r": @0}, @{@"b": @"com.example.a", @"t": @"Archiver", @"r": @2},
                                            @{@"b": @"org.coolstar.SileoStore", @"t": @"Sileo again", @"r": @3}, @{@"b": @"com.example.owner2", @"t": @"Another Owner", @"r": @9}]);
    NSArray *names = [list valueForKey:@"t"];
    CHECK(([names isEqualToArray:@[@"Another Owner", @"Sileo", @"Archiver", @"Zebra"]]), "the list: owners first by name, then the others by name, one row per app, no app without a claim (%s)", [[names componentsJoinedByString:@", "] UTF8String]);
    CHECK([list[0][@"r"] intValue] == 3, "  ... a rank above Owner reads as Owner");
    NSArray *odd = DMFinderOpenWithOrder((id)@[@"x", @{@"t": @"No id", @"r": @3}, @{@"b": @"", @"r": @3}, @{@"b": @"com.example.n", @"r": @2}, @{@"b": @"com.example.r", @"t": @"R", @"r": @"x"}]);
    CHECK(odd.count == 1 && [odd[0][@"t"] isEqualToString:@"com.example.n"], "rows without a bundle id or a rank are left out; one with no name shows its bundle id");
    CHECK(DMFinderOpenWithOrder(nil).count == 0 && DMFinderOpenWithOrder((id)@"x").count == 0, "nothing: an empty list");
    NSArray *same = DMFinderOpenWithOrder(@[@{@"b": @"b.two", @"t": @"Same", @"r": @2}, @{@"b": @"a.one", @"t": @"Same", @"r": @2}]);
    CHECK(([[same valueForKey:@"b"] isEqualToArray:@[@"a.one", @"b.two"]]), "two apps of one name: by bundle id, always the same order");

    // ---- where the copy goes
    NSString *fb = @"/var/mobile/tmp/msb-finder-openwith/com.opa334.TrollStore";
    CHECK([DMFinderOpenWithInbox(@"/var/mobile/Containers/Data/Application/AB-CD", fb) isEqualToString:@"/var/mobile/Containers/Data/Application/AB-CD/Documents/Inbox"], "the app's data container: its Documents/Inbox, as iOS's Open In");
    CHECK([DMFinderOpenWithInbox(@"/var/mobile/Containers/Data/Application/AB-CD/", fb) isEqualToString:@"/var/mobile/Containers/Data/Application/AB-CD/Documents/Inbox"], "  ... a trailing slash changes nothing");
    CHECK([DMFinderOpenWithInbox(@"/private/var/mobile/Containers/Data/Application/AB-CD", fb) hasSuffix:@"/Containers/Data/Application/AB-CD/Documents/Inbox"], "  ... spelt with /private too");
    CHECK([DMFinderOpenWithInbox(@"/var/mobile", fb) isEqualToString:fb] && [DMFinderOpenWithInbox(@"/private/var/mobile/", fb) isEqualToString:fb],
          "the user's home, which LaunchServices names for an app with no container of its own (the jailbreak's apps): Finder's own folder, never /var/mobile/Documents/Inbox");
    CHECK([DMFinderOpenWithInbox(@"/var/mobile/Containers/Data/Application", fb) isEqualToString:fb] && [DMFinderOpenWithInbox(@"/var/mobile/Containers/Data/Application/", fb) isEqualToString:fb]
          && [DMFinderOpenWithInbox(@"/var/mobile/Containers/Shared/AppGroup/AB-CD", fb) isEqualToString:fb] && [DMFinderOpenWithInbox(@"/var/mobile/Containers/Data/PluginKitPlugin/AB-CD", fb) isEqualToString:fb],
          "  ... nor the containers' folder itself, an app group's or an extension's container");
    CHECK([DMFinderOpenWithInbox(nil, fb) isEqualToString:fb] && [DMFinderOpenWithInbox(@"", fb) isEqualToString:fb] && [DMFinderOpenWithInbox(@"relative/x", fb) isEqualToString:fb] && [DMFinderOpenWithInbox(@"/", fb) isEqualToString:fb] && [DMFinderOpenWithInbox((id)@4, fb) isEqualToString:fb],
          "no data container (none, empty, relative, the root, not a string): Finder's own folder");

    printf("test-finderopenwith: %d passed, %d failed\n", passes, fails);
    return fails ? 1 : 0;
} }
