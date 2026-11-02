// PrefsForget.h -- a preferences domain emptied through cfprefsd (1.7.8): every key it lists removed with the preferences calls themselves, then
// read back. Deleting a domain's plist file leaves cfprefsd's own copy: the next reader -- a reinstall of ours -- gets the old keys back as if the
// file had never gone (1.7.7 fix round: the postrm's rm of the prewarm domains). Emptied this way, what is left on disk is at most an empty domain
// (the Mac's cfprefsd deletes the file; iPadOS's writes an empty one, M1 15.6.1), which an rm can then take away with nothing cached behind it.
// Used by the root helper's removal, in a child that runs as mobile (macsettings/sshtoggled/main.m ForgetPrewarmPrefs); plain CoreFoundation, so
// the Mac test (tools/test-prefsforget.m) runs this very code against the Mac's own cfprefsd.
#pragma once
#include <CoreFoundation/CoreFoundation.h>

// Returns how many keys were removed; *left (optional): how many the domain still lists after it (0 when it worked).
static inline int MSBDForgetPrefsDomain(CFStringRef domain, int *left) {
    int removed = 0;
    CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFArrayRef keys = CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (keys && CFArrayGetCount(keys)) {
        CFPreferencesSetMultiple(NULL, keys, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        removed = (int)CFArrayGetCount(keys);
    }
    if (keys) CFRelease(keys);
    CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (left) {
        CFArrayRef after = CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        *left = after ? (int)CFArrayGetCount(after) : 0;
        if (after) CFRelease(after);
    }
    return removed;
}
