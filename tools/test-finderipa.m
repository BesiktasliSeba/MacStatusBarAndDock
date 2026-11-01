// Mac test of statusbar/FinderIPA.h (the code Finder.h runs, 1.7.7 item 7): an app shared from Finder goes as an .ipa -- its name ("<App name>
// <version>.ipa"), its types (its own, then a zip named .ipa), its layout (Payload/<Name>.app, staged as a clone and zipped by the same Foundation
// zip Finder uses for a folder: written to $IPA_OUT for test-finderipa.sh to list), and the FairPlay check (LC_ENCRYPTION_INFO(_64) cryptid) against
// small Mach-O files built here, thin and fat, and, when test-finderipa.sh hands one in ($IOS_EXE), an iOS executable made by the real linker.
// Run by test-finderipa.sh.
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <unistd.h>
#include "../statusbar/FinderIPA.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)
static NSFileManager *FM;
static NSString *Root;

// ---- Mach-O fixtures: a header, then load commands (an encryption command when cryptid >= 0) ----
static NSMutableData *Image(BOOL is64, int cryptid, BOOL swap) {
    NSMutableData *cmds = [NSMutableData data];
    struct uuid_command u = { LC_UUID, sizeof(struct uuid_command), {1, 2, 3} };   // (a command before it: the walk must step over it)
    [cmds appendBytes:&u length:sizeof u];
    if (cryptid >= 0) {
        if (is64) { struct encryption_info_command_64 e = { LC_ENCRYPTION_INFO_64, sizeof e, 0x4000, 0x8000, (uint32_t)cryptid, 0 }; [cmds appendBytes:&e length:sizeof e]; }
        else { struct encryption_info_command e = { LC_ENCRYPTION_INFO, sizeof e, 0x1000, 0x2000, (uint32_t)cryptid }; [cmds appendBytes:&e length:sizeof e]; }
    }
    struct load_command tail = { LC_SOURCE_VERSION, sizeof(struct source_version_command) };   // (and one after it)
    struct source_version_command sv = { tail.cmd, tail.cmdsize, 7 };
    [cmds appendBytes:&sv length:sizeof sv];
    uint32_t ncmds = cryptid >= 0 ? 3 : 2;
    NSMutableData *out = [NSMutableData data];
    if (is64) { struct mach_header_64 h = { MH_MAGIC_64, CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL, MH_EXECUTE, ncmds, (uint32_t)cmds.length, 0, 0 }; [out appendBytes:&h length:sizeof h]; }
    else { struct mach_header h = { MH_MAGIC, CPU_TYPE_ARM, CPU_SUBTYPE_ARM_V7, MH_EXECUTE, ncmds, (uint32_t)cmds.length, 0 }; [out appendBytes:&h length:sizeof h]; }
    [out appendData:cmds];
    [out increaseLengthBy:64];   // (some "code" after the commands)
    if (swap) {   // (the other byte order: every 32-bit field of the header and the commands turned around)
        uint32_t *w = out.mutableBytes; NSUInteger words = (out.length - 64) / 4;
        for (NSUInteger i = 0; i < words; i++) w[i] = OSSwapInt32(w[i]);
    }
    return out;
}
static NSData *Fat(NSArray<NSData *> *images, BOOL fat64) {
    NSMutableData *out = [NSMutableData data];
    struct fat_header fh = { OSSwapHostToBigInt32(fat64 ? FAT_MAGIC_64 : FAT_MAGIC), OSSwapHostToBigInt32((uint32_t)images.count) };
    [out appendBytes:&fh length:sizeof fh];
    uint64_t off = 0x4000;
    for (NSData *im in images) {
        if (fat64) { struct fat_arch_64 a = { (cpu_type_t)OSSwapHostToBigInt32(CPU_TYPE_ARM64), 0, OSSwapHostToBigInt64(off), OSSwapHostToBigInt64(im.length), OSSwapHostToBigInt32(14), 0 }; [out appendBytes:&a length:sizeof a]; }
        else { struct fat_arch a = { (cpu_type_t)OSSwapHostToBigInt32(CPU_TYPE_ARM64), 0, OSSwapHostToBigInt32((uint32_t)off), OSSwapHostToBigInt32((uint32_t)im.length), OSSwapHostToBigInt32(14) }; [out appendBytes:&a length:sizeof a]; }
        off += 0x4000;
    }
    off = 0x4000;
    for (NSData *im in images) { out.length = off; [out appendData:im]; off += 0x4000; }
    return out;
}
static NSString *Write(NSString *name, NSData *d) { NSString *p = [Root stringByAppendingPathComponent:name]; [d writeToFile:p atomically:NO]; return p; }
static int Enc(NSString *name, NSData *d) { return DMFinderMachOEncrypted(Write(name, d)); }
// (where the encryption command's cryptid is in a thin 64-bit image: for patching the linker's executable, walked here on its own)
static long CryptidOffset(NSData *d) {
    const struct mach_header_64 *h = d.bytes; if (d.length < sizeof *h || h->magic != MH_MAGIC_64) return -1;
    uint32_t at = sizeof *h;
    for (uint32_t i = 0; i < h->ncmds && at + 8 <= d.length; i++) {
        const struct load_command *lc = (const void *)((const uint8_t *)d.bytes + at);
        if (lc->cmd == LC_ENCRYPTION_INFO_64) return at + offsetof(struct encryption_info_command_64, cryptid);
        at += lc->cmdsize;
    }
    return -1;
}

int main(void) {
    @autoreleasepool {
        FM = [NSFileManager defaultManager];
        char tmpl[] = "/tmp/test-finderipa.XXXXXX";
        if (!mkdtemp(tmpl)) { printf("FAIL: no temp folder\n"); return 1; }
        Root = [NSString stringWithUTF8String:tmpl];

        // ---- the name ----
        CHECK([DMFinderIPAFileName(@"Tips", @"9.0") isEqualToString:@"Tips 9.0.ipa"], "name and version (Tips 9.0 on 16.7.7)");
        CHECK([DMFinderIPAFileName(@"Clock", nil) isEqualToString:@"Clock.ipa"] && [DMFinderIPAFileName(@"Clock", @"") isEqualToString:@"Clock.ipa"] && [DMFinderIPAFileName(@"Clock", @"  ") isEqualToString:@"Clock.ipa"],
              "no version: the name alone (Clock has none on 16.7.7)");
        CHECK([DMFinderIPAFileName(@"  Notes ", @" 2.10 ") isEqualToString:@"Notes 2.10.ipa"], "spaces around either trimmed: %s", DMFinderIPAFileName(@"  Notes ", @" 2.10 ").UTF8String);
        CHECK([DMFinderIPAFileName(@"AC/DC Live", @"1/2") isEqualToString:@"AC-DC Live 1-2.ipa"], "a \"/\" never makes a path: %s", DMFinderIPAFileName(@"AC/DC Live", @"1/2").UTF8String);
        CHECK([DMFinderIPAFileName(@".Hidden", @"1.0") isEqualToString:@"Hidden 1.0.ipa"] && [DMFinderIPAFileName(@"..", nil) isEqualToString:@"App.ipa"] && [DMFinderIPAFileName(@". .x", nil) isEqualToString:@"x.ipa"],
              "never a hidden file: %s %s", DMFinderIPAFileName(@".Hidden", @"1.0").UTF8String, DMFinderIPAFileName(@". .x", nil).UTF8String);
        CHECK([DMFinderIPAFileName(@"Line\nBreak\t", @"1") isEqualToString:@"Line Break 1.ipa"] && [DMFinderIPAFileName([NSString stringWithFormat:@"A%CB%C", (unichar)0x85, (unichar)0x7F], nil) isEqualToString:@"A B.ipa"], "control characters become spaces: %s", DMFinderIPAFileName(@"Line\nBreak\t", @"1").UTF8String);
        CHECK([DMFinderIPAFileName(@"می‌خواهم", @"1") isEqualToString:@"می‌خواهم 1.ipa"] && [DMFinderIPAFileName(@"👨‍👩‍👧 Family", nil) isEqualToString:@"👨‍👩‍👧 Family.ipa"],
              "a joiner stays (Persian's ZWNJ, an emoji family's ZWJ): they are format characters, not controls");
        CHECK([DMFinderIPAFileName(nil, @"1.0") isEqualToString:@"App 1.0.ipa"] && [DMFinderIPAFileName((NSString *)@123, (NSString *)@[]) isEqualToString:@"App.ipa"], "no name (or not a string): \"App\"");
        CHECK([DMFinderIPAFileName(@"Calendário", @"1.0") isEqualToString:@"Calendário 1.0.ipa"] && [DMFinderIPAFileName(@"Star Wars: KOTOR", @"1.0.5") isEqualToString:@"Star Wars: KOTOR 1.0.5.ipa"],
              "other characters as they are");
        {
            NSString *longName = [@"" stringByPaddingToLength:300 withString:@"é" startingAtIndex:0];
            NSString *n = DMFinderIPAFileName(longName, @"1.0");
            CHECK(strlen(n.UTF8String) <= 255 && [n hasSuffix:@" 1.0.ipa"] && [n hasPrefix:@"éé"], "a long name is shortened to a file name's 255 bytes, version and .ipa whole (%zu bytes)", strlen(n.UTF8String));
            NSMutableString *fam = [NSMutableString string]; for (int i = 0; i < 40; i++) [fam appendString:@"👨‍👩‍👧"];
            NSString *e = DMFinderIPAFileName(fam, @"2");
            NSString *body = [e substringToIndex:e.length - 6];
            __block BOOL whole = YES; [body enumerateSubstringsInRange:NSMakeRange(0, body.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *s, NSRange r, NSRange er, BOOL *stop) { if (![s isEqualToString:@"👨‍👩‍👧"]) whole = NO; }];
            CHECK(strlen(e.UTF8String) <= 255 && [e hasSuffix:@" 2.ipa"] && whole && e.UTF8String, "cut only at a character's end (a ZWJ family stays whole): %zu bytes", strlen(e.UTF8String));
            NSMutableString *acc = [NSMutableString string]; for (int i = 0; i < 200; i++) [acc appendString:@"é"];
            NSString *a = DMFinderIPAFileName(acc, nil);
            CHECK(strlen(a.UTF8String) <= 255 && [a hasSuffix:@"é.ipa"], "never between a letter and its accent (e + combining acute): %zu bytes", strlen(a.UTF8String));
            NSString *longVersion = [@"" stringByPaddingToLength:100 withString:@"9" startingAtIndex:0];
            CHECK([DMFinderIPAFileName(@"Odd", longVersion) isEqualToString:@"Odd.ipa"], "a version too long for a name is left out");
        }

        // ---- the staged name: a free one in the app's folder (two copies of an app make one .ipa name) ----
        {
            NSString *dir = [Root stringByAppendingPathComponent:@"staged"]; [FM createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
            NSString *(^at)(NSString *) = ^NSString *(NSString *n) { return [dir stringByAppendingPathComponent:n]; };
            NSString *(^put)(NSString *) = ^NSString *(NSString *n) { [[NSData data] writeToFile:at(n) atomically:NO]; return n; };
            CHECK([DMFinderStagedPath(dir, @"Tips 9.0.ipa") isEqualToString:at(@"Tips 9.0.ipa")], "a free name stays as it is");
            put(@"Tips 9.0.ipa");
            CHECK([DMFinderStagedPath(dir, @"Tips 9.0.ipa") isEqualToString:at(@"Tips 9.0 2.ipa")], "the name there: \"Tips 9.0 2.ipa\" (the version's dot stays, \" 2\" goes before .ipa): %s", DMFinderStagedPath(dir, @"Tips 9.0.ipa").lastPathComponent.UTF8String);
            put(@"Tips 9.0 2.ipa");
            CHECK([DMFinderStagedPath(dir, @"Tips 9.0.ipa") isEqualToString:at(@"Tips 9.0 3.ipa")], "  ... both there: \"Tips 9.0 3.ipa\"");
            symlink("/nonexistent/msbd-test", at(@"Tips 9.0 3.ipa").fileSystemRepresentation);
            CHECK([DMFinderStagedPath(dir, @"Tips 9.0.ipa") isEqualToString:at(@"Tips 9.0 4.ipa")], "  ... a dangling link of that name counts as there: \"Tips 9.0 4.ipa\"");
            put(@"Clock.ipa");
            CHECK([DMFinderStagedPath(dir, @"Clock.ipa") isEqualToString:at(@"Clock 2.ipa")], "an app without a version: \"Clock 2.ipa\"");
            put(@"Read Me");
            CHECK([DMFinderStagedPath(dir, @"Read Me") isEqualToString:at(@"Read Me 2")], "a file without an extension: \"Read Me 2\"");
            put(@"Fix.ipa"); for (int n = 2; n <= 99; n++) put([NSString stringWithFormat:@"Fix %d.ipa", n]);
            CHECK([DMFinderStagedPath(dir, @"Fix.ipa") isEqualToString:at(@"Fix 99.ipa")], "after \" 99\" the last one tried comes back (its copy then fails and says why): %s", DMFinderStagedPath(dir, @"Fix.ipa").lastPathComponent.UTF8String);
            [FM removeItemAtPath:at(@"Fix 50.ipa") error:nil];
            CHECK([DMFinderStagedPath(dir, @"Fix.ipa") isEqualToString:at(@"Fix 50.ipa")], "  ... and the first free one below it is found");
        }

        // ---- the app's name and version ----
        NSDictionary *clock = @{@"CFBundleIdentifier": @"com.apple.mobiletimer", @"CFBundleDisplayName": @"Clock", @"CFBundleVersion": @"1.0", @"CFBundleExecutable": @"MobileTimer"};
        NSDictionary *files = @{@"CFBundleIdentifier": @"com.apple.DocumentsApp", @"CFBundleName": @"Files", @"CFBundleShortVersionString": @"1.0"};
        CHECK([DMFinderIPAAppName(clock, @"/x/MobileTimer.app", @"Reloj") isEqualToString:@"Reloj"], "the name the iPad shows comes first (a Spanish iPad: Reloj)");
        CHECK([DMFinderIPAAppName(clock, @"/x/MobileTimer.app", nil) isEqualToString:@"Clock"] && [DMFinderIPAAppName(clock, @"/x/MobileTimer.app", @"  ") isEqualToString:@"Clock"],
              "then the display name: Clock, not MobileTimer");
        CHECK([DMFinderIPAAppName(files, @"/x/Files.app", nil) isEqualToString:@"Files"], "then the bundle name (Files has no display name on 16.7.7)");
        CHECK([DMFinderIPAAppName(@{@"CFBundleDisplayName": @" ", @"CFBundleName": @[]}, @"/x/Photo Booth.app", nil) isEqualToString:@"Photo Booth"] && [DMFinderIPAAppName(nil, @"/x/Fix.app", nil) isEqualToString:@"Fix"] &&
              [DMFinderIPAAppName((NSDictionary *)@"junk", @"/x/Fix.app", nil) isEqualToString:@"Fix"], "else the .app folder's own name (blank or odd values passed over)");
        CHECK([DMFinderIPAVersion(files) isEqualToString:@"1.0"] && DMFinderIPAVersion(clock) == nil && DMFinderIPAVersion(nil) == nil && DMFinderIPAVersion(@{@"CFBundleShortVersionString": @" "}) == nil &&
              [DMFinderIPAVersion(@{@"CFBundleShortVersionString": @2}) isEqualToString:@"2"] && DMFinderIPAVersion(@{@"CFBundleShortVersionString": @[@"1"]}) == nil, "the version: CFBundleShortVersionString only (never CFBundleVersion)");
        CHECK([DMFinderIPAFileName(DMFinderIPAAppName(clock, @"/x/MobileTimer.app", nil), DMFinderIPAVersion(clock)) isEqualToString:@"Clock.ipa"] &&
              [DMFinderIPAFileName(DMFinderIPAAppName(files, @"/x/Files.app", nil), DMFinderIPAVersion(files)) isEqualToString:@"Files 1.0.ipa"], "together: Clock.ipa, Files 1.0.ipa");

        // ---- the types: its own, then a zip named .ipa (a receiver taking archives names the file .ipa, not .zip) ----
        {
            NSArray<NSString *> *types = DMFinderIPATypes();
            UTType *apple = [UTType typeWithIdentifier:@"com.apple.itunes.ipa"], *last = [UTType typeWithIdentifier:types.lastObject];
            NSString *own = apple.isDeclared ? @"com.apple.itunes.ipa" : [UTType typeWithFilenameExtension:@"ipa"].identifier;
            CHECK(types.count >= 1 && types.count <= 2 && [types.firstObject isEqualToString:own], "its own type first: %s (this Mac declares Apple's: %d)", types.firstObject.UTF8String, apple.isDeclared);
            CHECK([last conformsToType:UTTypeZIP] && [last.preferredFilenameExtension isEqualToString:@"ipa"] && ![types.lastObject isEqualToString:UTTypeZIP.identifier],
                  "then a zip archive whose file extension is ipa (%s), not public.zip-archive itself", types.lastObject.UTF8String);
            CHECK(types.count == 1 || ![[UTType typeWithIdentifier:types.firstObject] conformsToType:UTTypeZIP], "two types only when the .ipa's own is not a zip already");
            UTType *again = [UTType typeWithIdentifier:[NSString stringWithString:types.lastObject]];
            CHECK([again conformsToType:UTTypeArchive] && [again.preferredFilenameExtension isEqualToString:@"ipa"], "  ... read back from its identifier alone (as the receiving app does): an archive, extension ipa");
        }

        // ---- the layout: Payload/<Name>.app ----
        CHECK([DMFinderIPAPayloadPath(@"/var/containers/Bundle/Application/FF1D04DC-4A8A-4AE1-85C1-1BDF22B5486A/MobileTimer.app") isEqualToString:@"Payload/MobileTimer.app"] &&
              [DMFinderIPAPayloadPath(@"/Applications/Photo Booth.app") isEqualToString:@"Payload/Photo Booth.app"], "Payload/ + the bundle's own folder name");
        // (an installed app's container, as installd lays it out: the .app beside the installer's files, its FairPlay license inside it)
        NSString *container = [Root stringByAppendingPathComponent:@"982FC431-99D3-4C49-AE2B-58DEBC866A18"], *app = [container stringByAppendingPathComponent:@"Fix.app"];
        for (NSString *d in @[@"Frameworks/A.framework", @"SC_Info", @"_CodeSignature", @"Base.lproj"]) [FM createDirectoryAtPath:[app stringByAppendingPathComponent:d] withIntermediateDirectories:YES attributes:nil error:nil];
        [@{@"CFBundleExecutable": @"Fix", @"CFBundleIdentifier": @"com.example.fix", @"CFBundleDisplayName": @"Fix It", @"CFBundleShortVersionString": @"1.2"} writeToFile:[app stringByAppendingPathComponent:@"Info.plist"] atomically:NO];
        [Image(YES, 1, NO) writeToFile:[app stringByAppendingPathComponent:@"Fix"] atomically:NO];
        [[@"lib" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:[app stringByAppendingPathComponent:@"Frameworks/A.framework/A"] atomically:NO];
        [[@"sinf" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:[app stringByAppendingPathComponent:@"SC_Info/Fix.sinf"] atomically:NO];
        [[@"cr" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:[app stringByAppendingPathComponent:@"_CodeSignature/CodeResources"] atomically:NO];
        [[@"ro" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:[app stringByAppendingPathComponent:@"Base.lproj/ro.strings"] atomically:NO];
        for (NSString *f in @[@"iTunesMetadata.plist", @"BundleMetadata.plist"]) [[@"meta" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:[container stringByAppendingPathComponent:f] atomically:NO];
        chmod([app stringByAppendingPathComponent:@"Fix"].fileSystemRepresentation, 0755);
        chmod([app stringByAppendingPathComponent:@"Frameworks/A.framework/A"].fileSystemRepresentation, 0755);
        chmod([app stringByAppendingPathComponent:@"Base.lproj/ro.strings"].fileSystemRepresentation, 0444);
        NSString *stage = [Root stringByAppendingPathComponent:@"stage"]; NSError *err = nil;
        NSString *payload = DMFinderIPAStage(app, stage, &err);
        CHECK([payload isEqualToString:[stage stringByAppendingPathComponent:@"Payload"]], "the stage gives the Payload folder: %s (%s)", payload.UTF8String, err.description.UTF8String ?: "");
        NSString *staged = [stage stringByAppendingPathComponent:@"Payload/Fix.app"];
        NSArray *want = [[FM subpathsOfDirectoryAtPath:app error:nil] sortedArrayUsingSelector:@selector(compare:)], *got = [[FM subpathsOfDirectoryAtPath:staged error:nil] sortedArrayUsingSelector:@selector(compare:)];
        CHECK(want.count == 11 && [want isEqualToArray:got], "Payload/Fix.app holds the bundle as it is, every file and folder (%lu / %lu)", (unsigned long)got.count, (unsigned long)want.count);
        BOOL same = YES; for (NSString *f in want) {
            struct stat a, b; lstat([app stringByAppendingPathComponent:f].fileSystemRepresentation, &a); lstat([staged stringByAppendingPathComponent:f].fileSystemRepresentation, &b);
            if ((a.st_mode & 07777) != (b.st_mode & 07777) || a.st_size != b.st_size) { same = NO; printf("  differs: %s %o/%o\n", f.UTF8String, a.st_mode & 07777, b.st_mode & 07777); }
            BOOL dir = NO; if ([FM fileExistsAtPath:[app stringByAppendingPathComponent:f] isDirectory:&dir] && !dir && ![[NSData dataWithContentsOfFile:[app stringByAppendingPathComponent:f]] isEqualToData:[NSData dataWithContentsOfFile:[staged stringByAppendingPathComponent:f]]]) same = NO;
        }
        CHECK(same, "  ... each with its permissions and contents (the executable 755, a read-only file 444)");
        CHECK(![FM fileExistsAtPath:[stage stringByAppendingPathComponent:@"Payload/iTunesMetadata.plist"]] && ![FM fileExistsAtPath:[stage stringByAppendingPathComponent:@"iTunesMetadata.plist"]] && [FM fileExistsAtPath:[staged stringByAppendingPathComponent:@"SC_Info/Fix.sinf"]],
              "  ... only the bundle: the installer's files beside it stay out (its SC_Info license is part of it)");
        CHECK([FM fileExistsAtPath:[app stringByAppendingPathComponent:@"Fix"]] && [[FM subpathsOfDirectoryAtPath:container error:nil] count] == 14, "  ... the installed app is left as it was");
        {   // (a link in a bundle is kept a link -- never followed out of the bundle; see test-finderipa.sh for what the zip does with one)
            NSString *withLink = [Root stringByAppendingPathComponent:@"L.app"], *ls = [Root stringByAppendingPathComponent:@"lstage"];
            [FM createDirectoryAtPath:[withLink stringByAppendingPathComponent:@"Real"] withIntermediateDirectories:YES attributes:nil error:nil];
            symlink("Real", [withLink stringByAppendingPathComponent:@"Current"].fileSystemRepresentation);
            DMFinderIPAStage(withLink, ls, NULL);
            struct stat st; char t[64] = {0};
            CHECK(lstat([ls stringByAppendingPathComponent:@"Payload/L.app/Current"].fileSystemRepresentation, &st) == 0 && S_ISLNK(st.st_mode) && readlink([ls stringByAppendingPathComponent:@"Payload/L.app/Current"].fileSystemRepresentation, t, sizeof t - 1) == 4 && !strcmp(t, "Real"),
                  "  ... a link is staged as the link it is");
        }
        CHECK(DMFinderIPAStage([Root stringByAppendingPathComponent:@"Gone.app"], [Root stringByAppendingPathComponent:@"gstage"], &err) == nil && err, "an app that isn't there: no Payload, an error");
        CHECK(DMFinderIPASameVolume(Root, app) && !DMFinderIPASameVolume(Root, @"/dev") && !DMFinderIPASameVolume(Root, [Root stringByAppendingPathComponent:@"nothing"]),
              "one volume or not (another file system: /dev here, the iPad's /Applications there)");
        // (the zip Finder makes: the Payload folder through the Foundation zip it uses for every folder -- Finder.h DMFDStageItem)
        const char *out = getenv("IPA_OUT");
        if (out) {
            __block BOOL ok = NO; NSError *ce = nil;
            [[[NSFileCoordinator alloc] initWithFilePresenter:nil] coordinateReadingItemAtURL:[NSURL fileURLWithPath:payload] options:NSFileCoordinatorReadingForUploading error:&ce byAccessor:^(NSURL *z) {
                ok = [FM copyItemAtURL:z toURL:[NSURL fileURLWithPath:@(out)] error:nil]; }];
            CHECK(ok, "the Payload folder zipped as Finder zips a folder (%s)", ce.description.UTF8String ?: "");
        }

        // ---- FairPlay ----
        CHECK(Enc(@"e64", Image(YES, 1, NO)) == 1, "64-bit, cryptid 1: encrypted");
        CHECK(Enc(@"p64", Image(YES, 0, NO)) == 0, "64-bit, cryptid 0: not (what the linker writes into every iOS executable)");
        CHECK(Enc(@"n64", Image(YES, -1, NO)) == 0, "64-bit, no encryption command: not");
        CHECK(Enc(@"e32", Image(NO, 1, NO)) == 1 && Enc(@"p32", Image(NO, 0, NO)) == 0, "32-bit (LC_ENCRYPTION_INFO): 1 / 0");
        CHECK(Enc(@"s64", Image(YES, 1, YES)) == 1 && Enc(@"s64p", Image(YES, 0, YES)) == 0, "the other byte order: 1 / 0");
        CHECK(Enc(@"fat1", Fat(@[Image(YES, 0, NO), Image(YES, 1, NO)], NO)) == 1, "fat, one slice encrypted: encrypted");
        CHECK(Enc(@"fat0", Fat(@[Image(YES, 0, NO), Image(NO, 0, NO)], NO)) == 0, "fat, none: not");
        CHECK(Enc(@"fat64", Fat(@[Image(YES, 1, NO)], YES)) == 1 && Enc(@"fat64p", Fat(@[Image(YES, -1, NO)], YES)) == 0, "fat with 64-bit offsets: 1 / 0");
        {
            NSMutableData *d = Image(YES, 1, NO); ((struct mach_header_64 *)d.mutableBytes)->sizeofcmds = 1 << 20;
            CHECK(Enc(@"long", d) == -1, "commands said to run past the file: unreadable, not \"not encrypted\"");
            d = Image(YES, 1, NO); ((struct load_command *)((uint8_t *)d.mutableBytes + sizeof(struct mach_header_64)))->cmdsize = 0;
            CHECK(Enc(@"zero", d) == -1, "a command of size 0 (a walk that would never end): unreadable");
            d = Image(YES, 1, NO); ((struct mach_header_64 *)d.mutableBytes)->ncmds = 1000;
            CHECK(Enc(@"many", d) == -1, "more commands than there is room for: unreadable");
            d = Image(YES, 1, NO); d.length = 20;
            CHECK(Enc(@"cut", d) == -1, "a cut-off header: unreadable");
            NSMutableData *f = [Fat(@[Image(YES, 0, NO)], NO) mutableCopy]; ((struct fat_arch *)((uint8_t *)f.mutableBytes + sizeof(struct fat_header)))->offset = OSSwapHostToBigInt32(0x7fff0000);
            CHECK(Enc(@"fatpast", f) == -1, "a fat slice past the end: unreadable");
            CHECK(Enc(@"fatenc", Fat(@[[NSData dataWithBytes:"junkjunkjunk" length:12], Image(YES, 1, NO)], NO)) == 1, "a fat file with a bad slice, then an encrypted one: encrypted");
            CHECK(Enc(@"fatbad", Fat(@[[NSData dataWithBytes:"junkjunkjunk" length:12], Image(YES, 0, NO)], NO)) == -1, "a bad slice and a plain one: unreadable (not \"not encrypted\")");
        }
        CHECK(Enc(@"junk", [@"#!/bin/sh\necho hi\n" dataUsingEncoding:NSUTF8StringEncoding]) == -1 && Enc(@"empty", [NSData data]) == -1, "not a Mach-O (a script, an empty file): unreadable");
        CHECK(DMFinderMachOEncrypted(Root) == -1 && DMFinderMachOEncrypted([Root stringByAppendingPathComponent:@"none"]) == -1, "a folder, a missing file: unreadable");
        CHECK(DMFinderMachOEncrypted(@"/bin/ls") == 0, "a real binary of this Mac (/bin/ls, fat): not encrypted");
        CHECK(DMFinderIPAEncrypted(app) == 1, "the app: its Info.plist's CFBundleExecutable read -- encrypted");
        {
            NSString *a2 = [Root stringByAppendingPathComponent:@"Plain.app"]; [FM createDirectoryAtPath:a2 withIntermediateDirectories:YES attributes:nil error:nil];
            [Image(YES, 0, NO) writeToFile:[a2 stringByAppendingPathComponent:@"Plain"] atomically:NO];
            [@{@"CFBundleExecutable": @"Plain"} writeToFile:[a2 stringByAppendingPathComponent:@"Info.plist"] atomically:NO];
            CHECK(DMFinderIPAEncrypted(a2) == 0, "an app built for the iPad, not from the App Store: not encrypted");
            [@{@"CFBundleExecutable": @"../Fix.app/Fix"} writeToFile:[a2 stringByAppendingPathComponent:@"Info.plist"] atomically:NO];
            CHECK(DMFinderIPAEncrypted(a2) == -1, "an executable named outside the bundle: unknown (never read)");
            [@{@"CFBundleIdentifier": @"x"} writeToFile:[a2 stringByAppendingPathComponent:@"Info.plist"] atomically:NO];
            CHECK(DMFinderIPAEncrypted(a2) == -1 && DMFinderIPAEncrypted([Root stringByAppendingPathComponent:@"Gone.app"]) == -1, "no executable named, no app: unknown");
        }
        const char *ios = getenv("IOS_EXE");   // (an iOS executable from the real linker: test-finderipa.sh builds it when an iOS SDK is here)
        if (ios) {
            NSString *exe = @(ios); NSMutableData *d = [NSMutableData dataWithContentsOfFile:exe]; long at = CryptidOffset(d);
            CHECK(at > 0 && DMFinderMachOEncrypted(exe) == 0, "the linker's iOS executable: an encryption command with cryptid 0, not encrypted (at %ld)", at);
            if (at > 0) { *(uint32_t *)((uint8_t *)d.mutableBytes + at) = 1; CHECK(Enc(@"ios-enc", d) == 1, "  ... its cryptid set to 1 (as the App Store's are): encrypted"); }
        } else printf("note: no iOS executable handed in (no iOS SDK found): the linker's own file not checked\n");

        // ---- read only: the file checked is never changed ----
        NSString *e64 = [Root stringByAppendingPathComponent:@"e64"]; NSData *before = [NSData dataWithContentsOfFile:e64]; struct stat s0, s1; stat(e64.fileSystemRepresentation, &s0);
        DMFinderMachOEncrypted(e64); stat(e64.fileSystemRepresentation, &s1);
        CHECK([before isEqualToData:[NSData dataWithContentsOfFile:e64]] && s0.st_mtimespec.tv_sec == s1.st_mtimespec.tv_sec && s0.st_mtimespec.tv_nsec == s1.st_mtimespec.tv_nsec, "the check leaves the executable as it was");

        [FM removeItemAtPath:Root error:nil];
        printf("test-finderipa: %d passed, %d failed\n", passes, fails);
    }
    return fails ? 1 : 0;
}
