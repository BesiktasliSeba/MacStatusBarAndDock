// Mac test of the prewarm block's armed record (common/PrewarmArmed.h, 1.7.7 item 5): the line the dasd part writes at every start read back as
// Settings reads it, every state that is not armed, damaged lines, the two files Settings goes by (the record and the quit set's file), and the
// real Windows.plist indexed as the Settings search indexes it (common/TweakIndex.h): the row the page leaves out is the one the search leaves out.
// test-prewarmarmed <the Settings bundle's resources folder>.
#import <Foundation/Foundation.h>
#include <unistd.h>
#include "../common/PrewarmArmed.h"
#import "../common/TweakIndex.h"
static int fails = 0, checks = 0;
#define CHECK(cond, what) do { checks++; if (!(cond)) { fails++; printf("FAIL: %s\n", what); } } while (0)
static int Armed(const char *line) { return MSBDPrewarmArmedParse(line, NULL); }
static void Write(NSString *path, NSString *text) { [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL]; }
int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 2) { fprintf(stderr, "usage: test-prewarmarmed <resources folder>\n"); return 2; }
        // the line dasd writes, read back
        char line[48]; long pid = 0;
        MSBDPrewarmArmedFormat(line, sizeof line, "armed", 82103);
        CHECK(!strcmp(line, "armed 82103\n"), "the record: \"armed <pid>\" and a line end");
        CHECK(MSBDPrewarmArmedParse(line, &pid) && pid == 82103, "  ... read back: armed, dasd's pid");
        const char *notArmed[] = { "guard", "missing", "shape", "closure", "debug" };
        int all = 1;
        for (int i = 0; i < 5; i++) { MSBDPrewarmArmedFormat(line, sizeof line, notArmed[i], 412); pid = 0; all = all && !MSBDPrewarmArmedParse(line, &pid) && pid == 412; }
        CHECK(all, "guard, missing, shape, closure, debug: not armed (the pid still read)");
        CHECK(!Armed(NULL) && !Armed("") && !Armed("\n"), "no record, an empty one: not armed");
        CHECK(!Armed("armed") && !Armed("armed \n") && !Armed("arm"), "a cut line (no pid, half a word): not armed");
        CHECK(!Armed("armed 0\n") && !Armed("armed -3\n") && !Armed("armed x\n"), "a pid that is no pid: not armed");
        CHECK(!Armed("armed 12 more\n") && !Armed("armed 12x\n"), "something after the pid: not armed");
        CHECK(!Armed("ARMED 12\n") && !Armed("armedx 12\n") && !Armed("unarmed 12\n"), "another word: not armed (a state a later build adds too)");
        CHECK(Armed("armed 12") && Armed("armed 12\r\n") && Armed("armed 12 \n"), "the line end, a CR or a trailing space: still the same line");
        // Settings: armed AND the quit set's file there (SpringBoard keeps the set)
        CHECK(MSBDPrewarmAppsShownFrom("armed 7\n", 1), "armed, the quit set's file there: shown");
        CHECK(!MSBDPrewarmAppsShownFrom("armed 7\n", 0), "armed, no quit set's file (stock status bar, Mac Status Bar's old off, no status bar part): not shown");
        CHECK(!MSBDPrewarmAppsShownFrom("guard 7\n", 1) && !MSBDPrewarmAppsShownFrom("closure 7\n", 1), "not armed, the file there: not shown");
        CHECK(!MSBDPrewarmAppsShownFrom(NULL, 1), "no record yet (dasd not started with the part since the install): not shown");
        CHECK(!strcmp(kMSBDPrewarmArmedFile, "/var/jb/var/mobile/Library/Preferences/MacStatusBarAndDock-PrewarmBlockArmed.txt"), "the record sits beside the quit set's file and the stamp (dasd writes that folder on Dopamine and palera1n)");
        // ... read from the files as Settings reads them
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"tpa-%d", getpid()]];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        NSString *rec = [dir stringByAppendingPathComponent:@"armed.txt"], *qs = [dir stringByAppendingPathComponent:@"quitset.plist"];
        CHECK(!MSBDPrewarmAppsShownAt(rec.fileSystemRepresentation, qs.fileSystemRepresentation), "files: neither there: not shown");
        Write(qs, @"<plist/>");
        CHECK(!MSBDPrewarmAppsShownAt(rec.fileSystemRepresentation, qs.fileSystemRepresentation), "files: the quit set's file alone: not shown");
        Write(rec, @"armed 99\n");
        CHECK(MSBDPrewarmAppsShownAt(rec.fileSystemRepresentation, qs.fileSystemRepresentation), "files: armed and the quit set's file: shown");
        Write(rec, @"guard 99\n");
        CHECK(!MSBDPrewarmAppsShownAt(rec.fileSystemRepresentation, qs.fileSystemRepresentation), "files: the next start's guard written over it: not shown");
        Write(rec, @"armed 100\n");
        unlink(qs.fileSystemRepresentation);
        CHECK(!MSBDPrewarmAppsShownAt(rec.fileSystemRepresentation, qs.fileSystemRepresentation), "files: armed, the quit set's file gone: not shown");
        Write(qs, @"<plist/>"); Write(rec, @"");
        CHECK(!MSBDPrewarmAppsShownAt(rec.fileSystemRepresentation, qs.fileSystemRepresentation), "files: an empty record: not shown");
        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
        // the real Windows.plist as the Settings search indexes it (common/TweakSpotlight.h MTSBaseConfig's own pages): Prewarm Apps is the page
        // MAC_WINDOWS's row PREWARM_APPS -- the ids MTSShownRows leaves out -- and nothing else goes with it
        MTIConfig *c = [MTIConfig new];
        c.languages = @[@"en-US"]; c.cfVersion = 1953.1; c.maxPerPane = 400; c.maxTotal = 6000;
        c.own = @[@{@"id": @"MAC_WINDOWS", @"title": @"Windows & Multitasking", @"bundle": @(argv[1]), @"plist": @"Windows", @"icon": @"windows"}];
        NSArray<MTIEntry *> *index = MTIBuild(c);
        NSArray<MTIEntry *> *found = MTIMatch(index, @"Prewarm", 0);
        CHECK(found.count == 1 && [found.firstObject.title isEqualToString:@"Prewarm Apps"] && [found.firstObject.uid isEqualToString:@"msbd-tweaksetting:root=MAC_WINDOWS#PREWARM_APPS"],
              "the index of Windows.plist: \"Prewarm\" finds Prewarm Apps, prefs:root=MAC_WINDOWS#PREWARM_APPS");
        NSArray<MTIEntry *> *shown = MTIWithout(index, @"MAC_WINDOWS", @"PREWARM_APPS");
        CHECK(index.count > 5 && shown.count == index.count - 1 && MTIMatch(shown, @"Prewarm", 0).count == 0 && MTIMatch(shown, @"Prewarm Apps", 0).count == 0,
              "  ... without the row the page leaves out: not found, and every other row still there");
        CHECK(MTIMatch(shown, @"Mac Switcher", 0).count == 1 && MTIMatch(MTIWithout(index, @"MAC_DESKTOP", @"PREWARM_APPS"), @"Prewarm", 0).count == 1,
              "  ... another page's row of that id is not this one: kept");
    }
    printf("%s: %d of %d checks passed\n", fails ? "FAIL" : "PASS", checks - fails, checks);
    return fails ? 1 : 0;
}
