// Mac test of Prewarm Apps' default (common/PrewarmDefault.h, 1.7.7, KT): never set, OFF on a 2 GB iPad and ON with more; a boolean anyone stored
// stays; anything else counts as never set. The same rule SpringBoard (the quit set's file for dasd) and Settings (the switch) read. Built twice
// by test-prewarmdefault.sh: as a release build, and as a debug build whose RAM override is read from a scratch file (argv[1]).
#include <unistd.h>
#ifdef FAKE_RAM_FILE
#define MSBD_PREWARM_FAKE_RAM FAKE_RAM_FILE
#endif
#include "../common/PrewarmDefault.h"
static int fails = 0, checks = 0;
#define CHECK(cond, what) do { checks++; if (!(cond)) { fails++; printf("FAIL: %s\n", what); } } while (0)
static const unsigned long long GiB = 1073741824ULL;
int main(int argc, char **argv) {
    // the line: 2 GB iPads off, 3 GB and more on (hw.memsize is a little under the RAM fitted: the 4 GB 17.5 reports 4166696960)
    CHECK(!MSBDPrewarmAppsDefault(2 * GiB) && !MSBDPrewarmAppsDefault(2080000000ULL) && !MSBDPrewarmAppsDefault(1 * GiB), "2 GB (at most 2 GiB reported): off");
    CHECK(MSBDPrewarmAppsDefault(3 * GiB) && MSBDPrewarmAppsDefault(3 * GiB * 97 / 100), "3 GB (about 3.1e9 reported): on");
    CHECK(MSBDPrewarmAppsDefault(4166696960ULL) && MSBDPrewarmAppsDefault(6 * GiB) && MSBDPrewarmAppsDefault(16 * GiB), "4 GB (the 17.5's 4166696960), 6 GB, 16 GB: on");
    CHECK(!MSBDPrewarmAppsDefault(kMSBDPrewarmLowRAMBytes - 1) && MSBDPrewarmAppsDefault(kMSBDPrewarmLowRAMBytes) && kMSBDPrewarmLowRAMBytes == 2500000000ULL, "the line at 2.5e9 bytes, between 2 GiB and 3 GB");
    CHECK(MSBDPrewarmAppsDefault(0), "RAM unknown: on (the default before 1.7.7)");
    // what is stored, as both sides read it
    CFNumberRef one = CFNumberCreate(NULL, kCFNumberIntType, &(int){1}), zero = CFNumberCreate(NULL, kCFNumberIntType, &(int){0});
    CFStringRef yes = CFSTR("YES");
    CHECK(MSBDPrewarmAppsStored(NULL) == -1, "nothing stored: never set");
    CHECK(MSBDPrewarmAppsStored(kCFBooleanTrue) == 1 && MSBDPrewarmAppsStored(kCFBooleanFalse) == 0, "a boolean: its value");
    CHECK(MSBDPrewarmAppsStored(one) == -1 && MSBDPrewarmAppsStored(zero) == -1 && MSBDPrewarmAppsStored(yes) == -1, "a number or a string: never set (as SpringBoard has read it since 1.7.5)");
    // the rule
    CHECK(!MSBDPrewarmAppsOn(-1, 2 * GiB) && MSBDPrewarmAppsOn(-1, 4166696960ULL), "never set: off with 2 GB, on with 4 GB");
    CHECK(MSBDPrewarmAppsOn(1, 2 * GiB) && MSBDPrewarmAppsOn(1, 4166696960ULL), "switched on by anyone: on, 2 GB too (a value set is kept)");
    CHECK(!MSBDPrewarmAppsOn(0, 2 * GiB) && !MSBDPrewarmAppsOn(0, 4166696960ULL), "switched off: off, 4 GB too");
    CHECK(MSBDPrewarmAppsOn(MSBDPrewarmAppsStored(one), 2 * GiB) == 0 && MSBDPrewarmAppsOn(MSBDPrewarmAppsStored(yes), 6 * GiB) == 1, "  ... a value that is no boolean: the default for the RAM");
    CHECK(MSBDPrewarmAppsOn(-1, 0) == 1, "never set, RAM unknown: on");
    // the RAM read: hw.memsize, or (debug builds) the override
    unsigned long long mem = 0; size_t len = sizeof mem; sysctlbyname("hw.memsize", &mem, &len, NULL, 0);
#if DEBUG
    const char *fake = argc > 1 ? argv[1] : NULL;
    if (fake) unlink(fake);
    CHECK(mem > 0 && MSBDPrewarmRAM() == mem, "debug build, no override: this machine's hw.memsize");
    FILE *f = fake ? fopen(fake, "w") : NULL; if (f) { fputs("2\n", f); fclose(f); }
    CHECK(MSBDPrewarmRAM() == 2 * GiB && !MSBDPrewarmAppsOn(-1, MSBDPrewarmRAM()), "debug build, the override says 2: 2 GiB, Prewarm Apps off unless set");
    f = fake ? fopen(fake, "w") : NULL; if (f) { fputs("4\n", f); fclose(f); }
    CHECK(MSBDPrewarmRAM() == 4 * GiB && MSBDPrewarmAppsOn(-1, MSBDPrewarmRAM()), "  ... says 4: on");
    f = fake ? fopen(fake, "w") : NULL; if (f) { fputs("junk\n", f); fclose(f); }
    CHECK(MSBDPrewarmRAM() == mem, "  ... says nothing readable: the real RAM");
    if (fake) unlink(fake);
#else
    (void)argc; (void)argv;
    CHECK(mem > 0 && MSBDPrewarmRAM() == mem, "release build: hw.memsize, nothing else");
#endif
    CFRelease(one); CFRelease(zero);
    printf("%s: %d of %d checks passed\n", fails ? "FAIL" : "PASS", checks - fails, checks);
    return fails ? 1 : 0;
}
