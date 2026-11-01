// FinderIPA.h -- an app shared from Finder, or handed to another app, goes as an .ipa (1.7.7 item 7, KT: "it'd be nice if we can share an ipa
// like that"): a zip whose root is Payload/<Name>.app, the bundle as installed with its files' permissions, named "<App name> <version>.ipa".
// Finder's own hand-over makes it (Finder.h DMFDStageItem): the app is cloned (from another volume: copied) into a Payload folder in SpringBoard's
// tmp, and that folder is zipped by the same Foundation zip a folder gets, under the same size rules (asks above 200 MB, refused above 2 GB). Only
// the bundle goes: the app's data (its Documents, its data container) is never part of it, nor the installer's files beside the bundle
// (iTunesMetadata.plist, BundleMetadata.plist). An App Store app's main executable is FairPlay-encrypted for the Apple ID that got it (its license
// is the bundle's SC_Info): the copy opens only on iPads signed in with that Apple ID, and Finder says so before it hands one over
// (DMFinderIPAEncrypted reads the executable's load commands, read only; nothing is ever decrypted). One limit, the zip's: Foundation's zip refuses
// a symbolic link anywhere in a folder (macOS 15 and iOS 16.7.7 alike), so a bundle with one gets the "could not be compressed" sheet -- none of
// the iPad 2's 197 installed bundles has one. Foundation, UniformTypeIdentifiers, POSIX and the Mach-O headers only: Finder.h runs it,
// tools/test-finderipa.m checks it on the Mac.
#pragma once
#import <Foundation/Foundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <mach-o/loader.h>
#include <mach-o/fat.h>
#include <libkern/OSByteOrder.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>

// The .ipa's file name: "<App name> <version>.ipa", or "<App name>.ipa" when the app has no version. Spaces around either are trimmed, "/" (the one
// character a file name can't hold) becomes "-", a control character a space, and a leading "." goes (never a hidden file). A name too long for a
// file name (255 bytes) is shortened at a character's end; the version and ".ipa" stay whole (a version that long is left out).
static NSString *DMFinderIPAFileName(NSString *appName, NSString *version) {
    NSString *(^clean)(id) = ^NSString *(id s) {
        if (![s isKindOfClass:[NSString class]]) return @"";
        NSMutableString *m = [[(NSString *)s stringByReplacingOccurrencesOfString:@"/" withString:@"-"] mutableCopy];
        for (NSUInteger i = 0; i < m.length; i++) {   // (C0 / C1 controls only: a joiner -- an emoji family's, Persian's ZWNJ -- is part of the name)
            unichar c = [m characterAtIndex:i];
            if (c < 0x20 || (c >= 0x7F && c <= 0x9F)) [m replaceCharactersInRange:NSMakeRange(i, 1) withString:@" "];
        }
        NSString *t = [m stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        while ([t hasPrefix:@"."]) t = [[t substringFromIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return t;
    };
    NSString *n = clean(appName), *v = clean(version);
    if (!n.length) n = @"App";
    NSString *tail = v.length && strlen(v.UTF8String) <= 64 ? [NSString stringWithFormat:@" %@.ipa", v] : @".ipa";
    if (n.length > 255) n = [n substringToIndex:[n rangeOfComposedCharacterSequenceAtIndex:255].location];   // (no more characters than bytes allowed)
    while (n.length > 1 && strlen(n.UTF8String) + strlen(tail.UTF8String) > 255) n = [n substringToIndex:[n rangeOfComposedCharacterSequenceAtIndex:n.length - 1].location];
    return [(n.length ? n : @"App") stringByAppendingString:tail];
}
// The app's name for it: the name the iPad shows (`shown`: LaunchServices' name, when the app's bundle id is installed), else its Info.plist's
// display name or bundle name, else the .app folder's own name ("MobileTimer.app" is Clock: the display name comes first).
static NSString *DMFinderIPAAppName(NSDictionary *info, NSString *appPath, NSString *shown) {
    NSDictionary *i = [info isKindOfClass:[NSDictionary class]] ? info : nil;
    for (id n in @[shown ?: @"", i[@"CFBundleDisplayName"] ?: @"", i[@"CFBundleName"] ?: @""])
        if ([n isKindOfClass:[NSString class]] && [n stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length) return n;
    return appPath.lastPathComponent.stringByDeletingPathExtension;
}
// Its version: CFBundleShortVersionString (a number in the plist read as one), or nil -- the name then has none (Clock on 16.7.7 has none).
static NSString *DMFinderIPAVersion(NSDictionary *info) {
    id v = [info isKindOfClass:[NSDictionary class]] ? info[@"CFBundleShortVersionString"] : nil;
    if ([v isKindOfClass:[NSNumber class]]) v = [v stringValue];
    return [v isKindOfClass:[NSString class]] && [v stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length ? v : nil;
}
// The types an .ipa is offered as, its own first: Apple's ipa type when this system declares it (else what ".ipa" is here), then a zip named .ipa
// -- an .ipa is a zip archive. Both .ipa types are bare data on 16.7.7 (Apple's, and Filza's, which ".ipa" gives there), and Files takes only
// documents and archives, naming the file after the type it takes: offered as public.zip-archive it saved "Tips 9.0.zip". This one is UTType's own
// dynamic type for the extension ipa conforming to public.zip-archive (extension and conformance in its identifier: the same in every process);
// where a declared .ipa type is a zip already, that one, and the list is one type.
static NSArray<NSString *> *DMFinderIPATypes(void) {
    UTType *ipa = [UTType typeWithIdentifier:@"com.apple.itunes.ipa"];
    NSString *own = (ipa.isDeclared ? ipa : [UTType typeWithFilenameExtension:@"ipa"]).identifier ?: UTTypeData.identifier;
    NSString *zip = [UTType typeWithTag:@"ipa" tagClass:UTTagClassFilenameExtension conformingToType:UTTypeZIP].identifier ?: UTTypeZIP.identifier;
    return [own isEqualToString:zip] ? @[own] : @[own, zip];
}
// Where the app sits in the .ipa: Payload/<its own folder name> (the bundle's name as installed: Payload/MobileTimer.app).
static NSString *DMFinderIPAPayloadPath(NSString *appPath) { return [@"Payload" stringByAppendingPathComponent:appPath.lastPathComponent]; }
// Where an item is staged in the app's folder (Finder.h DMFDStageItem): <dir>/<name>, or with " 2", " 3" ... before its extension while that name is
// there already -- two items of one name, as two copies of an app make one .ipa name: "Tips 9.0 2.ipa". Anything there counts, a dangling link too
// (lstat). After " 99" the last one tried comes back: its copy then fails and says why.
static NSString *DMFinderStagedPath(NSString *dir, NSString *name) {
    NSString *dst = [dir stringByAppendingPathComponent:name];
    struct stat st;
    for (int n = 2; lstat(dst.fileSystemRepresentation, &st) == 0 && n < 100; n++)
        dst = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@ %d%@", name.stringByDeletingPathExtension, n, name.pathExtension.length ? [@"." stringByAppendingString:name.pathExtension] : @""]];
    return dst;
}
// Two paths on one volume (an APFS clone is possible between them).
static BOOL DMFinderIPASameVolume(NSString *a, NSString *b) {
    struct stat x, y;
    return stat(a.fileSystemRepresentation, &x) == 0 && stat(b.fileSystemRepresentation, &y) == 0 && x.st_dev == y.st_dev;
}
// The app laid out for the zip: <dir>/Payload/<Name>.app, a clone of the bundle (instant, no space; NSFileManager clones on APFS) or, from another
// volume (the system's own apps in /Applications, the jailbreak's), a copy -- files, permissions and links as they are. Returns the Payload folder
// (the zip's root), or nil with *err.
static NSString *DMFinderIPAStage(NSString *appPath, NSString *dir, NSError **err) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *payload = [dir stringByAppendingPathComponent:@"Payload"];
    if (![fm createDirectoryAtPath:payload withIntermediateDirectories:YES attributes:nil error:err]) return nil;
    if (![fm copyItemAtPath:appPath toPath:[dir stringByAppendingPathComponent:DMFinderIPAPayloadPath(appPath)] error:err]) return nil;
    return payload;
}

// ---- FairPlay -------------------------------------------------------------------------------------------------------------------------------
// An App Store app's executable carries an encryption load command (LC_ENCRYPTION_INFO_64; LC_ENCRYPTION_INFO in a 32-bit one) whose cryptid is
// not 0 while its code is encrypted for the buyer. One Mach-O image at `off`: 1 encrypted, 0 not, -1 not one Finder can read (the load commands
// are checked against the image's own sizes; only they are read).
static int DMFinderMachOImageEncrypted(int fd, uint64_t off, uint64_t fileSize) {
    struct mach_header_64 h;   // (a 32-bit header is its first 28 bytes: ncmds and sizeofcmds at the same places)
    if (off >= fileSize || pread(fd, &h, sizeof(uint32_t), (off_t)off) != (ssize_t)sizeof(uint32_t)) return -1;
    BOOL swap = h.magic == MH_CIGAM || h.magic == MH_CIGAM_64, is64 = h.magic == MH_MAGIC_64 || h.magic == MH_CIGAM_64;
    if (!is64 && h.magic != MH_MAGIC && h.magic != MH_CIGAM) return -1;
    size_t hs = is64 ? sizeof(struct mach_header_64) : sizeof(struct mach_header);
    if (pread(fd, &h, hs, (off_t)off) != (ssize_t)hs) return -1;
    uint32_t ncmds = swap ? OSSwapInt32(h.ncmds) : h.ncmds, size = swap ? OSSwapInt32(h.sizeofcmds) : h.sizeofcmds;
    if (size > 16 * 1024 * 1024 || off + hs + size > fileSize || (uint64_t)ncmds * sizeof(struct load_command) > size) return -1;   // (each command takes 8 bytes at least)
    NSMutableData *buf = [NSMutableData dataWithLength:size];
    if (size && pread(fd, buf.mutableBytes, size, (off_t)(off + hs)) != (ssize_t)size) return -1;
    const uint8_t *p = buf.bytes;
    uint32_t at = 0;
    for (uint32_t i = 0; i < ncmds; i++) {
        struct load_command lc;
        if ((uint64_t)at + sizeof lc > size) return -1;
        memcpy(&lc, p + at, sizeof lc);
        uint32_t cmd = swap ? OSSwapInt32(lc.cmd) : lc.cmd, cs = swap ? OSSwapInt32(lc.cmdsize) : lc.cmdsize;
        if (cs < sizeof lc || (uint64_t)at + cs > size) return -1;
        if (cmd == LC_ENCRYPTION_INFO || cmd == LC_ENCRYPTION_INFO_64) {
            struct encryption_info_command e;   // (the 64-bit one adds only padding after cryptid)
            if (cs < sizeof e) return -1;
            memcpy(&e, p + at, sizeof e);
            if ((swap ? OSSwapInt32(e.cryptid) : e.cryptid) != 0) return 1;
        }
        at += cs;
    }
    return 0;
}
// A file: one image, or a fat file's every slice (encrypted when any slice is). 1 / 0 / -1 as above; the file is only opened for reading.
static int DMFinderMachOEncrypted(NSString *path) {
    int fd = open(path.fileSystemRepresentation, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return -1;
    struct stat st; uint32_t magic = 0; int r = -1;
    if (fstat(fd, &st) == 0 && S_ISREG(st.st_mode) && pread(fd, &magic, sizeof magic, 0) == (ssize_t)sizeof magic) {
        uint32_t be = OSSwapBigToHostInt32(magic);
        if (be == FAT_MAGIC || be == FAT_MAGIC_64) {
            struct fat_header fh;
            uint32_t n = pread(fd, &fh, sizeof fh, 0) == (ssize_t)sizeof fh ? OSSwapBigToHostInt32(fh.nfat_arch) : 0;
            BOOL bad = n == 0 || n > 64, enc = NO;
            for (uint32_t i = 0; i < n && n <= 64 && !enc; i++) {   // (a bad slice doesn't end the look: another may still be encrypted)
                uint64_t off = UINT64_MAX;
                if (be == FAT_MAGIC_64) { struct fat_arch_64 a; if (pread(fd, &a, sizeof a, (off_t)(sizeof fh + i * sizeof a)) == (ssize_t)sizeof a) off = OSSwapBigToHostInt64(a.offset); }
                else { struct fat_arch a; if (pread(fd, &a, sizeof a, (off_t)(sizeof fh + i * sizeof a)) == (ssize_t)sizeof a) off = OSSwapBigToHostInt32(a.offset); }
                int s = DMFinderMachOImageEncrypted(fd, off, (uint64_t)st.st_size);
                if (s < 0) bad = YES; else if (s == 1) enc = YES;
            }
            r = enc ? 1 : bad ? -1 : 0;
        } else r = DMFinderMachOImageEncrypted(fd, 0, (uint64_t)st.st_size);
    }
    close(fd);
    return r;
}
// An app's main executable (its Info.plist's CFBundleExecutable, a name inside the bundle): 1 FairPlay-encrypted, 0 not, -1 unknown.
static int DMFinderIPAEncrypted(NSString *appPath) {
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[appPath stringByAppendingPathComponent:@"Info.plist"]];
    NSString *exe = info[@"CFBundleExecutable"];
    if (![exe isKindOfClass:[NSString class]] || !exe.length || [exe containsString:@"/"] || [exe isEqualToString:@".."]) return -1;
    return DMFinderMachOEncrypted([appPath stringByAppendingPathComponent:exe]);
}
