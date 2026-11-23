// common/MacPointerStatus.h: MacStatusBar&Dock 1.8.8.2 (GitHub #17): what the Mac pointer is doing, said where the user can see it. The Mac
// pointer is drawn inside pointeruid (statusbar/macpointer/MacPointer.x), which is sandboxed, so when it was not drawn nobody could tell why: Settings
// still said "Mac" and the round pointer showed. Now pointeruid says its state in one Darwin notification state, SpringBoard says which pointeruid
// runs, and Settings > Pointer and Report a Problem put the two together:
//  - com.besiktasliseba.macpointer.status (MacPointer, or our loader in pointeruid when MacPointer is not loaded there; MSBDMPPack below):
//    bits 0-31 the pid of the pointeruid that said it; 32-35 the verdict on another pointer (MSBD_MP_V_*); 36-39 what was seen of it when standing
//    aside (MSBD_MP_SEEN_*); 40-51 the parts of iPadOS's pointer MacPointer did not find on this version (MSBD_MP_MISS_*); 52-55 why the arrow is
//    not shown on the iPad's own display at its last update (MSBD_MP_NOW_*). Posted under the same name when it changes.
//  - com.besiktasliseba.macpointer.process (SpringBoard, StatusBar.x DMMacPointerProcessCheck): the pid of the pointeruid that has run for 5 s or
//    more while a trackpad or mouse is attached; 0 none, or not known. A pid other than the status word's: MacPointer is not running in it.
//  - com.besiktasliseba.macpointer.other.0 to .3 (MacPointer): the file name of the first other library found changing the pointer's classes,
//    32 bytes, for Report a Problem only (never on the Pointer page: other tweaks are not named or blamed there).
//  - com.besiktasliseba.macpointer.restart (Settings > Pointer's Restart Pointer, shown with the not-running and could-not-start notes): our root
//    helper (macsettings/sshtoggled) stops iPadOS's pointer process as our package's install does (SIGKILL); launchd starts it again at once and
//    MacPointer loads into the new one, with no respring. The note carries nothing (MSBDMPRestartTarget, MSBDMPRestartNow).
// Plain C for the words and the reader (our loader in pointeruid is C); the texts in Objective-C (Foundation only). Included by MacPointer.x,
// StatusBar.x, PointerSettings.x, CrashExplain.h and loader/Loader.c; the Mac test: tools/test-pointeraside.sh.
#pragma once
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <notify.h>

#define MSBD_MP_STATUS "com.besiktasliseba.macpointer.status"
#define MSBD_MP_PROCESS "com.besiktasliseba.macpointer.process"
#define MSBD_MP_OTHER_FMT "com.besiktasliseba.macpointer.other.%d"   // (0 to 3: 8 bytes each)
#define MSBD_MP_RESTART "com.besiktasliseba.macpointer.restart"   // (Settings asks our root helper to restart pointeruid)

// The verdict on another pointer. 0: loaded, not looked yet. ALONE: no other library changes pointeruid's pointer classes (the usual case, decided
// once). SHARED: others change them, and nothing of theirs draws a pointer: the Mac pointer draws (until 1.8.8.1.1 it stood aside then). ASIDE: another
// pointer is drawn: the Mac pointer stands aside (two pointers would show). WAITING: others change them, the pointer was not shown yet to look at.
// HELD and LOADFAIL are our loader's in pointeruid: MacPointer not loaded by design (an untested iPadOS without Enable Anyway, or the crash guard's
// safe mode: rows only), or its file did not open.
enum { MSBD_MP_V_NONE = 0, MSBD_MP_V_ALONE = 1, MSBD_MP_V_SHARED = 2, MSBD_MP_V_ASIDE = 3, MSBD_MP_V_WAITING = 4, MSBD_MP_V_HELD = 5, MSBD_MP_V_LOADFAIL = 6 };
// What was seen of the other pointer: a view or layer of the other library's own class that shows something; a layer or view on the pointer that
// shows something and that pointeruid itself does not hold (the usual way: a shape layer added to the pointer view); iPadOS's round pointer hidden
// by someone else than the Mac pointer.
enum { MSBD_MP_SEEN_CLASS = 1, MSBD_MP_SEEN_LAYER = 2, MSBD_MP_SEEN_ROUND_HIDDEN = 4 };
// The parts of iPadOS's pointer MacPointer uses (pointeruid differs per version; a missing part is said, not guessed). CANNOT_DRAW: without these the
// Mac pointer cannot be drawn in place of the round one at all.
enum {
    MSBD_MP_MISS_SHAPEVIEW = 0x001,   // the pointer view class (PUIDPointerShapeView)
    MSBD_MP_MISS_ROOTVC = 0x002,      // the rendering controller class (PUIDPointerRenderingRootViewController)
    MSBD_MP_MISS_CONTROLLER = 0x004,  // the pointer controller class (PUIDPointerController: Pointer Size changes)
    MSBD_MP_MISS_SETSHAPE = 0x008,    // -[PUIDPointerShapeView setPointerShape:animated:completion:]
    MSBD_MP_MISS_SETSTATE = 0x010,    // -[PUIDPointerRenderingRootViewController setPointerState:options:updateHandlerCollection:error:]
    MSBD_MP_MISS_HIDE = 0x020,        // -[PUIDPointerRenderingRootViewController hidePointer]
    MSBD_MP_MISS_ROUNDVIEW = 0x040,   // the round pointer's view in the pointer view (_pointerView)
    MSBD_MP_MISS_SHAPE = 0x080,       // the pointer's shape (_pointerShape or pointerShape)
    MSBD_MP_MISS_MAINVIEW = 0x100,    // the controller's own pointer view (_pointerShapeView)
    MSBD_MP_MISS_VISIBILITY = 0x200,  // the controller's visibility state (_visibilityState)
    MSBD_MP_MISS_ROOTVIEW = 0x400,    // the controller's root view (_pointerRootView)
};
#define MSBD_MP_MISS_CANNOT_DRAW (MSBD_MP_MISS_SHAPEVIEW | MSBD_MP_MISS_ROUNDVIEW)
// Why the arrow is not shown on the iPad's own display at the last update (0: no update yet).
enum { MSBD_MP_NOW_NONE = 0, MSBD_MP_NOW_SHOWN = 1, MSBD_MP_NOW_STYLE = 2, MSBD_MP_NOW_NO_BRIDGE = 3, MSBD_MP_NOW_SYSTEM_HID = 4, MSBD_MP_NOW_VIRTUAL_MAC = 5, MSBD_MP_NOW_ASIDE = 6 };

static inline uint64_t MSBDMPPack(uint32_t pid, unsigned verdict, unsigned seen, unsigned missing, unsigned now) {
    return (uint64_t)pid | ((uint64_t)(verdict & 0xF) << 32) | ((uint64_t)(seen & 0xF) << 36) | ((uint64_t)(missing & 0xFFF) << 40) | ((uint64_t)(now & 0xF) << 52);
}
static inline uint32_t MSBDMPPid(uint64_t w) { return (uint32_t)(w & 0xFFFFFFFFu); }
static inline unsigned MSBDMPVerdict(uint64_t w) { return (unsigned)((w >> 32) & 0xF); }
static inline unsigned MSBDMPSeen(uint64_t w) { return (unsigned)((w >> 36) & 0xF); }
static inline unsigned MSBDMPMissing(uint64_t w) { return (unsigned)((w >> 40) & 0xFFF); }
static inline unsigned MSBDMPNow(uint64_t w) { return (unsigned)((w >> 52) & 0xF); }

// The verdict after one look at the pointer (only while others change the pointer's classes: ALONE and an unset verdict never change). seen: the
// look found another pointer drawn. Standing aside is at once; drawing again only after two clean looks in a row (the looks are 2 s apart), so a
// pointer that flickers between the two is not fought over. *clean counts those looks.
static inline unsigned MSBDMPAsideNext(unsigned verdict, int seen, int *clean) {
    if (verdict != MSBD_MP_V_SHARED && verdict != MSBD_MP_V_ASIDE && verdict != MSBD_MP_V_WAITING) return verdict;
    if (seen) { *clean = 0; return MSBD_MP_V_ASIDE; }
    if (verdict == MSBD_MP_V_ASIDE) { if (++*clean < 2) return MSBD_MP_V_ASIDE; *clean = 0; return MSBD_MP_V_SHARED; }
    *clean = 0;
    return MSBD_MP_V_SHARED;
}
// Whether the Mac pointer draws at all with this verdict (the setting and the bridge decide the rest).
static inline int MSBDMPVerdictDraws(unsigned verdict) { return verdict == MSBD_MP_V_ALONE || verdict == MSBD_MP_V_SHARED; }

// When the look runs (1.8.8.2, after the first device pass on iPadOS 17.5.1: with the other pointer switched off the Mac pointer never came back).
// Until then a look ran only one main-queue turn after a pointer update, at most every 2 s counted from the last try. On 17.5.1 plain moves give
// pointeruid no update (2 in 109 s while the pointer moved), so no look came; and at a window's edge, where the text beam and the round pointer take
// turns, the first update after the 2 s was always the beam's: its look could not look (not a plain pointer), spent the 2 s, and the round pointer's
// own update a few ms later was thrown away, every time. Now:
//  - standing aside, the look runs on a 2 s timer of its own while the pointer is in use (not auto-hidden, not hidden by iPadOS, not in Virtual
//    Mac); stopped at rest, started again by the pointer's next update; never in any other verdict (nothing runs for a pointer no other library
//    changes, ALONE);
//  - waiting or drawing beside another library's hooks, after a pointer update: at once while waiting, else 2 s after the last look that looked; a
//    request inside that time is kept for its end, never dropped;
//  - a look looks only at a plain pointer the user sees whose shape iPadOS has left alone for MSBD_MP_SETTLE s: iPadOS hides its own round pointer
//    while it changes shape (to the text beam and back), and a look in that moment saw "the round pointer hidden" (seen 6 at a window's edge).
#define MSBD_MP_LOOK_EVERY 2.0
#define MSBD_MP_SETTLE 0.5
static inline int MSBDMPAsideTimerWanted(unsigned verdict, int atRest) { return verdict == MSBD_MP_V_ASIDE && !atRest; }
// After an update (WAITING or SHARED): in how many seconds the look runs (0: now). last: when a look last looked (a long time ago: -10 or less).
static inline double MSBDMPAsideLookDelay(unsigned verdict, double now, double last) {
    double wait = last + (verdict == MSBD_MP_V_WAITING ? 0.25 : MSBD_MP_LOOK_EVERY) - now;
    return wait > 0.0 ? wait : 0.0;
}
// Whether a look can look now. plain: the round pointer, no hover, shown (not auto-hidden, not hidden by iPadOS, not in Virtual Mac); shapeAt: when
// iPadOS last changed its shape. -1: look now; 0: not a plain pointer now (its next update asks again); > 0: settling, ask again in that many s.
static inline double MSBDMPAsideCanLook(int plain, double now, double shapeAt) {
    if (!plain) return 0.0;
    double wait = shapeAt + MSBD_MP_SETTLE - now;
    return wait > 0.0 ? wait : -1.0;
}

// SpringBoard's word on the pointer process (MSBD_MP_PROCESS). attached: a trackpad or mouse; mpPid: the status word's pid, mpIsPointer: that pid is a
// running pointeruid; procPid / procAge: the pointeruid found running and for how many seconds (0: none found); said: the word as it stands. A
// pointeruid younger than 5 s keeps the word as it was (our part in it says its pid as it loads: asked again at the next check).
static inline uint64_t MSBDMPProcessWord(int attached, uint32_t mpPid, int mpIsPointer, int procPid, double procAge, uint64_t said) {
    if (!attached) return 0;
    if (mpPid > 0 && mpIsPointer) return mpPid;
    if (procPid <= 0) return 0;
    return procAge >= 5.0 ? (uint64_t)procPid : said;
}

// What Settings > Pointer says under Pointer Style (nothing while all is well, or with Pointer Style iPadOS).
enum { MSBD_MP_NOTE_NONE = 0, MSBD_MP_NOTE_ASIDE, MSBD_MP_NOTE_NOT_RUNNING, MSBD_MP_NOTE_LOAD_FAILED, MSBD_MP_NOTE_CANNOT_DRAW };
static inline int MSBDMPNoteFor(int styleMac, uint64_t status, uint64_t process) {
    if (!styleMac) return MSBD_MP_NOTE_NONE;
    if (process && MSBDMPPid(status) != (uint32_t)process) return MSBD_MP_NOTE_NOT_RUNNING;   // (the pointer process that runs now has said nothing)
    unsigned v = MSBDMPVerdict(status);
    if (v == MSBD_MP_V_LOADFAIL) return MSBD_MP_NOTE_LOAD_FAILED;
    if (v == MSBD_MP_V_HELD || !status) return MSBD_MP_NOTE_NONE;   // (rows only: no Pointer page then; nothing said: nothing to say)
    if (MSBDMPMissing(status) & MSBD_MP_MISS_CANNOT_DRAW) return MSBD_MP_NOTE_CANNOT_DRAW;
    if (v == MSBD_MP_V_ASIDE) return MSBD_MP_NOTE_ASIDE;
    return MSBD_MP_NOTE_NONE;
}
// Restart Pointer: offered with the notes where a new pointer process can help (MacPointer not running in it, or not started in it).
static inline int MSBDMPNoteHasRestart(int note) { return note == MSBD_MP_NOTE_NOT_RUNNING || note == MSBD_MP_NOTE_LOAD_FAILED; }
// The root helper's side: which process it stops (the short name pointeruid and an executable of the system's, never a jailbreak's file under
// /var/jb or /private/preboot, nor one it cannot read the path of), and whether a request is taken (at most one every 5 s: a request repeated or
// sent by anyone else can at most restart the pointer process once in that time).
static inline int MSBDMPRestartTarget(const char *comm, const char *path) {
    if (!comm || strcmp(comm, "pointeruid") != 0 || !path || path[0] != '/') return 0;
    size_t n = strlen(path);
    if (n < 11 || strcmp(path + n - 11, "/pointeruid") != 0) return 0;
    return !strstr(path, "/var/jb/") && !strstr(path, "/private/preboot/");
}
static inline int MSBDMPRestartNow(double now, double *last) {
    if (*last > 0 && now - *last < 5.0 && now >= *last) return 0;
    *last = now;
    return 1;
}
// (1.8.8.2 review) The helper takes a request only while the two words say what Settings offers Restart Pointer for (MacPointer not running in the
// pointer process that runs, or not started there; Pointer Style aside: the row shows only with Mac): the request carries no sender, so one posted
// at any other time, by anyone, is left and the pointer is not restarted.
static inline int MSBDMPRestartWanted(uint64_t status, uint64_t process) { return MSBDMPNoteHasRestart(MSBDMPNoteFor(1, status, process)); }
// The reader (Settings and SpringBoard): one state, looked up and let go.
static inline uint64_t MSBDMPReadState(const char *name) {
    int t = 0; uint64_t v = 0;
    if (notify_register_check(name, &t) != NOTIFY_STATUS_OK) return 0;
    notify_get_state(t, &v);
    notify_cancel(t);
    return v;
}

#ifdef __OBJC__
#import <Foundation/Foundation.h>
// The note in plain words: what happened and what the user can do; another tweak is never named or blamed there.
static inline NSString *MSBDMPNoteText(int note, NSString *osVersion) {
    switch (note) {
        case MSBD_MP_NOTE_ASIDE: return @"The Mac pointer is standing aside: another tweak draws its own pointer, and two pointers would show at once. To use the Mac pointer, turn the other pointer off in its settings, and the Mac pointer comes back by itself. To keep the other pointer, set Pointer Style to iPadOS.";
        case MSBD_MP_NOTE_NOT_RUNNING: return @"The Mac pointer is not running in iPadOS's pointer process (pointeruid), so the round pointer shows. If tweaks are turned off for pointeruid, turn them back on, then tap Restart Pointer. If it still shows round, tap Report a Problem in Settings > Status Bar.";
        case MSBD_MP_NOTE_LOAD_FAILED: return @"The Mac pointer could not start in iPadOS's pointer process, so the round pointer shows. Please tap Report a Problem in Settings > Status Bar.";
        case MSBD_MP_NOTE_CANNOT_DRAW: return [NSString stringWithFormat:@"The Mac pointer does not fit the pointer of iPadOS %@ yet, so the round pointer shows. Please tap Report a Problem in Settings > Status Bar.", osVersion.length ? osVersion : @"on this iPad"];
        default: return nil;
    }
}

// The file name another library was found under, as it may be shown in a report: letters, digits and . _ + - only, at most 31 characters.
static inline NSString *MSBDMPCleanName(const char *bytes, size_t len) {
    char out[32]; size_t n = 0;
    for (size_t i = 0; i < len && bytes[i] && n < sizeof out - 1; i++) {
        char c = bytes[i];
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '.' || c == '_' || c == '+' || c == '-') out[n++] = c;
        else return nil;
    }
    out[n] = 0;
    return n ? [NSString stringWithUTF8String:out] : nil;
}
// Report a Problem's line (after "- Mac pointer: "): the state in a few words, what is missing on this version and, when not shown, why.
static inline NSString *MSBDMPReportWords(int styleMac, uint64_t status, uint64_t process, NSString *other) {
    if (!styleMac) return @"Pointer Style iPadOS";
    NSString *o = other.length ? [NSString stringWithFormat:@": %@", other] : @"";
    NSMutableString *w = [NSMutableString string];
    unsigned v = MSBDMPVerdict(status), seen = MSBDMPSeen(status), miss = MSBDMPMissing(status), now = MSBDMPNow(status);
    if (process && MSBDMPPid(status) != (uint32_t)process) [w appendString:@"not running in pointeruid"];
    else if (!status) [w appendString:process ? @"no word from pointeruid" : @"no word from pointeruid (not seen running)"];
    else switch (v) {
        case MSBD_MP_V_ALONE: [w appendString:@"drawing"]; break;
        case MSBD_MP_V_SHARED: [w appendFormat:@"drawing (other hooks on the pointer draw nothing%@)", o]; break;
        case MSBD_MP_V_ASIDE: [w appendFormat:@"standing aside (another pointer%@; seen:%@%@%@)", o, (seen & MSBD_MP_SEEN_CLASS) ? @" its class" : @"",
                              (seen & MSBD_MP_SEEN_LAYER) ? @" a layer" : @"", (seen & MSBD_MP_SEEN_ROUND_HIDDEN) ? @" round hidden" : @""]; break;
        case MSBD_MP_V_WAITING: [w appendFormat:@"waiting to look (other hooks on the pointer%@)", o]; break;
        case MSBD_MP_V_HELD: [w appendString:@"not loaded (rows only)"]; break;
        case MSBD_MP_V_LOADFAIL: [w appendString:@"did not load in pointeruid"]; break;
        default: [w appendString:@"loaded, no pointer yet"]; break;
    }
    if (miss) {
        static const char *names[] = { "shape view", "controller", "pointer controller", "setPointerShape", "setPointerState", "hidePointer", "round view", "shape", "main view", "visibility", "root view" };
        [w appendString:@"; missing:"];
        for (int i = 0; i < 11; i++) if (miss & (1u << i)) [w appendFormat:@" %s", names[i]];
    }
    static NSString *const nows[] = { nil, nil, @"off in pointeruid", @"no word from SpringBoard", @"hidden by iPadOS", @"hidden in Virtual Mac", @"standing aside" };
    if (status && now < 7 && nows[now]) [w appendFormat:@"; now: %@", nows[now]];
    return w;
}

// The other library's name, from its four states.
static inline NSString *MSBDMPOtherName(void) {
    char bytes[33]; memset(bytes, 0, sizeof bytes);
    for (int i = 0; i < 4; i++) {
        char nm[64]; snprintf(nm, sizeof nm, MSBD_MP_OTHER_FMT, i);
        uint64_t v = MSBDMPReadState(nm);
        memcpy(bytes + i * 8, &v, 8);
    }
    return MSBDMPCleanName(bytes, 32);
}
// Pointer Style from our preferences (every value but "ipados" is the Mac pointer, as SpringBoard's bridge reads it).
static inline int MSBDMPStyleMac(void) {
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("pointerStyle"), CFSTR("com.besiktasliseba.macstatusbar"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    int ipad = v && CFGetTypeID(v) == CFStringGetTypeID() && CFStringCompare((CFStringRef)v, CFSTR("ipados"), 0) == kCFCompareEqualTo;
    if (v) CFRelease(v);
    return !ipad;
}
#endif
