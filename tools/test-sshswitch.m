// Mac test of common/SSHSwitch.h (run by test-sshswitch.sh): the state line the root helper writes and every switch reads, what an answer says
// about a request (done, failed and why, another wish since, still waiting), the reasons in words, and which address is the iPad's.
#import <Foundation/Foundation.h>
#include "../common/SSHSwitch.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

static MSBDSSHState S(int on, int wish, int result, unsigned long count) { MSBDSSHState s = { on, wish, result, count }; return s; }
static BOOL Same(MSBDSSHState a, MSBDSSHState b) { return a.on == b.on && a.wish == b.wish && a.result == b.result && a.count == b.count; }

int main(void) {
    @autoreleasepool {
        // the line: written by the helper, read back the same; the old one-character files still read
        char line[96];
        MSBDSSHState w = S(1, 1, kMSBDSSHResultDone, 12);
        int n = MSBDSSHFormatState(line, sizeof(line), w);
        CHECK(n > 0 && !strcmp(line, "1 w1 r1 n12\n"), "the helper's line for on, asked on, done, 12th answer (%s)", line);
        CHECK(Same(MSBDSSHParseState(line), w), "  ... read back the same");
        CHECK(line[0] == '1', "  ... its first character is what readers before 1.7.6 read (1 = on)");
        MSBDSSHFormatState(line, sizeof(line), S(0, 1, kMSBDSSHResultNoStart, 3));
        CHECK(Same(MSBDSSHParseState(line), S(0, 1, kMSBDSSHResultNoStart, 3)), "off after asking on, OpenSSH did not start: read back the same (%s)", line);
        MSBDSSHFormatState(line, sizeof(line), S(1, -1, kMSBDSSHResultNone, 1));
        CHECK(!strcmp(line, "1 r0 n1\n") && Same(MSBDSSHParseState(line), S(1, -1, 0, 1)), "the helper only looked (its start): no wish in the line, none read back (%s)", line);
        CHECK(Same(MSBDSSHParseState(line), S(1, -1, 0, 1)) && MSBDSSHJudge(S(1, 0, 1, 0), MSBDSSHParseState(line), 0) == kMSBDSSHWaiting,
              "  ... never taken for an answer to a request it did not act on (asked off, found on: still waiting)");
        CHECK(Same(MSBDSSHParseState("1"), S(1, -1, 0, 0)) && Same(MSBDSSHParseState("0"), S(0, -1, 0, 0)), "an old helper's file (one character): the state, no wish, no count");
        CHECK(Same(MSBDSSHParseState("0\n"), S(0, -1, 0, 0)), "  ... with a line end");
        CHECK(MSBDSSHParseState("").on == -1 && MSBDSSHParseState(NULL).on == -1 && MSBDSSHParseState("x1").on == -1, "nothing, or not a state: not known");
        CHECK(Same(MSBDSSHParseState("1 n7 w0 r3"), S(1, 0, kMSBDSSHResultNoStop, 7)), "fields in another order");
        CHECK(Same(MSBDSSHParseState("1 w1 zz r1 q5 n9"), S(1, 1, 1, 9)), "unknown fields skipped");
        CHECK(MSBDSSHParseState("1 w7 r9").wish == -1 && MSBDSSHParseState("1 w7 r9").result == 0, "a wish or a result out of range: none");
        // the files: the new one first, else the old one, else none
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"sshswitch-%d", getpid()]];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *nw = [dir stringByAppendingPathComponent:@"ssh-state"], *old = [dir stringByAppendingPathComponent:@".sshtoggle-state"];
        CHECK(MSBDSSHReadStateFrom(nw.UTF8String, old.UTF8String).on == -1, "no file: not known");
        [@"0" writeToFile:old atomically:YES encoding:NSUTF8StringEncoding error:nil];
        CHECK(MSBDSSHReadStateFrom(nw.UTF8String, old.UTF8String).on == 0, "only the old file: read");
        [@"1 w1 r1 n4\n" writeToFile:nw atomically:YES encoding:NSUTF8StringEncoding error:nil];
        CHECK(Same(MSBDSSHReadStateFrom(nw.UTF8String, old.UTF8String), S(1, 1, 1, 4)), "the new file first");
        [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
        // what an answer says about a request (asked for `want`, the state `before` when asked)
        MSBDSSHState before = S(1, -1, 0, 4);
        CHECK(MSBDSSHJudge(before, before, 0) == kMSBDSSHWaiting, "nothing new written: waiting");
        CHECK(MSBDSSHJudge(before, S(0, 0, kMSBDSSHResultDone, 5), 0) == kMSBDSSHDone, "asked off, the helper turned it off: done");
        CHECK(MSBDSSHJudge(before, S(1, 0, kMSBDSSHResultNoStop, 5), 0) == kMSBDSSHFailed, "asked off, OpenSSH did not stop: failed");
        CHECK(MSBDSSHJudge(S(0, -1, 0, 4), S(0, 1, kMSBDSSHResultNoStart, 5), 1) == kMSBDSSHFailed, "asked on, OpenSSH did not start: failed");
        CHECK(MSBDSSHJudge(S(0, -1, 0, 4), S(0, 1, kMSBDSSHResultNotInstalled, 5), 1) == kMSBDSSHFailed, "asked on, OpenSSH not installed: failed");
        CHECK(MSBDSSHJudge(before, S(1, 1, kMSBDSSHResultDone, 5), 0) == kMSBDSSHOverruled, "the helper acted on another wish meanwhile (asked on again): not this switch's to report");
        CHECK(MSBDSSHJudge(before, S(0, -1, 0, 5), 0) == kMSBDSSHDone, "the helper only looked (its start) and found it as asked: done");
        CHECK(MSBDSSHJudge(before, S(1, -1, 0, 5), 0) == kMSBDSSHWaiting, "  ... and found it not as asked yet: still waiting for the request");
        CHECK(MSBDSSHJudge(before, S(0, 0, 1, 0), 0) == kMSBDSSHWaiting, "an old helper's file (no count): never taken for an answer");
        CHECK(MSBDSSHJudge(before, S(-1, -1, 0, 0), 0) == kMSBDSSHWaiting, "no state: waiting");
        CHECK(MSBDSSHJudge(S(1, -1, 0, 0), S(0, 0, 1, 1), 0) == kMSBDSSHDone, "the first answer of a new helper (count 1): done");
        // the reasons in words
        CHECK(!strcmp(MSBDSSHReason(kMSBDSSHResultNoStart, 1), "OpenSSH did not start.") && !strcmp(MSBDSSHReason(kMSBDSSHResultNoStop, 0), "OpenSSH did not stop."),
              "the helper's results in words");
        CHECK(!strcmp(MSBDSSHReason(kMSBDSSHResultNotInstalled, 1), "OpenSSH is not installed."), "not installed in words");
        CHECK(!strcmp(MSBDSSHReason(kMSBDSSHResultDone, 1), "SSH could not be turned on.") && !strcmp(MSBDSSHReason(kMSBDSSHResultNone, 0), "SSH could not be turned off."),
              "no result to name: what did not happen");
        CHECK(strlen(MSBDSSHNoAnswerReason()) > 0 && strlen(MSBDSSHNoHelperReason()) > 0, "no answer, no helper: a reason each");
        // the address: Wi-Fi first, then another network interface, never loopback, tunnels or cellular
        CHECK(MSBDSSHAddressRank("en0") > MSBDSSHAddressRank("en1") && MSBDSSHAddressRank("en1") > MSBDSSHAddressRank("bridge100"), "Wi-Fi (en0) before Ethernet (en1) before a bridge");
        CHECK(!MSBDSSHAddressRank("lo0") && !MSBDSSHAddressRank("utun3") && !MSBDSSHAddressRank("ipsec0") && !MSBDSSHAddressRank("pdp_ip0") && !MSBDSSHAddressRank(NULL),
              "loopback, tunnels, cellular: no way in");
        char addr[INET_ADDRSTRLEN + 8]; MSBDSSHAddress(addr, sizeof(addr));
        CHECK(!addr[0] || (strncmp(addr, "127.", 4) && strncmp(addr, "169.254.", 8) && inet_addr(addr) != INADDR_NONE), "this Mac's address, if any, is an IPv4 address that is no loopback or link-local one (%s)", addr[0] ? addr : "none");
        char tiny[4] = "xyz"; MSBDSSHAddress(tiny, 0); CHECK(!strcmp(tiny, "xyz"), "no room: nothing written");
    }
    printf("test-sshswitch: %d passed, %d failed\n", passes, fails);
    return fails ? 1 : 0;
}
