// MacDockActive.h -- is MacDock (the Dock line) really active? (MacStatusBar&Dock, 2026-09-25)
// The Dock's Settings part (DockMagnificationSettings) and its page are loaded by BOTH lines, so the Dock page stays reachable when MacDock is off.
// What MacDock changes in Apple's own pages (Home Screen & Dock) must only happen while MacDock itself runs: its loader is in this process (Choicy /
// iCleaner Pro let it load, and every app is restarted with SpringBoard) and its line is still switched on (MSBDLineEnabled, common/LineSwitch.h,
// which must be included first), and the iPadOS version is tested or "Enable Anyway" is on (VersionGate.h).
#import <mach-o/dyld.h>
#import <string.h>

// Is a line's loader in this process (`suffix` = "/<line>.dylib"), is the line switched on, and may the parts run on this iPadOS version?
static inline BOOL MSBDLineLoadedHere(const char *suffix) {
    size_t sl = strlen(suffix);
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *n = _dyld_get_image_name(i);
        size_t l = n ? strlen(n) : 0;
        if (l >= sl && !strcmp(n + l - sl, suffix)) return YES;
    }
    return NO;
}
static inline BOOL MSBDMacDockActive(void) {
    static int loaded = -1;
    if (loaded < 0) loaded = MSBDLineLoadedHere("/MacDock.dylib") ? 1 : 0;
    return loaded == 1 && MSBDVersionAllowed(0) && MSBDLineEnabled(@"MacDock");   // (on an untested version only with "Enable Anyway")
}
// The same for the MacStatusBar line (everything except the Dock: page dots, app names, ...).
static inline BOOL MSBDMacStatusBarActive(void) {
    static int loaded = -1;
    if (loaded < 0) loaded = MSBDLineLoadedHere("/MacStatusBar.dylib") ? 1 : 0;
    return loaded == 1 && MSBDVersionAllowed(0) && MSBDLineEnabled(@"MacStatusBar");
}
