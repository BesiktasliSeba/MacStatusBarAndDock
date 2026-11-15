// test-mobilereads.m -- Mac test of the root helper's reads of mobile's files (1.8.7.5, audit L22 of 1.8.7.2): sshtoggled read Choicy's settings,
// our records of our changes in them, the engines' saved settings, the old packages' preference files and Control Center's lists as root, and
// wrote what it read (or what it made of it) back where mobile reads it; a link planted there by a hostile process running as mobile reached a
// file only root may read. Run on the real reader cut out of main.m (reader.inc, made by tools/test-mobilereads.sh: AsMobile, MobileFileData,
// MobilePlist, CopyQuitSetForDasd -- the postinst's quit-set copy, now the helper's) on files in a scratch folder (MR_DIR). For the code before
// the fix the .sh gives the reads as they were (dataWithContentsOfFile:, dictionaryWithContentsOfFile:) under the same names. The fifo comes
// last: the reads of before wait on it for ever (the .sh bounds the run).
#import <Foundation/Foundation.h>
#include <sys/stat.h>
#include <sys/kauth.h>
#include <pthread.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

static NSMutableArray<NSString *> *gLog;
static void ELog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void ELog(NSString *fmt, ...) { va_list ap; va_start(ap, fmt); [gLog addObject:[[NSString alloc] initWithFormat:fmt arguments:ap]]; va_end(ap); }
static BOOL Exists(NSString *path) { struct stat st; return lstat(path.fileSystemRepresentation, &st) == 0; }
#define PREFSDIR MR_DIR "/Preferences"
#define kMSBDPrewarmQuitSetFile MR_DIR "/Preferences/MacStatusBarAndDock-PrewarmQuitSet.plist"
#include "reader.inc"

static int gN = 0, gFail = 0;
static void Expect(BOOL ok, NSString *what) { gN++; if (!ok) gFail++; printf("  %s %s\n", ok ? "ok  " : "FAIL", what.UTF8String); fflush(stdout); }
static NSString *P(NSString *name) { return [@MR_DIR "/Preferences" stringByAppendingPathComponent:name]; }
static BOOL Logged(NSString *s) { for (NSString *l in gLog) if ([l containsString:s]) return YES; return NO; }
static NSData *D(NSString *s) { return [s dataUsingEncoding:NSUTF8StringEncoding]; }

int main(void) {
    @autoreleasepool {
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:@MR_DIR "/Preferences" withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *secret = @MR_DIR "/root-only.plist";   // (a file only root may read, on the iPad: here the test's own, mode 0600)
        [@{@"secret": @"not for mobile"} writeToFile:secret atomically:YES]; chmod(secret.fileSystemRepresentation, 0600);
        printf("MobileFileData:\n");
        gLog = [NSMutableArray array];
        [D(@"hello") writeToFile:P(@"plain.txt") atomically:YES];
        Expect([MobileFileData(P(@"plain.txt")) isEqual:D(@"hello")] && !gLog.count, @"a plain file: its contents");
        [[NSData data] writeToFile:P(@"empty.txt") atomically:YES];
        NSData *e = MobileFileData(P(@"empty.txt"));
        Expect(e && e.length == 0, @"an empty plain file: empty data (as before)");
        Expect(!MobileFileData(P(@"missing.txt")) && !gLog.count, @"no file: nil, nothing logged");
        symlink(secret.fileSystemRepresentation, P(@"link.plist").fileSystemRepresentation);
        gLog = [NSMutableArray array];
        Expect(!MobileFileData(P(@"link.plist")), @"a link to a root-only file: nil (never followed)");
        Expect(Logged(@"link.plist: not a plain file (a link) -- not read"), @"  ... said in the log");
        symlink((@MR_DIR "/nowhere").fileSystemRepresentation, P(@"dangling.plist").fileSystemRepresentation);
        Expect(!MobileFileData(P(@"dangling.plist")), @"a link to nothing: nil");
        mkdir(P(@"folder.plist").fileSystemRepresentation, 0755);
        gLog = [NSMutableArray array];
        Expect(!MobileFileData(P(@"folder.plist")) && Logged(@"folder.plist: not a plain file (another kind of file) -- not read"), @"a folder: nil, said in the log");
        printf("MobilePlist (as dictionaryWithContentsOfFile: reads one):\n");
        NSDictionary *choicy = @{@"globalDeniedTweaks": @[@"Zetsu"], @"preferenceVersion": @1};
        [choicy writeToFile:P(@"xml.plist") atomically:YES];
        Expect([MobilePlist(P(@"xml.plist")) isEqual:choicy], @"an XML property list: the dictionary");
        [[NSPropertyListSerialization dataWithPropertyList:choicy format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil] writeToFile:P(@"bin.plist") atomically:YES];
        Expect([MobilePlist(P(@"bin.plist")) isEqual:choicy], @"a binary property list: the dictionary");
        [@[@"a"] writeToFile:P(@"array.plist") atomically:YES];
        [D(@"\x01not a plist") writeToFile:P(@"junk.plist") atomically:YES];
        Expect(!MobilePlist(P(@"array.plist")) && !MobilePlist(P(@"junk.plist")) && !MobilePlist(P(@"missing.plist")), @"an array, junk, no file: nil (as before)");
        Expect(!MobilePlist(P(@"link.plist")), @"a link to a root-only property list: nil");
#ifdef MR_COPY
        printf("CopyQuitSetForDasd (the postinst's copy, the helper's now):\n");
        NSString *qs = @kMSBDPrewarmQuitSetFile, *qp = P(@"com.besiktasliseba.macstatusbar.prewarm.plist");
        NSData *set = D(@"bplist00 the set");
        [set writeToFile:qp atomically:YES];
        struct stat st;
        Expect(CopyQuitSetForDasd() == 0 && [[NSData dataWithContentsOfFile:qs] isEqual:set] && lstat(qs.fileSystemRepresentation, &st) == 0 && S_ISREG(st.st_mode) && (st.st_mode & 0777) == 0644,
               @"the set's plain file: copied byte for byte, a plain file, mode 0644");
        [D(@"ours") writeToFile:qs atomically:YES];
        Expect(CopyQuitSetForDasd() == 1 && [[NSData dataWithContentsOfFile:qs] isEqual:D(@"ours")], @"  ... one there already (SpringBoard's own): kept");
        unlink(qs.fileSystemRepresentation); unlink(qp.fileSystemRepresentation);
        symlink(secret.fileSystemRepresentation, qp.fileSystemRepresentation);
        Expect(CopyQuitSetForDasd() == 1 && !Exists(qs), @"the set's file a link to a root-only file: nothing copied");
        unlink(qp.fileSystemRepresentation); [set writeToFile:qp atomically:YES];
        symlink((@MR_DIR "/made-by-root").fileSystemRepresentation, qs.fileSystemRepresentation);
        Expect(CopyQuitSetForDasd() == 1 && !Exists(@MR_DIR "/made-by-root") && Exists(qs), @"dasd's file a link to nowhere: left alone, nothing written through it");
        unlink(qs.fileSystemRepresentation); unlink(qp.fileSystemRepresentation);
        Expect(CopyQuitSetForDasd() == 1 && !Exists(qs), @"no set: nothing made");
#endif
        printf("a fifo (last):\n");
        mkfifo(P(@"fifo.plist").fileSystemRepresentation, 0644);
        CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
        NSData *f = MobileFileData(P(@"fifo.plist"));
        Expect(!f && CFAbsoluteTimeGetCurrent() - t0 < 1.0, @"a fifo: nil, at once (never waits for a writer)");
        Expect(!MobilePlist(P(@"fifo.plist")), @"  ... as a property list too");
    }
    printf("test-mobilereads (compiled): %d checks, %d failed\n", gN, gFail);
    return gFail ? 1 : 0;
}
