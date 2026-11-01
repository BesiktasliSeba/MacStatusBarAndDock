// SSHSwitch.h -- SSH on and off, one logic for every switch of ours (1.7.6 item 1): Settings' SSH row (macsettings/MacSettings.x), the menu bar's
// SSH menu (statusbar/StatusBar.x), the SSH control in Control Center (ccmodule/MSBDSSHModule.m) and, from 1.8.0, our own Control Center's tile.
// One stored value: what the root helper (macsettings/sshtoggled) found OpenSSH to be the last time it looked -- its state file, which it alone
// writes (a root-owned folder). One notification: kMSBDSSHStateNote, posted by the helper after every write. Every switch shows that value and
// reads it again when the notification comes; none keeps a value of its own. Asking goes as it did: the wish into MacSettings' own preference
// (sshWanted: the helper takes WHAT to do only from there), then kMSBDSSHAskNote.
// The state file: its first character is 1 or 0 (what every reader before 1.7.6 reads), then the wish the helper acted on, its result and a count
// of its answers ("1 w1 r1 n12"): a switch that asked tells the answer to its own request (done, failed and why) from an older one.
// Plain C (and CoreFoundation for the wish), so the Mac test (tools/test-sshswitch.sh) runs this very code.
#pragma once
#include <CoreFoundation/CoreFoundation.h>
#include <notify.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#define kMSBDSSHStateFile    "/var/jb/var/lib/sshtoggled-engines/ssh-state"   // (the helper's, root-owned since the 1.0 hardening)
#define kMSBDSSHStateFileOld "/var/jb/var/mobile/.sshtoggle-state"            // (the old one, still written: first character only)
#define kMSBDSSHAskNote      "com.besiktasliseba.sshtoggle.changed"           // a switch asks: "look at sshWanted"
#define kMSBDSSHStateNote    "com.besiktasliseba.sshtoggle.state"             // the helper answered: the state file is new
#define kMSBDSSHDaemon       "/var/jb/usr/sbin/sshd"                          // OpenSSH installed (Settings' row and the control need it)
#define kMSBDSSHWishDomain   CFSTR("com.besiktasliseba.macsettings")
#define kMSBDSSHWishKey      CFSTR("sshWanted")

// The helper's result for the wish it acted on.
enum { kMSBDSSHResultNone = 0, kMSBDSSHResultDone = 1, kMSBDSSHResultNoStart = 2, kMSBDSSHResultNoStop = 3, kMSBDSSHResultNotInstalled = 4 };

typedef struct {
    int on;               // 1 on, 0 off, -1 not known (no state file: no helper has run)
    int wish;             // the wish the helper last acted on: 1, 0, or -1 (none: it only looked, at its start or for an old Settings)
    int result;           // kMSBDSSHResult...
    unsigned long count;  // the helper's answers so far (0: none, or a helper from before 1.7.6)
} MSBDSSHState;

// "1", "0", or "1 w1 r1 n12" (fields in any order after the first character; unknown ones skipped).
static inline MSBDSSHState MSBDSSHParseState(const char *text) {
    MSBDSSHState s = { -1, -1, kMSBDSSHResultNone, 0 };
    if (!text || (text[0] != '0' && text[0] != '1')) return s;
    s.on = text[0] == '1';
    for (const char *p = text + 1; *p; ) {
        while (*p == ' ' || *p == '\t') p++;
        char key = *p;
        if (!key || key == '\n' || key == '\r') break;
        char *end = NULL;
        unsigned long v = strtoul(p + 1, &end, 10);
        if (end == p + 1) { while (*p && *p != ' ') p++; continue; }   // (a field without a number: skipped)
        if (key == 'w' && v <= 1) s.wish = (int)v;
        else if (key == 'r' && v <= kMSBDSSHResultNotInstalled) s.result = (int)v;
        else if (key == 'n') s.count = v;
        p = end;
    }
    return s;
}
// The state file's line for `s` (the helper writes it); the number of characters, as snprintf. No wish acted on (the helper only looked): no "w".
static inline int MSBDSSHFormatState(char *buf, size_t size, MSBDSSHState s) {
    if (s.wish < 0) return snprintf(buf, size, "%d r%d n%lu\n", s.on == 1 ? 1 : 0, s.result, s.count);
    return snprintf(buf, size, "%d w%d r%d n%lu\n", s.on == 1 ? 1 : 0, s.wish ? 1 : 0, s.result, s.count);
}
// The state as the helper last wrote it (the new file, else the old one); on -1 when neither is there.
static inline MSBDSSHState MSBDSSHReadStateFrom(const char *path, const char *oldPath) {
    char line[96] = {0};
    FILE *f = path ? fopen(path, "r") : NULL;
    if (!f && oldPath) f = fopen(oldPath, "r");
    if (f) { if (!fgets(line, sizeof(line), f)) line[0] = 0; fclose(f); }
    return MSBDSSHParseState(line);
}
static inline MSBDSSHState MSBDSSHReadState(void) { return MSBDSSHReadStateFrom(kMSBDSSHStateFile, kMSBDSSHStateFileOld); }

// OpenSSH is installed (the control is offered, Settings' row shown).
static inline int MSBDSSHInstalled(void) { return access(kMSBDSSHDaemon, F_OK) == 0; }

// Asking: the wish first (the helper reads only that), then the request. The calling process's own user (mobile: SpringBoard, Settings).
static inline void MSBDSSHAsk(int on) {
    CFPreferencesSetValue(kMSBDSSHWishKey, on ? kCFBooleanTrue : kCFBooleanFalse, kMSBDSSHWishDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(kMSBDSSHWishDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    notify_post(kMSBDSSHAskNote);
}

// What a state written after a request (`now`) says about that request: asked for `want`, the state was `before` when it was asked.
typedef enum {
    kMSBDSSHWaiting,      // no answer to it yet (an answer to an older request, or none)
    kMSBDSSHDone,         // the helper did it
    kMSBDSSHFailed,       // the helper acted on it and OpenSSH is not as asked: now.result says why
    kMSBDSSHOverruled,    // the helper acted on another wish meanwhile (asked again here or elsewhere): not this switch's to report
} MSBDSSHOutcome;
static inline MSBDSSHOutcome MSBDSSHJudge(MSBDSSHState before, MSBDSSHState now, int want) {
    want = want ? 1 : 0;
    if (now.on < 0 || now.count == 0 || now.count == before.count) return kMSBDSSHWaiting;   // (nothing new written)
    if (now.wish < 0) return now.on == want ? kMSBDSSHDone : kMSBDSSHWaiting;              // (it only looked: the request is still to come)
    if (now.wish != want) return kMSBDSSHOverruled;
    return now.on == want && now.result != kMSBDSSHResultNoStart && now.result != kMSBDSSHResultNoStop ? kMSBDSSHDone : kMSBDSSHFailed;
}
// The reason, in words, for a switch that did not happen (`want`: what was asked); "" when there is none to give.
static inline const char *MSBDSSHReason(int result, int want) {
    switch (result) {
        case kMSBDSSHResultNoStart: return "OpenSSH did not start.";
        case kMSBDSSHResultNoStop: return "OpenSSH did not stop.";
        case kMSBDSSHResultNotInstalled: return "OpenSSH is not installed.";
        default: return want ? "SSH could not be turned on." : "SSH could not be turned off.";
    }
}
static inline const char *MSBDSSHNoAnswerReason(void) { return "The SSH helper did not answer."; }
static inline const char *MSBDSSHNoHelperReason(void) { return "The SSH helper is not running."; }

// The iPad's address, as a Mac's Sharing pane gives it for Remote Login: the Wi-Fi's (en0) IPv4 address, else another network interface's
// (an Ethernet adapter, en1...); loopback, tunnels (utun, ipsec) and cellular (pdp_ip) are no way in. "" when it has none.
static inline int MSBDSSHAddressRank(const char *name) {
    if (!name) return 0;
    if (!strcmp(name, "en0")) return 3;
    if (!strncmp(name, "en", 2)) return 2;
    if (!strncmp(name, "bridge", 6)) return 1;
    return 0;
}
static inline void MSBDSSHAddress(char *buf, size_t size) {
    if (!buf || !size) return;
    buf[0] = 0;
    struct ifaddrs *list = NULL;
    if (getifaddrs(&list) != 0) return;
    int best = 0;
    for (struct ifaddrs *i = list; i; i = i->ifa_next) {
        if (!i->ifa_addr || i->ifa_addr->sa_family != AF_INET || !(i->ifa_flags & IFF_UP) || (i->ifa_flags & IFF_LOOPBACK)) continue;
        int rank = MSBDSSHAddressRank(i->ifa_name);
        if (rank <= best) continue;
        char a[INET_ADDRSTRLEN] = {0};
        if (!inet_ntop(AF_INET, &((struct sockaddr_in *)i->ifa_addr)->sin_addr, a, sizeof(a))) continue;
        if (!strncmp(a, "169.254.", 8)) continue;   // (a link-local address: no network given one)
        snprintf(buf, size, "%s", a);
        best = rank;
    }
    freeifaddrs(list);
}
