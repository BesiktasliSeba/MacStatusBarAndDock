// test-dpkgcache.m -- Mac test of dpkg's status lookups in common/CrashExplain.h (S-2, 1.3.3): the block search (MSBDPackageFieldIn), the cache keyed
// on the status file's modification time and size (read once per change), and the main-thread lookup that never reads the file
// (MSBDPackageVersionNoWait). Run: tools/test-dpkgcache.sh
#import <Foundation/Foundation.h>
#include <utime.h>
#import "../common/CrashExplain.h"

static int gPass, gFail;
static void Check(NSString *what, BOOL ok, id got) {
    if (ok) gPass++; else { gFail++; printf("FAIL: %s (got %s)\n", what.UTF8String, [[got description] UTF8String]); }
}
static void WriteStatus(NSString *text, time_t mtime) {
    [text writeToFile:@MSBD_DPKG_STATUS atomically:YES encoding:NSUTF8StringEncoding error:nil];
    struct utimbuf t = { mtime, mtime };
    utime(MSBD_DPKG_STATUS, &t);
}
static BOOL Eq(NSString *a, NSString *b) { return (!a && !b) || [a isEqualToString:b]; }

int main(void) {
    @autoreleasepool {
        // ---- the block search ----
        NSString *s = @"Package: com.x.a\nStatus: install ok installed\nVersion: 1.0\nDepends: firmware\n\n"
                       "Package: com.x.ab\nVersion: 2.0\nPre-Depends: dpkg\nDescription: a tool\n Package: com.x.fake\n Version: 9.9\n\n"
                       "Package: com.x.mid\nName: Middle One\nVersion: 3.0-1+debug\n\n"
                       "Package: com.x.last\nVersion: 4.0";
        Check(@"first block", Eq(MSBDPackageFieldIn(s, @"com.x.a", @"Version"), @"1.0"), MSBDPackageFieldIn(s, @"com.x.a", @"Version"));
        Check(@"a name that is the start of another's", Eq(MSBDPackageFieldIn(s, @"com.x.ab", @"Version"), @"2.0"), MSBDPackageFieldIn(s, @"com.x.ab", @"Version"));
        Check(@"a description line is not a block", MSBDPackageFieldIn(s, @"com.x.fake", @"Version") == nil, MSBDPackageFieldIn(s, @"com.x.fake", @"Version"));
        Check(@"Depends is not Pre-Depends", MSBDPackageFieldIn(s, @"com.x.ab", @"Depends") == nil, MSBDPackageFieldIn(s, @"com.x.ab", @"Depends"));
        Check(@"Pre-Depends", Eq(MSBDPackageFieldIn(s, @"com.x.ab", @"Pre-Depends"), @"dpkg"), MSBDPackageFieldIn(s, @"com.x.ab", @"Pre-Depends"));
        Check(@"middle block, other field", Eq(MSBDPackageFieldIn(s, @"com.x.mid", @"Name"), @"Middle One"), MSBDPackageFieldIn(s, @"com.x.mid", @"Name"));
        Check(@"debug version", Eq(MSBDPackageFieldIn(s, @"com.x.mid", @"Version"), @"3.0-1+debug"), MSBDPackageFieldIn(s, @"com.x.mid", @"Version"));
        Check(@"last block, no newline at the end", Eq(MSBDPackageFieldIn(s, @"com.x.last", @"Version"), @"4.0"), MSBDPackageFieldIn(s, @"com.x.last", @"Version"));
        Check(@"the field of the next block is not taken", MSBDPackageFieldIn(s, @"com.x.a", @"Name") == nil, MSBDPackageFieldIn(s, @"com.x.a", @"Name"));
        Check(@"no such package", MSBDPackageFieldIn(s, @"com.x.none", @"Version") == nil, @"?");
        Check(@"empty text", MSBDPackageFieldIn(@"", @"com.x.a", @"Version") == nil, @"?");
        Check(@"nil text", MSBDPackageFieldIn(nil, @"com.x.a", @"Version") == nil, @"?");
        NSString *t = @"Package: com.y\nProvides: Package: com.z\nVersion: 1\n\nPackage: com.z\nVersion: 5\n";
        Check(@"the name inside another line is not a block start", Eq(MSBDPackageFieldIn(t, @"com.z", @"Version"), @"5"), MSBDPackageFieldIn(t, @"com.z", @"Version"));
        NSString *u = @"Package: com.q\nConffiles:\n /etc/x\nPackage: com.r\nVersion: 7\n\nPackage: com.r\nVersion: 8\n";
        Check(@"only a line after an empty line starts a block", Eq(MSBDPackageFieldIn(u, @"com.r", @"Version"), @"8"), MSBDPackageFieldIn(u, @"com.r", @"Version"));

        // ---- a package on the device for the engine helper's choice (DpkgState.h MSBDPackageOnDisk; 1.4.1 logic test M-1: a Sileo queue) ----
        NSString *q = @"Package: e.inst\nStatus: install ok installed\n\n"
                       "Package: e.unp\nStatus: install ok unpacked\n\n"
                       "Package: e.half\nStatus: install ok half-configured\n\n"
                       "Package: e.trp\nStatus: install ok triggers-pending\n\n"
                       "Package: e.tra\nStatus: install ok triggers-awaited\n\n"
                       "Package: e.cfg\nStatus: deinstall ok config-files\n\n"
                       "Package: e.goes\nStatus: deinstall ok installed\n\n"
                       "Package: e.purge\nStatus: purge ok not-installed\n\n"
                       "Package: e.broken\nStatus: install reinstreq half-installed\n\n"
                       "Package: e.hinst\nStatus: install ok half-installed\n\n"
                       "Package: e.inst2\nVersion: 1\nStatus: install ok installed\nDescription: Status: purge ok not-installed\n\n"
                       "Package: e.held\nStatus: hold ok installed\n\n"
                       "Package: e.heldunp\nStatus: hold ok unpacked\n\n"
                       "Package: e.heldcfg\nStatus: hold ok config-files\n\n"
                       "Package: e.heldbroken\nStatus: hold reinstreq half-installed\n\n"
                       "Package: e.heldnot\nStatus: hold ok not-installed\n\n"
                       "Package: e.unknown\nStatus: unknown ok installed\n\n"
                       "Package: e.holdx\nStatus: holdx ok installed\n\n"
                       "Package: e.heldlast\nStatus: hold ok installed";
        Check(@"installed counts", MSBDPackageOnDisk(q, @"e.inst"), @"NO");
        Check(@"unpacked (same dpkg run) counts", MSBDPackageOnDisk(q, @"e.unp"), @"NO");
        Check(@"half-configured counts", MSBDPackageOnDisk(q, @"e.half"), @"NO");
        Check(@"triggers-pending counts", MSBDPackageOnDisk(q, @"e.trp"), @"NO");
        Check(@"triggers-awaited counts", MSBDPackageOnDisk(q, @"e.tra"), @"NO");
        Check(@"config-files (removed) does not count", !MSBDPackageOnDisk(q, @"e.cfg"), @"YES");
        Check(@"marked for removal does not count", !MSBDPackageOnDisk(q, @"e.goes"), @"YES");
        Check(@"purged does not count", !MSBDPackageOnDisk(q, @"e.purge"), @"YES");
        Check(@"reinstreq does not count", !MSBDPackageOnDisk(q, @"e.broken"), @"YES");
        Check(@"half-installed does not count", !MSBDPackageOnDisk(q, @"e.hinst"), @"YES");
        Check(@"not in the file does not count", !MSBDPackageOnDisk(q, @"e.none"), @"YES");
        Check(@"a name that starts another's does not count for it", !MSBDPackageOnDisk(q, @"e.in"), @"YES");
        Check(@"the field's own line, not one inside another field", MSBDPackageOnDisk(q, @"e.inst2"), @"NO");
        Check(@"nil text does not count", !MSBDPackageOnDisk(nil, @"e.inst"), @"YES");
        // (a held package, apt-mark hold / "ignore updates": installed all the same, 1.4.2)
        Check(@"held and installed counts", MSBDPackageOnDisk(q, @"e.held"), @"NO");
        Check(@"held and unpacked (its own dpkg -i run) counts", MSBDPackageOnDisk(q, @"e.heldunp"), @"NO");
        Check(@"held with only its config files does not count", !MSBDPackageOnDisk(q, @"e.heldcfg"), @"YES");
        Check(@"held and reinstreq does not count", !MSBDPackageOnDisk(q, @"e.heldbroken"), @"YES");
        Check(@"held but not installed does not count", !MSBDPackageOnDisk(q, @"e.heldnot"), @"YES");
        Check(@"want unknown does not count", !MSBDPackageOnDisk(q, @"e.unknown"), @"YES");
        Check(@"a want word that only starts with hold does not count", !MSBDPackageOnDisk(q, @"e.holdx"), @"YES");
        Check(@"held in the file's last block (no line end after it) counts", MSBDPackageOnDisk(q, @"e.heldlast"), @"NO");
        // ---- the cache: read once per change of the file ----
        time_t base = time(NULL) - 1000;
        WriteStatus(@"Package: com.besiktasliseba.macstatusbaranddock\nVersion: 1.3.2\n\nPackage: ellekit\nVersion: 1.1.3\n", base);
        int r0 = gMSBDDpkgReads;
        Check(@"cached: version", Eq(MSBDPackageVersion(@"com.besiktasliseba.macstatusbaranddock"), @"1.3.2"), MSBDPackageVersion(@"com.besiktasliseba.macstatusbaranddock"));
        for (int i = 0; i < 50; i++) MSBDPackageVersion(@"com.besiktasliseba.macstatusbaranddock");
        Check(@"cached: one read for 51 asks", gMSBDDpkgReads - r0 == 1, @(gMSBDDpkgReads - r0));
        Check(@"cached: another package", Eq(MSBDPackageVersion(@"ellekit"), @"1.1.3"), MSBDPackageVersion(@"ellekit"));
        Check(@"cached: a missing package is remembered too", MSBDPackageVersion(@"com.none") == nil && MSBDPackageVersion(@"com.none") == nil && gMSBDDpkgReads - r0 == 3, @(gMSBDDpkgReads - r0));
        WriteStatus(@"Package: com.besiktasliseba.macstatusbaranddock\nVersion: 1.3.3\n\nPackage: ellekit\nVersion: 1.1.3\n", base);   // (same size, same time: not seen)
        Check(@"same size and time: the cache stays", Eq(MSBDPackageVersion(@"com.besiktasliseba.macstatusbaranddock"), @"1.3.2"), MSBDPackageVersion(@"com.besiktasliseba.macstatusbaranddock"));
        WriteStatus(@"Package: com.besiktasliseba.macstatusbaranddock\nVersion: 1.3.3\n\nPackage: ellekit\nVersion: 1.1.3\n", base + 5);   // (a new time)
        Check(@"new time: read again", Eq(MSBDPackageVersion(@"com.besiktasliseba.macstatusbaranddock"), @"1.3.3"), MSBDPackageVersion(@"com.besiktasliseba.macstatusbaranddock"));
        WriteStatus(@"Package: com.besiktasliseba.macstatusbaranddock\nVersion: 1.3.3-2+debug\n\nPackage: ellekit\nVersion: 1.1.3\n", base + 5);   // (same time, other size)
        Check(@"new size: read again", Eq(MSBDPackageVersion(@"com.besiktasliseba.macstatusbaranddock"), @"1.3.3-2+debug"), MSBDPackageVersion(@"com.besiktasliseba.macstatusbaranddock"));
        unlink(MSBD_DPKG_STATUS);
        Check(@"no file: nil", MSBDPackageVersion(@"com.besiktasliseba.macstatusbaranddock") == nil, MSBDPackageVersion(@"com.besiktasliseba.macstatusbaranddock"));

        // ---- the main-thread lookup never reads ----
        WriteStatus(@"Package: com.example.p\nVersion: 2.0\n", base + 10);
        int r1 = gMSBDDpkgReads;
        NSString *first = MSBDPackageVersionNoWait(@"com.example.p");
        Check(@"no wait, cold: nothing yet (read in the background)", first == nil, first);
        for (int i = 0; i < 200 && gMSBDDpkgReads == r1; i++) usleep(10000);
        usleep(50000);
        Check(@"no wait: the background read happened", gMSBDDpkgReads - r1 == 1, @(gMSBDDpkgReads - r1));
        int r2 = gMSBDDpkgReads;
        Check(@"no wait, warm: the answer", Eq(MSBDPackageVersionNoWait(@"com.example.p"), @"2.0"), MSBDPackageVersionNoWait(@"com.example.p"));
        Check(@"no wait, warm: no read", gMSBDDpkgReads == r2, @(gMSBDDpkgReads - r2));
        WriteStatus(@"Package: com.example.p\nVersion: 2.1\n", base + 20);
        NSString *stale = MSBDPackageVersionNoWait(@"com.example.p");
        Check(@"no wait, file changed: the last answer this time", Eq(stale, @"2.0"), stale);
        for (int i = 0; i < 200 && gMSBDDpkgReads == r2; i++) usleep(10000);
        usleep(50000);
        Check(@"no wait, file changed: the new answer next time", Eq(MSBDPackageVersionNoWait(@"com.example.p"), @"2.1"), MSBDPackageVersionNoWait(@"com.example.p"));

        // ---- many threads at once, the file changing under them ----
        __block int bad = 0;
        dispatch_group_t g = dispatch_group_create();
        for (int k = 0; k < 8; k++) dispatch_group_async(g, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            for (int i = 0; i < 400; i++) {
                NSString *v = MSBDPackageVersion(@"com.example.p");
                if (v && ![v hasPrefix:@"2."]) { @synchronized ([NSNull null]) { bad++; } }
                if (k == 0 && i % 50 == 0) WriteStatus([NSString stringWithFormat:@"Package: com.example.p\nVersion: 2.%d\n", i], base + 30 + i);
            }
        });
        dispatch_group_wait(g, DISPATCH_TIME_FOREVER);
        Check(@"threads: only real answers", bad == 0, @(bad));
        printf("test-dpkgcache: %d passed, %d failed\n", gPass, gFail);
        return gFail ? 1 : 0;
    }
}
