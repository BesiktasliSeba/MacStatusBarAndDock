// test-prefsforget.m -- Mac test of common/PrefsForget.h (1.7.8): a preferences domain emptied through cfprefsd, against the Mac's own cfprefsd
// (the same CoreFoundation calls and the same kind of daemon as on iPadOS). First the 1.7.7 finding itself: a domain's plist deleted by hand while
// cfprefsd holds it -- the keys come back to the next reader. Then the removal through cfprefsd: no key listed, none read back, and no file left.
// A scratch domain of its own, named by test-prefsforget.sh (argv[1]), which removes it again at the end -- cfprefsd's late write of the emptied
// domain included: it wrote an empty plist a few seconds after this test ended, and 328 of them were left in ~/Library/Preferences by 7 Nov.
#import <Foundation/Foundation.h>
#include <unistd.h>
#include "../common/PrefsForget.h"
static int fails = 0, checks = 0;
static void Check(const char *what, BOOL ok) { checks++; if (ok) printf("PASS  %s\n", what); else { fails++; printf("FAIL  %s\n", what); } }
static NSString *Read(CFStringRef d, CFStringRef k) {
    CFPreferencesSynchronize(d, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPropertyListRef v = CFPreferencesCopyValue(k, d, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSString *s = v && CFGetTypeID(v) == CFStringGetTypeID() ? [(__bridge NSString *)v copy] : nil;
    if (v) CFRelease(v);
    return s;
}
int main(int argc, char **argv) {
    @autoreleasepool {
        NSString *name = argc > 1 ? @(argv[1]) : [NSString stringWithFormat:@"com.besiktasliseba.msbdtest.prefsforget.%d", getpid()];
        printf("scratch domain: %s\n", name.UTF8String);
        CFStringRef d = (__bridge CFStringRef)name;
        NSString *file = [NSString stringWithFormat:@"%@/Library/Preferences/%@.plist", NSHomeDirectory(), name];
        CFPreferencesSetValue(CFSTR("quitSet"), CFSTR("old"), d, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesSetValue(CFSTR("log"), CFSTR("old"), d, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesSynchronize(d, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        for (int i = 0; i < 50 && access(file.fileSystemRepresentation, F_OK) != 0; i++) usleep(100000);
        Check("set up: the scratch domain is on disk with its two keys", access(file.fileSystemRepresentation, F_OK) == 0 && [Read(d, CFSTR("quitSet")) isEqualToString:@"old"]);
        // the 1.7.7 finding: the file removed by hand, cfprefsd still serves the domain
        unlink(file.fileSystemRepresentation);
        Check("the finding: its file deleted by hand (as the postrm's rm), cfprefsd still hands out the old key", [Read(d, CFSTR("quitSet")) isEqualToString:@"old"]);
        // the removal through cfprefsd
        int left = -1;
        int removed = MSBDForgetPrefsDomain(d, &left);
        Check("emptied through cfprefsd: both keys removed", removed == 2);
        Check("  ... cfprefsd lists no key after it", left == 0);
        Check("  ... a reader gets nothing back", Read(d, CFSTR("quitSet")) == nil && Read(d, CFSTR("log")) == nil);
        usleep(300000);
        Check("  ... and no file is left behind", access(file.fileSystemRepresentation, F_OK) != 0);
        int again = MSBDForgetPrefsDomain(d, &left);
        Check("an empty domain: nothing to remove, nothing left", again == 0 && left == 0);
        unlink(file.fileSystemRepresentation);
    }
    printf("%s: %d/%d\n", fails ? "test-prefsforget FAILED" : "test-prefsforget: all pass", checks - fails, checks);
    return fails ? 1 : 0;
}
