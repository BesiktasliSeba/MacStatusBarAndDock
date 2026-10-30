// Mac test of the quit set's file (common/PrewarmQuitSet.h): SpringBoard's write (StatusBar.x DMPrewarmQuitWriteFile) read back as the dasd part
// reads it (PrewarmBlock.x), XML and binary, every damaged or other shape an empty set, and the file stamp that has the set read again when the
// file changed (iPad 2, palera1n, 29 Oct: cfprefsd gave dasd nothing for our domain, so it refused nothing).
#import <Foundation/Foundation.h>
#include <unistd.h>
#include "../common/PrewarmQuitSet.h"
static int fails = 0, checks = 0;
#define CHECK(cond, what) do { checks++; if (!(cond)) { fails++; printf("FAIL: %s\n", what); } } while (0)
static NSData *Plist(id obj, NSPropertyListFormat f) { return [NSPropertyListSerialization dataWithPropertyList:obj format:f options:0 error:NULL]; }
int main(void) {
    @autoreleasepool {
        NSArray *six = @[@"com.apple.mobiletimer", @"com.apple.tips", @"com.apple.Preferences", @"com.apple.Maps", @"com.apple.weather", @"com.apple.AppStore"];
        NSData *written = MSBDPrewarmQuitSetPlist(six);
        CHECK(written.length > 0 && [[[NSString alloc] initWithData:written encoding:NSUTF8StringEncoding] containsString:@"<key>quitSet</key>"], "SpringBoard's write: an XML property list with the set under quitSet");
        NSSet *s = MSBDPrewarmQuitSetFromPlist(written);
        CHECK(s.count == 6 && [s isEqualToSet:[NSSet setWithArray:six]], "read back: all six apps");
        id back = [NSPropertyListSerialization propertyListWithData:written options:0 format:NULL error:NULL];
        CHECK([back[@"quitSet"] isEqualToArray:six], "  ... stored in their order (oldest quit first)");
        CHECK(MSBDPrewarmQuitSetFromPlist(MSBDPrewarmQuitSetPlist(@[])).count == 0 && MSBDPrewarmQuitSetFromPlist(MSBDPrewarmQuitSetPlist(nil)).count == 0, "an empty set (or none) written: read back empty");
        NSData *bin = Plist(@{@"quitSet": six}, NSPropertyListBinaryFormat_v1_0);
        CHECK(bin.length > 8 && !memcmp(bin.bytes, "bplist00", 8) && [MSBDPrewarmQuitSetFromPlist(bin) isEqualToSet:s], "binary: the same six");
        CHECK([MSBDPrewarmQuitSetFromPlist(Plist(@{@"quitSet": six, @"other": @1}, NSPropertyListBinaryFormat_v1_0)) isEqualToSet:s], "other keys beside it: ignored");
        CHECK(MSBDPrewarmQuitSetFromPlist(Plist(@{@"quitSet": @[@"com.apple.tips", @"", @7, @[@"x"], @"com.apple.tips"]}, NSPropertyListBinaryFormat_v1_0)).count == 1, "empty names, numbers, lists and repeats left out");
        CHECK(MSBDPrewarmQuitSetFromPlist(nil).count == 0, "no file: empty");
        CHECK(MSBDPrewarmQuitSetFromPlist([NSData data]).count == 0, "an empty file: empty");
        CHECK(MSBDPrewarmQuitSetFromPlist([bin subdataWithRange:NSMakeRange(0, bin.length / 2)]).count == 0, "a cut file: empty");
        CHECK(MSBDPrewarmQuitSetFromPlist([@"not a plist" dataUsingEncoding:NSUTF8StringEncoding]).count == 0, "not a property list: empty");
        CHECK(MSBDPrewarmQuitSetFromPlist(Plist(@{}, NSPropertyListBinaryFormat_v1_0)).count == 0, "no quitSet key (the set cleared, the stock status bar): empty");
        CHECK(MSBDPrewarmQuitSetFromPlist(Plist(@{@"quitSet": @"com.apple.tips"}, NSPropertyListBinaryFormat_v1_0)).count == 0, "a string, not a list: empty");
        CHECK(MSBDPrewarmQuitSetFromPlist(Plist(six, NSPropertyListBinaryFormat_v1_0)).count == 0, "a list at the top, not a dictionary: empty");
        // the stamp: a real file, rewritten as cfprefsd does (a new file in its place)
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"tpq-%d", getpid()]];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        NSString *f = [dir stringByAppendingPathComponent:@"MacStatusBarAndDock-PrewarmQuitSet.plist"];
        struct stat st;
        MSBDPrewarmFileStamp none = MSBDPrewarmStampOf(stat(f.fileSystemRepresentation, &st) == 0 ? &st : NULL), zero = MSBDPrewarmStampOf(NULL);
        CHECK(!none.present && !MSBDPrewarmStampChanged(zero, none), "no file, read as no file: unchanged");
        [written writeToFile:f atomically:YES];
        MSBDPrewarmFileStamp a = MSBDPrewarmStampOf(stat(f.fileSystemRepresentation, &st) == 0 ? &st : NULL);
        CHECK(a.present && a.size == (long long)written.length && MSBDPrewarmStampChanged(none, a), "the file came: changed");
        MSBDPrewarmFileStamp a2 = MSBDPrewarmStampOf(stat(f.fileSystemRepresentation, &st) == 0 ? &st : NULL);
        CHECK(!MSBDPrewarmStampChanged(a, a2), "the same file again: unchanged (no read)");
        usleep(20000);
        [MSBDPrewarmQuitSetPlist([six subarrayWithRange:NSMakeRange(0, 5)]) writeToFile:f atomically:YES];
        MSBDPrewarmFileStamp b = MSBDPrewarmStampOf(stat(f.fileSystemRepresentation, &st) == 0 ? &st : NULL);
        CHECK(MSBDPrewarmStampChanged(a, b), "rewritten with one app less: changed");
        CHECK(MSBDPrewarmQuitSetFromPlist([NSData dataWithContentsOfFile:f]).count == 5, "  ... and read again: five");
        MSBDPrewarmFileStamp sameTime = b; sameTime.size += 1;
        CHECK(MSBDPrewarmStampChanged(b, sameTime), "the same time, another size: changed");
        MSBDPrewarmFileStamp ns = b; ns.nsec += 1;
        CHECK(MSBDPrewarmStampChanged(b, ns), "a nanosecond later: changed");
        [[NSFileManager defaultManager] removeItemAtPath:f error:NULL];
        MSBDPrewarmFileStamp gone = MSBDPrewarmStampOf(stat(f.fileSystemRepresentation, &st) == 0 ? &st : NULL);
        CHECK(MSBDPrewarmStampChanged(b, gone) && !gone.present, "the file went: changed (an empty set)");
        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
        CHECK(!strcmp(kMSBDPrewarmQuitSetFile, "/var/jb/var/mobile/Library/Preferences/MacStatusBarAndDock-PrewarmQuitSet.plist"), "the file sits in the jailbreak's preferences folder, beside dasd's start count");
    }
    printf("%s: %d of %d checks passed\n", fails ? "FAIL" : "PASS", checks - fails, checks);
    return fails ? 1 : 0;
}
