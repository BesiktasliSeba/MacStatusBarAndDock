// Mac test of Keep Tailspin Off's rules (common/TailspinGuard.h, 1.7.9, KT): the default (on with 2 GB, off with more or unknown RAM), the value
// stored, whether perfdiagsselfenabled reads the key (its binary scanned for the key and the domain), what the helper does with Apple's
// preference (write our false, leave, take ours away), when it turns off a tailspin turned on by perfdiagsselfenabled, and when Settings shows the
// switch (the helper's state file). Built by test-tailspinguard.sh; argv[1] is a scratch folder.
#include "../common/TailspinGuard.h"
#include <unistd.h>
static int fails = 0, checks = 0;
#define CHECK(cond, what) do { checks++; if (!(cond)) { fails++; printf("FAIL: %s\n", what); } } while (0)
static const unsigned long long GiB = 1073741824ULL;

static int scan(const char *bytes, size_t len) { return MSBDPDSESupportsBytes((const unsigned char *)bytes, len); }
static void writeFile(const char *path, const void *bytes, size_t len) { FILE *f = fopen(path, "wb"); if (f) { fwrite(bytes, 1, len, f); fclose(f); } }
static void writeState(const char *path, CFTypeRef supported) {
    CFMutableDictionaryRef d = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (supported) CFDictionarySetValue(d, CFSTR("supported"), supported);
    CFDataRef data = CFPropertyListCreateData(NULL, d, kCFPropertyListBinaryFormat_v1_0, 0, NULL);
    writeFile(path, CFDataGetBytePtr(data), (size_t)CFDataGetLength(data));
    CFRelease(data); CFRelease(d);
}

int main(int argc, char **argv) {
    const char *dir = argc > 1 ? argv[1] : "/tmp";
    char path[1024];
    // the default: the Prewarm Apps line (2.5e9 bytes of hw.memsize) the other way round
    CHECK(MSBDTailspinOffDefault(2 * GiB) && MSBDTailspinOffDefault(2080000000ULL) && MSBDTailspinOffDefault(1 * GiB), "2 GB (at most 2 GiB reported): on");
    CHECK(!MSBDTailspinOffDefault(3 * GiB * 97 / 100) && !MSBDTailspinOffDefault(4166696960ULL) && !MSBDTailspinOffDefault(16 * GiB), "3 GB, the 4 GB 17.5 (4166696960), 16 GB: off");
    CHECK(MSBDTailspinOffDefault(kMSBDPrewarmLowRAMBytes - 1) && !MSBDTailspinOffDefault(kMSBDPrewarmLowRAMBytes), "the line at Prewarm Apps' 2.5e9 bytes");
    CHECK(!MSBDTailspinOffDefault(0), "RAM unknown: off (iPadOS's own behaviour left alone)");
    // the stored value
    CFNumberRef one = CFNumberCreate(NULL, kCFNumberIntType, &(int){1});
    CHECK(MSBDTailspinOffStored(NULL) == -1 && MSBDTailspinOffStored(one) == -1 && MSBDTailspinOffStored(CFSTR("YES")) == -1, "nothing, a number, a string: never set");
    CHECK(MSBDTailspinOffStored(kCFBooleanTrue) == 1 && MSBDTailspinOffStored(kCFBooleanFalse) == 0, "a boolean: its value");
    CHECK(MSBDTailspinOffOn(-1, 2 * GiB) == 1 && MSBDTailspinOffOn(-1, 4166696960ULL) == 0 && MSBDTailspinOffOn(-1, 0) == 0, "never set: the RAM's default");
    CHECK(MSBDTailspinOffOn(0, 2 * GiB) == 0 && MSBDTailspinOffOn(1, 6 * GiB) == 1, "set by the user: kept, on a 2 GB iPad and a 6 GB one alike");
    // perfdiagsselfenabled's binary: the key and the domain, each as a whole string (a NUL before and after)
    static const char good[] = "\0junk\0PDSEPrefHTThirdPartyKillSwitch\0PDSEPrefAllowEnableTailspin\0HTProfile\0com.apple.da\0com.apple.hangtracer\0";
    CHECK(scan(good, sizeof good) == 1, "the key and the domain: read there");
    static const char noKey[] = "\0PDSEPrefHTThirdPartyKillSwitch\0com.apple.da\0";
    CHECK(scan(noKey, sizeof noKey) == 0, "no PDSEPrefAllowEnableTailspin (another iPadOS): not read");
    static const char noDomain[] = "\0PDSEPrefAllowEnableTailspin\0com.apple.hangtracer\0";
    CHECK(scan(noDomain, sizeof noDomain) == 0, "no com.apple.da: not read");
    static const char longer[] = "\0PDSEPrefAllowEnableTailspinX\0com.apple.dasd\0com.apple.da.tasking_changed\0";
    CHECK(scan(longer, sizeof longer) == 0, "only longer names that start with them (com.apple.dasd, com.apple.da.tasking_changed): not read");
    static const char inside[] = "\0xPDSEPrefAllowEnableTailspin\0xcom.apple.da\0";
    CHECK(scan(inside, sizeof inside) == 0, "names inside other strings: not read");
    static const char atStart[] = "PDSEPrefAllowEnableTailspin\0com.apple.da";   // (the domain's NUL is the array's own)
    CHECK(scan(atStart, sizeof atStart) == 1 && scan(atStart, sizeof atStart - 1) == 0, "at the very start and end of the file; cut before the end NUL: not read");
    CHECK(scan("", 0) == 0, "an empty file: not read");
    snprintf(path, sizeof path, "%s/pdse", dir); writeFile(path, good, sizeof good);
    CHECK(MSBDPDSESupportsAt(path) == 1, "the file: read there");
    snprintf(path, sizeof path, "%s/pdse-old", dir); writeFile(path, noKey, sizeof noKey);
    CHECK(MSBDPDSESupportsAt(path) == 0 && MSBDPDSESupportsAt("/nonexistent/perfdiagsselfenabled") == 0 && MSBDPDSESupportsAt(NULL) == 0, "a file without the key, no file: not read");
    // Apple's preference as read
    CHECK(MSBDPDSEAllowRead(kCFBooleanFalse) == 0 && MSBDPDSEAllowRead(kCFBooleanTrue) == 1 && MSBDPDSEAllowRead(NULL) == -1 && MSBDPDSEAllowRead(one) == -1, "Apple's value: false / true / none / not a boolean");
    // the helper's decision: supported, want off, Apple's value, owned -> the action and owned after
    int own = -1;
    CHECK(MSBDTailspinDecide(1, 1, -1, 0, &own) == kMSBDTGWriteFalse && own == 1, "on, nothing there: write our false (ours)");
    CHECK(MSBDTailspinDecide(1, 1, 1, 0, &own) == kMSBDTGWriteFalse && own == 1, "on, a true there: the switch is the say -- our false");
    CHECK(MSBDTailspinDecide(1, 1, 0, 1, &own) == kMSBDTGLeave && own == 1, "on, our false there: nothing");
    CHECK(MSBDTailspinDecide(1, 1, 0, 0, &own) == kMSBDTGLeave && own == 0, "on, someone else's false: left, still theirs");
    CHECK(MSBDTailspinDecide(1, 1, -1, 1, &own) == kMSBDTGWriteFalse && own == 1, "on, ours taken away (tasking): written again");
    CHECK(MSBDTailspinDecide(1, 0, 0, 1, &own) == kMSBDTGRemove && own == 0, "off, our false there: taken away");
    CHECK(MSBDTailspinDecide(1, 0, 0, 0, &own) == kMSBDTGLeave && own == 0, "off, someone else's false: left");
    CHECK(MSBDTailspinDecide(1, 0, 1, 1, &own) == kMSBDTGLeave && own == 0, "off, a true written over ours since: left, no longer ours");
    CHECK(MSBDTailspinDecide(1, 0, -1, 0, &own) == kMSBDTGLeave && own == 0, "off, nothing there: nothing");
    CHECK(MSBDTailspinDecide(0, 1, 0, 1, &own) == kMSBDTGRemove && own == 0, "not read any more (an iPadOS update), our false there: taken away");
    CHECK(MSBDTailspinDecide(0, 1, -1, 0, &own) == kMSBDTGLeave && own == 0, "not read, nothing of ours: nothing, switch or not");
    CHECK(MSBDTailspinDecide(1, 1, -1, 0, NULL) == kMSBDTGWriteFalse, "  ... no owned-after asked: the same action");
    // a tailspin turned on by perfdiagsselfenabled (its modifier) is turned off at once; one turned on by hand is not
    CHECK(MSBDTailspinOnBySelfEnablement(1, "perfdiagsselfenabled [38726]") && MSBDTailspinOnBySelfEnablement(1, "perfdiagsselfenabled"), "on by perfdiagsselfenabled: turned off");
    CHECK(!MSBDTailspinOnBySelfEnablement(0, "perfdiagsselfenabled [38726]") && !MSBDTailspinOnBySelfEnablement(-1, "perfdiagsselfenabled [1]"), "off or unknown: nothing to turn off");
    CHECK(!MSBDTailspinOnBySelfEnablement(1, "tailspin CLI [59475]") && !MSBDTailspinOnBySelfEnablement(1, "perfdiagsselfenabledX [1]") && !MSBDTailspinOnBySelfEnablement(1, NULL) && !MSBDTailspinOnBySelfEnablement(1, ""),
          "on by hand (the tool, a profile), another name, no modifier: left alone");
    // Settings shows the switch by the helper's state file
    snprintf(path, sizeof path, "%s/state.plist", dir);
    writeState(path, kCFBooleanTrue);  CHECK(MSBDTailspinRowShownAt(path) == 1, "state: supported -- the switch shown");
    writeState(path, kCFBooleanFalse); CHECK(MSBDTailspinRowShownAt(path) == 0, "state: not supported -- left out");
    writeState(path, NULL);            CHECK(MSBDTailspinRowShownAt(path) == 0, "state without the answer -- left out");
    writeFile(path, "garbage", 7);     CHECK(MSBDTailspinRowShownAt(path) == 0, "a damaged state file -- left out");
    unlink(path);                      CHECK(MSBDTailspinRowShownAt(path) == 0, "no state file (the helper has not looked yet) -- left out");
    CFRelease(one);
    printf("test-tailspinguard: %d/%d checks pass\n", checks - fails, checks);
    return fails ? 1 : 0;
}
