// AppleMultitaskingTable.h -- where Apple keeps its multitasking settings, per iPadOS version (1.6.0, KT 28 Oct: "Apple's multitasking settings
// merged in" on our Windows & Multitasking page). Plain Foundation (Mac test tools/test-applemultitasking.sh); the Settings side is
// common/AppleMultitasking.h. One entry per place Apple has them, of one of these kinds:
//   MSAMRows  Apple's rows shown on our page, live and still Apple's, the way our Pointer and Keyboard pages show Apple's (common/NativeEmbed.h):
//             Apple's page whose rows they are (made, never shown), the rows it must have (else the entry is left out and Apple's row stays), and
//             the page of Apple's that leads there with the row(s) taken out of it while ours shows them (each setting in one place). A link into
//             them (Settings' own search results, prefs:root=... links) goes to our page instead.
//   MSAMLink  where Apple's page has no rows to show (a SwiftUI page): a row on our page that opens it by Apple's own link, through Settings' own
//             URL handler, selecting Apple's row in Settings' main list -- which must be there; its title and icon are the row's. Apple's row stays.
//   MSAMPage  the same where Settings has no URL handler of its own to call (iPadOS 18): Apple's page itself, shown from ours the way Settings
//             shows a preference bundle's page. Apple's row stays.
// Read on the devices with the Settings probe (MSBDSettingsProbe.m: embed, rootids, classes, methods):
//   16.7.7 20H330 (iPad 2): General > Picture in Picture = PSGPiPController (AUTO_PIP group, ALLOW_PIP = com.apple.springboard SBAllowAutoPIP);
//     General > Gestures = PSGGesturesController (MULTITASKING_GESTURES group, SBUseSystemGestures; CORNER_GESTURES group,
//     ALLOW_FINGER_TO_SWIPE_FROM_CORNER; CORNER_SWIPES group, BOTTOM_LEFT_CORNER_SWIPE, BOTTOM_RIGHT_CORNER_SWIPE); General's rows PiP_SPEC and
//     GESTURES lead there. Home Screen & Multitasking (DBSHomeScreenPadListController, HomeScreenPad.plist) holds only Stage Manager among them (a
//     MULTITASKING - HEADER group and the CONTINUOUS-EXPOSE row, both requiredCapabilitiesOr DeviceSupports(SingleDisplay)EnhancedMultitasking), so
//     it is there only where Settings itself sees Stage Manager -- never with TrollPad, whose Stage Manager only SpringBoard knows; and Apple's
//     switch on that page reads and writes SBChamoisWindowingEnabled while SpringBoard with TrollPad acts on TPSBChamoisWindowingEnabled. Not taken
//     (no iPad here has Stage Manager natively on 16 to check it on). DBSPiPController (Allow Multiple Apps, Gestures) is in the framework but no
//     page of 16 leads to it.
//   15.6.1 19G82 (M1, with the probe's embed and dump): the same two pages of General as on 16 -- PSGPiPController (AUTO_PIP group,
//     ALLOW_PIP "Start PiP Automatically") and PSGGesturesController (MULTITASKING_GESTURES group with SBUseSystemGestures "Four & Five Finger
//     Swipe"; CORNER_GESTURES, Allow Finger to Swipe From Corner; CORNER_SWIPES, BOTTOM_LEFT_CORNER_SWIPE, BOTTOM_RIGHT_CORNER_SWIPE), General's
//     rows PiP_SPEC and GESTURES leading there. Home Screen & Dock (DBSHomeScreenPadListController, 15 rows as our page would get them) has no
//     multitasking rows at all: Home Screen (Use Large App Icons), Newly Downloaded Apps, Notification Badges, and a group whose identifier is
//     MULTITASKING_DOCK but whose rows are the Dock's (Show App Library in Dock, Show Suggested and Recent Apps -- on our Dock page already).
//     "Allow Multiple Apps" is gone since iPadOS 15. So 15's entries are 16's.
//   17.5 and 18.5 (A12Z agent, round 4; and its preference bundle capture): Multitasking & Gestures is MultitaskingAndGesturesSettings, a
//     PSViewController of SwiftUI section models without specifiers, in /System/Library/PreferenceBundles/MultitaskingAndGesturesSettings.bundle
//     (com.apple.MultitaskingAndGesturesSettings, principal class MultitaskingAndGesturesSettings). 17.5: a row of Settings' main list with the
//     bundle's identifier, so prefs:root=com.apple.MultitaskingAndGesturesSettings selects it, and -[PreferencesAppController processURL:animated:
//     fromSearch:withCompletion:] is Settings' own handler (TweakSearchCheck.h). 18.5: an item of the SwiftUI sidebar, and the app has no
//     PreferencesAppController (its delegate is SettingsApp.SettingsApplicationDelegate).
#pragma once
#import <Foundation/Foundation.h>
#import <unistd.h>

typedef enum { MSAMRows = 0, MSAMLink = 1, MSAMPage = 2 } MSAMKind;
typedef struct {
    int os;                 // iPadOS major version
    MSAMKind kind;
    const char *page;       // Apple's page: whose rows our page shows (a PSListController), or the page a link row opens
    const char *bundle;     // where that class comes from when it is not loaded yet (NULL: Settings' own frameworks)
    const char *expect;     // MSAMRows: its rows that must be there, comma-separated (all of them, or the entry is left out)
    const char *only;       // MSAMRows: the rows taken, comma-separated, in Apple's order (NULL: every row of the page)
    const char *title;      // MSAMRows: our header over its first group (NULL: Apple's own); link rows: the title where Apple's own can't be read
    const char *from;       // MSAMRows: Apple's page that leads there
    const char *fromRows;   // MSAMRows: that page's rows taken out while ours shows them (the link row, or the rows themselves on that page)
    const char *aliases;    // MSAMRows: other row ids a link to Apple's page uses for these rows (Settings' own search index: on 16.7.7 its
                            // "Gestures" result is prefs:root=General#Multitasking_Gesture_Switch, a row of no page 16 shows)
    const char *link;       // MSAMLink: Apple's own link to the page, opened by Settings' own URL handler
    const char *linkRow;    // MSAMLink: Apple's row in Settings' main list that link selects (it must be there)
    int debugOnly;          // (debug builds: only while /tmp/msb-amlink-test exists -- MSAMSourcesFor)
} MSAMSource;

#define MSAM_MG_BUNDLE "/System/Library/PreferenceBundles/MultitaskingAndGesturesSettings.bundle"
static const MSAMSource kMSAMSources[] = {
    {.os = 15, .kind = MSAMRows, .page = "PSGPiPController", .expect = "AUTO_PIP,ALLOW_PIP", .title = "Picture in Picture",
     .from = "PSGGeneralController", .fromRows = "PiP_SPEC"},
    {.os = 15, .kind = MSAMRows, .page = "PSGGesturesController", .expect = "MULTITASKING_GESTURES,SBUseSystemGestures",
     .from = "PSGGeneralController", .fromRows = "GESTURES", .aliases = "Multitasking_Gesture_Switch"},
    {.os = 16, .kind = MSAMRows, .page = "PSGPiPController", .expect = "AUTO_PIP,ALLOW_PIP", .title = "Picture in Picture",
     .from = "PSGGeneralController", .fromRows = "PiP_SPEC"},
    {.os = 16, .kind = MSAMRows, .page = "PSGGesturesController", .expect = "MULTITASKING_GESTURES,SBUseSystemGestures",
     .from = "PSGGeneralController", .fromRows = "GESTURES", .aliases = "Multitasking_Gesture_Switch"},
    {.os = 17, .kind = MSAMLink, .page = "MultitaskingAndGesturesSettings", .bundle = MSAM_MG_BUNDLE, .title = "Multitasking & Gestures",
     .link = "prefs:root=com.apple.MultitaskingAndGesturesSettings", .linkRow = "com.apple.MultitaskingAndGesturesSettings"},
    {.os = 18, .kind = MSAMPage, .page = "MultitaskingAndGesturesSettings", .bundle = MSAM_MG_BUNDLE, .title = "Multitasking & Gestures"},
#if DEBUG
    // (debug builds, while /tmp/msb-amlink-test exists: the 17 and 18 kinds of row on 16, where they can be checked on the iPad 2 -- a link to Apple's
    //  Home Screen & Multitasking row of the main list, and Apple's Picture in Picture page shown from ours)
    {.os = 16, .kind = MSAMLink, .page = "DBSHomeScreenPadListController", .title = "Home Screen & Multitasking", .link = "prefs:root=HOME_SCREEN_DOCK",
     .linkRow = "HOME_SCREEN_DOCK", .debugOnly = 1},
    {.os = 16, .kind = MSAMPage, .page = "PSGPiPController", .title = "Picture in Picture (Apple's page)", .debugOnly = 1},
#endif
};
#define MSAM_SOURCE_COUNT ((int)(sizeof(kMSAMSources) / sizeof(kMSAMSources[0])))

static inline NSArray<NSString *> *MSAMList(const char *csv) {
    if (!csv || !*csv) return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *p in [@(csv) componentsSeparatedByString:@","]) if (p.length) [out addObject:p];
    return out;
}
// The entries for this iPadOS version, in the order our page shows them.
static inline NSArray<NSNumber *> *MSAMSourcesFor(int os) {
    NSMutableArray *out = [NSMutableArray array];
#if DEBUG
    BOOL test = access("/tmp/msb-amlink-test", F_OK) == 0;
#else
    BOOL test = NO;
#endif
    for (int i = 0; i < MSAM_SOURCE_COUNT; i++) if (kMSAMSources[i].os == os && (!kMSAMSources[i].debugOnly || test)) [out addObject:@(i)];
    return out;
}
// The entry of this version that takes `rowID` out of Apple's page `pageClass` (-1: none).
static inline int MSAMSourceTaking(int os, NSString *pageClass, NSString *rowID) {
    if (!pageClass.length || !rowID.length) return -1;
    for (NSNumber *n in MSAMSourcesFor(os)) {
        const MSAMSource *s = &kMSAMSources[n.intValue];
        if (s->kind != MSAMRows || !s->from) continue;   // (a link row takes nothing: Apple's row stays)
        if ([pageClass isEqualToString:@(s->from)] && ([MSAMList(s->fromRows) containsObject:rowID] || [MSAMList(s->aliases) containsObject:rowID])) return n.intValue;
    }
    return -1;
}
// A link into Apple's page `pageClass` (its "path", as Settings hands it to the page: "GESTURES", "GESTURES/BOTTOM_LEFT_CORNER_SWIPE", a row after a
// "#"): the entry whose rows it leads to (-1: not ours), and in *row the row of that entry to show on our page -- the one the link names when it is
// one of the entry's rows (in `rowsOfEntry`, the rows our page has from it), else the entry's first row.
static inline int MSAMRedirect(int os, NSString *pageClass, NSString *path, NSArray<NSString *> *(^rowsOfEntry)(int entry), NSString **row) {
    if (row) *row = nil;
    if (![path isKindOfClass:[NSString class]] || !path.length) return -1;
    NSString *clean = [[path stringByReplacingOccurrencesOfString:@"%23" withString:@"#"] stringByReplacingOccurrencesOfString:@"#" withString:@"/"];
    NSArray *parts = [clean componentsSeparatedByString:@"/"];
    int entry = MSAMSourceTaking(os, pageClass, parts.firstObject);
    if (entry < 0) return -1;
    NSArray *rows = rowsOfEntry ? rowsOfEntry(entry) : nil;
    NSString *want = nil;
    for (NSString *p in [parts reverseObjectEnumerator]) {
        NSString *d = [p stringByRemovingPercentEncoding] ?: p;
        if ([rows containsObject:d]) { want = d; break; }
    }
    if (!want) want = rows.firstObject ?: MSAMList(kMSAMSources[entry].expect).firstObject;
    if (row) *row = want;
    return entry;
}
