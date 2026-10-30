// Mac test of common/ProcSample.h (run by test-procsample.sh): the per-process %CPU maths behind the Activity Monitor feature, on fixed numbers,
// and the process names read as UTF-8 that is never refused (checked against CoreFoundation's own UTF-8 reading, the one NSString uses).
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <CoreFoundation/CoreFoundation.h>
#include "../common/ProcSample.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

// CoreFoundation reads these bytes as UTF-8 (what +[NSString stringWithUTF8String:] does; NULL there = a nil name on the device).
static int CFTakes(const char *bytes, size_t len) {
    CFStringRef s = CFStringCreateWithBytes(NULL, (const UInt8 *)bytes, (CFIndex)len, kCFStringEncodingUTF8, false);
    if (s) CFRelease(s);
    return s != NULL;
}
// Both read by CoreFoundation as the same string. (Not "the same bytes": CoreFoundation itself takes one stray byte, 0xA9, as U+FFFD.)
static int CFSame(const char *a, size_t al, const char *b, size_t bl) {
    CFStringRef x = CFStringCreateWithBytes(NULL, (const UInt8 *)a, (CFIndex)al, kCFStringEncodingUTF8, false);
    CFStringRef y = CFStringCreateWithBytes(NULL, (const UInt8 *)b, (CFIndex)bl, kCFStringEncodingUTF8, false);
    int same = x && y && CFEqual(x, y);
    if (x) CFRelease(x);
    if (y) CFRelease(y);
    return same;
}
static const char *Name(const char *in, size_t len) {   // (MSBDProcNameUTF8 into a buffer of the size the device uses)
    static char out[3 * 1024 + 1];
    MSBDProcNameUTF8(in, len, out, sizeof out);
    return out;
}

int main(void) {
    const uint64_t MS = 1000000ull, SEC = 1000000000ull;
    // A process that used 50 ms of CPU over a 1 s refresh = 5% of one core.
    double p = MSBDProcCPUPercent(1000 * MS, 1050 * MS, SEC);
    CHECK(p > 4.99 && p < 5.01, "50 ms over 1 s = 5%% (%.3f)", p);
    // One core fully busy for the whole interval = 100%.
    CHECK(MSBDProcCPUPercent(0, SEC, SEC) == 100.0, "a full core = 100%%");
    // Two cores at once over the interval = 200%, like Activity Monitor.
    CHECK(MSBDProcCPUPercent(0, 2 * SEC, SEC) == 200.0, "two cores = 200%%");
    // An idle process: no CPU time used.
    CHECK(MSBDProcCPUPercent(500 * MS, 500 * MS, SEC) == 0.0, "no CPU used = 0%%");
    // No time between samples -> not a measurement.
    CHECK(MSBDProcCPUPercent(0, 10 * MS, 0) < 0.0, "no interval: no value");
    // The pid was reused by a new process (counter went back) -> not a measurement.
    CHECK(MSBDProcCPUPercent(900 * MS, 10 * MS, SEC) < 0.0, "counter went back: no value");

    CHECK(MSBDProcCPUTime(30 * MS, 20 * MS) == 50 * MS, "cpu time = user + system");

    char b[16];
    MSBDFormatPercent(4.3, b, sizeof b);   CHECK(!strcmp(b, "4.3"), "4.3 -> %s", b);
    MSBDFormatPercent(0.0, b, sizeof b);   CHECK(!strcmp(b, "0.0"), "0.0 -> %s", b);
    MSBDFormatPercent(127.0, b, sizeof b); CHECK(!strcmp(b, "127.0"), "127.0 -> %s", b);
    MSBDFormatPercent(-1.0, b, sizeof b);  CHECK(!strcmp(b, "-"), "no value -> %s", b);

    // timebase: on Apple silicon ticks are already nanoseconds (1/1); a 125/3 timebase (older devices) scales.
    CHECK(MSBDMachTicksToNs(1000, 1, 1) == 1000, "1/1 timebase: ticks are ns");
    CHECK(MSBDMachTicksToNs(3, 125, 3) == 125, "125/3 timebase scales");
    CHECK(MSBDMachTicksToNs(1000, 0, 0) == 0, "no timebase: 0, never a divide by zero");

    // ---- process names: always UTF-8 NSString takes ----
    CHECK(!strcmp(Name("SpringBoard", 11), "SpringBoard"), "plain ASCII stays");
    CHECK(!strcmp(Name("Caf\xC3\xA9 Notes", 11), "Caf\xC3\xA9 Notes"), "an accent (2 bytes) stays");
    CHECK(!strcmp(Name("\xE6\x97\xA5\xE6\x9C\xAC\xE8\xAA\x9E", 9), "\xE6\x97\xA5\xE6\x9C\xAC\xE8\xAA\x9E"), "CJK (3 bytes each) stays");
    CHECK(!strcmp(Name("Smile \xF0\x9F\x98\x80", 10), "Smile \xF0\x9F\x98\x80"), "an emoji (4 bytes) stays");
    // p_comm: 16 bytes of a longer name -- five 3-byte characters and the first byte of the sixth, or the first two of it: the cut one is left out
    const char *jp = "\xE6\x97\xA5\xE6\x9C\xAC\xE8\xAA\x9E\xE3\x81\xAE\xE3\x82\xA2\xE3\x83\x97\xE3\x83\xAA";   // (7 characters, 21 bytes)
    char comm[17]; memcpy(comm, jp, 16); comm[16] = 0;
    CHECK(!CFTakes(comm, 16), "the cut p_comm is what NSString refuses (the crash's input)");
    CHECK(!strcmp(Name(comm, 16), "\xE6\x97\xA5\xE6\x9C\xAC\xE8\xAA\x9E\xE3\x81\xAE\xE3\x82\xA2"), "p_comm cut after 1 byte of a character: the 5 whole ones");
    memcpy(comm, "x", 1); memcpy(comm + 1, jp, 15); comm[16] = 0;   // (x + five whole characters: the cut falls between two)
    CHECK(!strcmp(Name(comm, 16), comm), "16 bytes ending on a whole character: all of it");
    memcpy(comm, "xy", 2); memcpy(comm + 2, jp, 14); comm[16] = 0;   // (xy + four whole characters + 2 bytes of the fifth)
    CHECK(!strcmp(Name(comm, 16), "xy\xE6\x97\xA5\xE6\x9C\xAC\xE8\xAA\x9E\xE3\x81\xAE"), "p_comm cut after 2 bytes of a character: left out");
    // stray bytes in the middle: one U+FFFD each broken sequence, the rest kept
    CHECK(!strcmp(Name("a\xFF" "b", 3), "a\xEF\xBF\xBD" "b"), "a byte that is never UTF-8 -> U+FFFD");
    CHECK(!strcmp(Name("a\xC3(b", 4), "a\xEF\xBF\xBD(b"), "a character's start with no continuation -> U+FFFD, the next byte kept");
    CHECK(!strcmp(Name("\xE6\x97(", 3), "\xEF\xBF\xBD("), "a broken 3-byte character -> one U+FFFD");
    CHECK(!strcmp(Name("\xC0\x80", 2), "\xEF\xBF\xBD\xEF\xBF\xBD"), "an overlong NUL -> replaced");
    CHECK(!strcmp(Name("\xED\xA0\x80", 3), "\xEF\xBF\xBD\xEF\xBF\xBD\xEF\xBF\xBD"), "a UTF-16 surrogate -> replaced");
    CHECK(!strcmp(Name("\xF4\x90\x80\x80", 4), "\xEF\xBF\xBD\xEF\xBF\xBD\xEF\xBF\xBD\xEF\xBF\xBD"), "past U+10FFFF -> replaced");
    CHECK(!strcmp(Name("abcdef", 3), "abc"), "only len bytes are read");
    CHECK(!strcmp(Name("ab\0cd", 5), "ab"), "a NUL ends the name");
    CHECK(MSBDProcNameUTF8("", 0, comm, sizeof comm) == 0 && comm[0] == 0, "an empty name: nothing (the device's \"(pid)\")");
    CHECK(MSBDProcNameUTF8(NULL, 5, comm, sizeof comm) == 0 && comm[0] == 0, "no bytes at all: nothing");
    char small[4];
    CHECK(MSBDProcNameUTF8("\xE6\x97\xA5\xE6\x9C\xAC", 6, small, sizeof small) == 3 && !strcmp(small, "\xE6\x97\xA5"), "a small buffer ends before a character, never inside one");
    CHECK(MSBDProcNameUTF8("abc", 3, small, 0) == 0, "no room at all: nothing written");
    char canary[5] = { 'x', 'x', 'x', 'C', 0 };   // (3 bytes given: a 3-byte character and its NUL do not fit; byte 3 is not ours)
    CHECK(MSBDProcNameUTF8("\xE6\x97\xA5", 3, canary, 3) == 0 && canary[0] == 0 && canary[3] == 'C', "never a byte past the buffer");
    canary[3] = 'C';
    CHECK(MSBDProcNameUTF8("\xFF", 1, canary, 3) == 0 && canary[3] == 'C', "never a byte past the buffer (U+FFFD)");
    // fuzz: random bytes, mostly not ASCII, any length up to 40 -- every result is UTF-8 CoreFoundation takes, never longer than 3x; input that
    // CoreFoundation takes as it is comes back as the same string; a second pass changes nothing
    srand(1700);
    int fuzzBad = 0, fuzzKept = 0, fuzzWell = 0;
    for (int n = 0; n < 200000; n++) {
        char in[41]; size_t len = (size_t)(rand() % 41);
        for (size_t j = 0; j < len; j++) {
            int r = rand() % 8;
            in[j] = r < 3 ? (char)(0x20 + rand() % 0x5F) : r < 5 ? (char)(0x80 + rand() % 0x40) : (char)(0xC0 + rand() % 0x40);
            if (rand() % 6 == 0 && j + 3 < len) { memcpy(in + j, "\xE3\x81\xAE", 3); j += 2; }   // (whole characters too, for the cuts around them)
        }
        char out[3 * 41 + 1]; size_t o = MSBDProcNameUTF8(in, len, out, sizeof out);
        if (o != strlen(out) || o > 3 * len || !CFTakes(out, o)) { fuzzBad++; continue; }
        if (CFTakes(in, len)) { fuzzWell++; if (!CFSame(in, len, out, o)) fuzzBad++; else fuzzKept++; }
        char again[3 * 123 + 1]; MSBDProcNameUTF8(out, o, again, sizeof again);
        if (strcmp(again, out)) fuzzBad++;
    }
    CHECK(fuzzBad == 0, "fuzz: %d of 200000 names not UTF-8 CoreFoundation takes, changed when well-formed, or changed again", fuzzBad);
    CHECK(fuzzWell > 1000 && fuzzKept == fuzzWell, "fuzz: every well-formed name kept as it is (%d of %d)", fuzzKept, fuzzWell);

    printf("test-procsample: %d passed, %d failed\n", passes, fails);
    return fails ? 1 : 0;
}
