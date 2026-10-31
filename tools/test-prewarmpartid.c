// Mac test of the prewarm block's build ID and start stamp (common/PrewarmPartID.h, 1.7.2 item 8): the ID read from a part's bytes, the stamp the
// part writes read back, and the install's decision -- dasd keeps running only when the stamp is the running dasd's and names the part installed.
#include <stdio.h>
#include <string.h>
#include "../common/PrewarmPartID.h"
static int fails = 0, checks = 0;
#define CHECK(cond, what) do { checks++; if (!(cond)) { fails++; printf("FAIL: %s\n", what); } } while (0)
static MSBDPrewarmRunning Run(int found, const char *name, long long sec, long usec) { MSBDPrewarmRunning r = { found, name, sec, usec }; return r; }
int main(void) {
    char id[32];
    // the ID in a binary's bytes
    const char bin1[] = "\x00\x01junk msbd-dasd-part:0123456789abcdef\x00more";
    CHECK(MSBDPrewarmPartIDIn((const unsigned char *)bin1, sizeof bin1 - 1, id, sizeof id) && !strcmp(id, "0123456789abcdef"), "the ID after the marker, in the middle of a binary");
    const char bin2[] = "msbd-dasd-part:0123456789abcdef";
    CHECK(MSBDPrewarmPartIDIn((const unsigned char *)bin2, sizeof bin2 - 1, id, sizeof id) && !strcmp(id, "0123456789abcdef"), "the ID at the very end of the file");
    const char bin3[] = "msbd-dasd-part:0123456789abcde";
    CHECK(!MSBDPrewarmPartIDIn((const unsigned char *)bin3, sizeof bin3 - 1, id, sizeof id) && !id[0], "a cut ID (15 digits, the file ends): none");
    const char bin4[] = "msbd-dasd-part:0123456789ABCDEF\x00";
    CHECK(!MSBDPrewarmPartIDIn((const unsigned char *)bin4, sizeof bin4 - 1, id, sizeof id), "upper-case digits (not what the build writes): none");
    const char bin5[] = "msbd-dasd-part:0123456789abcdef0\x00";
    CHECK(!MSBDPrewarmPartIDIn((const unsigned char *)bin5, sizeof bin5 - 1, id, sizeof id), "17 hex digits: not an ID");
    const char bin6[] = "no marker at all, an older part (1.7.1 and before)";
    CHECK(!MSBDPrewarmPartIDIn((const unsigned char *)bin6, sizeof bin6 - 1, id, sizeof id), "no marker (a part from 1.7.1 or before): none");
    const char bin7[] = "msbd-dasd-part:zzzz msbd-dasd-part:fedcba9876543210\x00";
    CHECK(MSBDPrewarmPartIDIn((const unsigned char *)bin7, sizeof bin7 - 1, id, sizeof id) && !strcmp(id, "fedcba9876543210"), "a broken marker before the real one: the real one");
    CHECK(!MSBDPrewarmPartIDIn(NULL, 10, id, sizeof id) && !MSBDPrewarmPartIDIn((const unsigned char *)bin1, sizeof bin1 - 1, id, 16), "no bytes, or no room for the ID: none");
    // the stamp, as the part writes it, read back
    char line[96];
    MSBDPrewarmStampFormat(line, sizeof line, 15511, 1793395074LL, 4521, "0123456789abcdef");
    CHECK(!strcmp(line, "15511 1793395074.004521 0123456789abcdef\n"), "the stamp's line: pid, start time (microseconds as six digits), ID");
    MSBDPrewarmStampProc p; char sid[kMSBDPrewarmPartIDLen + 1];
    CHECK(MSBDPrewarmStampParse(line, &p, sid, sizeof sid) && p.pid == 15511 && p.startSec == 1793395074LL && p.startUsec == 4521 && !strcmp(sid, "0123456789abcdef"), "read back: the same pid, start time and ID");
    CHECK(MSBDPrewarmStampParse("15511 1793395074.004521 0123456789abcdef", &p, sid, sizeof sid), "  ... also without the line's end");
    CHECK(!MSBDPrewarmStampParse("", &p, sid, sizeof sid) && !MSBDPrewarmStampParse("15511 1793395074.004521", &p, sid, sizeof sid), "empty, or no ID: not a stamp");
    CHECK(!MSBDPrewarmStampParse("15511 1793395074.004521 0123456789abcde", &p, sid, sizeof sid), "a cut ID (a write cut short): not a stamp");
    CHECK(!MSBDPrewarmStampParse("15511 1793395074.004521 0123456789abcdef extra", &p, sid, sizeof sid), "something after the ID: not a stamp");
    CHECK(!MSBDPrewarmStampParse("0 1793395074.004521 0123456789abcdef", &p, sid, sizeof sid) && !MSBDPrewarmStampParse("-4 1793395074.004521 0123456789abcdef", &p, sid, sizeof sid), "pid 0 or below: not a stamp");
    CHECK(!MSBDPrewarmStampParse("15511 1793395074.1000000 0123456789abcdef", &p, sid, sizeof sid), "microseconds out of range: not a stamp");
    CHECK(!MSBDPrewarmStampParse("15511 1793395074 0123456789abcdef", &p, sid, sizeof sid), "a start time without microseconds: not a stamp");
    CHECK(!MSBDPrewarmStampParse("15511 1793395074.004521 0123456789abcdeg", &p, sid, sizeof sid), "a letter that is not hex in the ID: not a stamp");
    // the install's decision
    const char *s = "15511 1793395074.004521 0123456789abcdef\n";
    CHECK(MSBDPrewarmPartCurrent(s, Run(1, "dasd", 1793395074LL, 4521), "0123456789abcdef"), "the running dasd's stamp, the same build installed: dasd keeps running");
    CHECK(!MSBDPrewarmPartCurrent(s, Run(1, "dasd", 1793395074LL, 4521), "fedcba9876543210"), "another build installed (the part changed, or debug <-> release): restarted");
    CHECK(!MSBDPrewarmPartCurrent(s, Run(1, "dasd", 1793395074LL, 4521), ""), "the part installed has no ID (it is not ours, or damaged): restarted");
    CHECK(!MSBDPrewarmPartCurrent(s, Run(1, "dasd", 1793395074LL, 4521), NULL), "  ... or it could not be read: restarted");
    CHECK(!MSBDPrewarmPartCurrent(s, Run(0, NULL, 0, 0), "0123456789abcdef"), "no process at the stamp's pid (dasd started again since, without our part): restarted");
    CHECK(!MSBDPrewarmPartCurrent(s, Run(1, "locationd", 1793395074LL, 4521), "0123456789abcdef"), "another program at that pid: restarted");
    CHECK(!MSBDPrewarmPartCurrent(s, Run(1, "dasd", 1793399999LL, 4521), "0123456789abcdef"), "a dasd at the same pid that started at another time (the pid used again): restarted");
    CHECK(!MSBDPrewarmPartCurrent(s, Run(1, "dasd", 1793395074LL, 4522), "0123456789abcdef"), "  ... one microsecond apart: restarted");
    CHECK(!MSBDPrewarmPartCurrent(NULL, Run(1, "dasd", 1793395074LL, 4521), "0123456789abcdef"), "no stamp (a first install, a block switched off by its crash guard, a refused write): restarted");
    CHECK(!MSBDPrewarmPartCurrent("garbage", Run(1, "dasd", 1793395074LL, 4521), "0123456789abcdef"), "a damaged stamp: restarted");
    printf("test-prewarmpartid: %d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
