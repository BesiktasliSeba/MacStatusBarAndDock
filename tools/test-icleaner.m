// test-icleaner.m -- Mac test of iCleaner in Finder (common/ICleaner.h, 1.8.5 item 1): what the root helper accepts as a request (an id, the action
// "clean", fresh), iCleaner's printed results turned into the answer line (a clean that worked, iCleaner's own failure, nothing it printed, not
// started, stopped at the time limit), Finder's reading of that line, and the result in a Mac's words. iCleaner's lines are the ones its binary
// prints (official 7.10.0, read 10 Nov: success=, message=, freed=, deleted=, shouldrespring=).
#import <Foundation/Foundation.h>
#include "../common/ICleaner.h"

static int fails = 0, checks = 0;
static void ok(NSString *what, BOOL cond) { checks++; if (!cond) { fails++; printf("FAIL %s\n", what.UTF8String); } }
static void eqs(NSString *what, NSString *got, NSString *want) { checks++; if (!(got == want || [got isEqualToString:want])) { fails++; printf("FAIL %s: got \"%s\", want \"%s\"\n", what.UTF8String, got.UTF8String ?: "(nil)", want.UTF8String ?: "(nil)"); } }
static NSString *const kRID = @"0123456789abcdef0123456789abcdef";
static NSData *D(NSString *s) { return [s dataUsingEncoding:NSUTF8StringEncoding]; }

int main(void) {
    @autoreleasepool {
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        NSString *rid = nil, *why = nil;
        // ---- the request ----
        ok(@"a good request", MSBDICleanRequestFrom(@{@"id": kRID, @"action": @"clean", @"at": @(now - 1)}, now, &rid, &why) && [rid isEqualToString:kRID] && !why);
        ok(@"not a dictionary: not a request", !MSBDICleanRequestFrom(@"clean", now, &rid, &why) && !rid);
        ok(@"a bad id: not a request (nobody to answer)", !MSBDICleanRequestFrom(@{@"id": @"xyz", @"action": @"clean", @"at": @(now)}, now, &rid, &why) && !rid);
        ok(@"another action: refused, answered", !MSBDICleanRequestFrom(@{@"id": kRID, @"action": @"respring", @"at": @(now)}, now, &rid, &why) && [rid isEqualToString:kRID] && why.length);
        ok(@"an extra key (an argument): refused", !MSBDICleanRequestFrom(@{@"id": kRID, @"action": @"clean", @"at": @(now), @"args": @"-restore-togglable-items"}, now, &rid, &why) && rid && why.length);
        ok(@"no time: refused", !MSBDICleanRequestFrom(@{@"id": kRID, @"action": @"clean", @"x": @1}, now, &rid, &why) && rid);
        ok(@"too old (a request left behind): refused", !MSBDICleanRequestFrom(@{@"id": kRID, @"action": @"clean", @"at": @(now - 31)}, now, &rid, &why) && [why containsString:@"too old"]);
        ok(@"from the future: refused", !MSBDICleanRequestFrom(@{@"id": kRID, @"action": @"clean", @"at": @(now + 60)}, now, &rid, &why) && rid);
        ok(@"NaN time: refused", !MSBDICleanRequestFrom(@{@"id": kRID, @"action": @"clean", @"at": @(NAN)}, now, &rid, &why) && rid);
        // ---- iCleaner's results as the answer line ----
        eqs(@"a clean that worked", MSBDICleanAnswerFromOutput(0, D(@"success=true\nfreed=123.4 MB\ndeleted=5678\nshouldrespring=false\n"), NO, 0), @"ok freed=123.4 MB deleted=5678 respring=0");
        eqs(@"  ... with a respring asked", MSBDICleanAnswerFromOutput(0, D(@"success=true\nfreed=1 KB\ndeleted=1\nshouldrespring=true\n"), NO, 0), @"ok freed=1 KB deleted=1 respring=1");
        eqs(@"  ... lines with spaces and CRs", MSBDICleanAnswerFromOutput(0, D(@"  success=true \r\n freed=0 bytes\r\ndeleted=0\r\n"), NO, 0), @"ok freed=0 bytes deleted=0 respring=0");
        eqs(@"  ... nothing said about size or files", MSBDICleanAnswerFromOutput(0, D(@"success=true\n"), NO, 0), @"ok freed=- deleted=-1 respring=0");
        eqs(@"  ... a size too long to be one is left out", MSBDICleanAnswerFromOutput(0, D(@"success=true\nfreed=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\ndeleted=2\n"), NO, 0), @"ok freed=- deleted=2 respring=0");
        eqs(@"  ... a size that tries to add a field is left out", MSBDICleanAnswerFromOutput(0, D(@"success=true\nfreed=1 MB deleted=9 respring=1\ndeleted=2\n"), NO, 0), @"ok freed=- deleted=2 respring=0");
        eqs(@"  ... the first of each line counts", MSBDICleanAnswerFromOutput(0, D(@"success=true\ndeleted=3\ndeleted=99\n"), NO, 0), @"ok freed=- deleted=3 respring=0");
        eqs(@"iCleaner's own failure, in its words", MSBDICleanAnswerFromOutput(0, D(@"success=false\nmessage=Another cleaning is in progress\n"), NO, 256), @"error: Another cleaning is in progress");
        eqs(@"  ... without words", MSBDICleanAnswerFromOutput(0, D(@"success=false\n"), NO, 256), @"error: iCleaner couldn’t clean");
        eqs(@"nothing we know printed (exit 1)", MSBDICleanAnswerFromOutput(0, D(@"usage: iCleaner [-clean ...]\n"), NO, 256), @"error: iCleaner gave no result (exit 1)");
        eqs(@"not started", MSBDICleanAnswerFromOutput(1, nil, NO, -1), @"error: iCleaner couldn’t be started (1)");
        eqs(@"no pipe", MSBDICleanAnswerFromOutput(-1, nil, NO, -1), @"error: iCleaner couldn’t be started (no pipe)");
        eqs(@"stopped at the time limit", MSBDICleanAnswerFromOutput(0, D(@"success=true\n"), YES, 9), @"error: iCleaner didn’t finish in time and was stopped");
        ok(@"a message with newlines stays one line in the answer file", [[[NSString alloc] initWithData:MSBDEjectAnswerData(kRID, MSBDICleanAnswerFromOutput(0, D(@"success=false\nmessage=a\ab\n"), NO, 0)) encoding:NSUTF8StringEncoding] componentsSeparatedByString:@"\n"].count == 3);
        // ---- Finder reads the line ----
        NSString *freed = nil, *err = nil; long long del = 0; BOOL resp = NO;
        ok(@"Finder: a clean that worked", MSBDICleanParseAnswer(@"ok freed=123.4 MB deleted=5678 respring=1", &freed, &del, &resp, &err) && [freed isEqualToString:@"123.4 MB"] && del == 5678 && resp && !err);
        ok(@"Finder: a test run's answer reads the same", MSBDICleanParseAnswer(@"ok freed=2 MB deleted=4 respring=0 test=1", &freed, &del, &resp, &err) && [freed isEqualToString:@"2 MB"] && del == 4 && !resp);
        ok(@"Finder: no size", MSBDICleanParseAnswer(@"ok freed=- deleted=-1 respring=0", &freed, &del, &resp, &err) && !freed && del == -1);
        ok(@"Finder: an error", !MSBDICleanParseAnswer(@"error: iCleaner Pro isn’t installed", &freed, &del, &resp, &err) && [err isEqualToString:@"iCleaner Pro isn’t installed"]);
        ok(@"Finder: something else", !MSBDICleanParseAnswer(@"what", &freed, &del, &resp, &err) && [err isEqualToString:@"what"]);
        ok(@"Finder: nothing", !MSBDICleanParseAnswer(nil, &freed, &del, &resp, &err) && err.length);
        // ---- the words ----
        eqs(@"words: size and files", MSBDICleanResultText(@"123.4 MB", 5678), @"Freed 123.4 MB (5,678 files).");
        eqs(@"words: one file", MSBDICleanResultText(@"4 KB", 1), @"Freed 4 KB (1 file).");
        eqs(@"words: size only", MSBDICleanResultText(@"4 KB", -1), @"Freed 4 KB.");
        eqs(@"words: files only", MSBDICleanResultText(nil, 3), @"Removed 3 files.");
        eqs(@"words: nothing said", MSBDICleanResultText(nil, -1), @"Done.");
        printf("%d checks, %d failed\n", checks, fails);
        return fails ? 1 : 0;
    }
}
