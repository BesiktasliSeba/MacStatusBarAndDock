// LiveActivities.h -- Live Activities in the menu bar (MacStatusBar&Dock 1.8.4 item 1, as macOS 27.3 shows them): the rules in plain C, shared by
// SpringBoard's side (statusbar/LiveActivities.h) and the Mac test (tools/test-liveactivities.sh).
//
// Settings > Status Bar > Live Activities in Menu Bar (MSBD_LA_KEY, on unless switched off) with its page (Now Playing, Timers, Calls, Apps: each
// on unless switched off). A pill each, left of the status icons, in KT's order: calls, timers, Now Playing, then other apps' activities (iPadOS 17
// and later); what does not fit goes into a "+N" pill, whose card stacks them. An activity that ended stays a few minutes, greyed and tappable.
#pragma once
#include <math.h>
#include <stdio.h>
#include <string.h>

#define MSBD_LA_KEY        "liveActivities"             // (com.besiktasliseba.macstatusbar) the switch
#define MSBD_LA_NP_KEY     "liveActivitiesNowPlaying"   // the page's four kinds
#define MSBD_LA_TIMERS_KEY "liveActivitiesTimers"
#define MSBD_LA_CALLS_KEY  "liveActivitiesCalls"
#define MSBD_LA_APPS_KEY   "liveActivitiesApps"

// The kinds, in KT's order (6 Nov): a call, a timer, Now Playing, the rest (other apps' Live Activities).
enum { kMSBDLACall = 0, kMSBDLATimer = 1, kMSBDLANowPlaying = 2, kMSBDLAApp = 3, kMSBDLAKinds = 4 };

// A switch as stored: a boolean, else on (never set: new installs and updaters alike, KT 6 Nov).
static inline int MSBDLASwitchOn(int isBool, int value) { return isBool ? value != 0 : 1; }

// ---- where the parts new to SpringBoard have been seen to work (review 1.8.4 M1, P2-L3) ------------------------------------------------------------
// The exact iPadOS versions where the device pass has seen the timers source (MobileTimer's timer manager of our own, with a real Clock timer: the
// pill, and Pause, Resume and Cancel from its card) and the Now Playing scrubber's seek work (plans/v184.md). Off everywhere else. SpringBoard asks
// them (statusbar/LiveActivities.h) and so does Settings: the Activities page has its Timers row only where timers are listed -- no switch that
// does nothing --, and the search the same (common/OwnPageRows.h). A version goes in as one line, { 17, 5, 1 }, after a clean device run on it.
// Listed after the 1.8.4 device pass (KT's yes, 7 Nov): 17.5.1 (the 17.5) and 18.5 (the A12Z). Not 16.7.7: its MobileTimer has no
// +[MTTimer isActiveTimer:], so the timers source does not run there.
typedef struct { int major, minor, patch; } MSBDLAVersion;
static const MSBDLAVersion kMSBDLATimersChecked[] = { { 17, 5, 1 }, { 18, 5, 0 } };
static const MSBDLAVersion kMSBDLASeekChecked[] = { { 17, 5, 1 }, { 18, 5, 0 } };
static inline int MSBDLAVersionListed(const MSBDLAVersion *list, size_t n, long major, long minor, long patch) {
    for (size_t i = 0; i < n; i++) if (list[i].major == major && list[i].minor == minor && list[i].patch == patch) return 1;
    return 0;
}
static inline int MSBDLATimersListed(long major, long minor, long patch) {
    return MSBDLAVersionListed(kMSBDLATimersChecked, sizeof kMSBDLATimersChecked / sizeof kMSBDLATimersChecked[0], major, minor, patch);
}
static inline int MSBDLASeekListed(long major, long minor, long patch) {
    return MSBDLAVersionListed(kMSBDLASeekChecked, sizeof kMSBDLASeekChecked / sizeof kMSBDLASeekChecked[0], major, minor, patch);
}
// Other apps' Live Activities (iPadOS 17 and later, statusbar/LiveActivityApps.h): the versions where la_probe and a device run have confirmed the
// listing (the pills) and, separately, the hosted live view in the card. EMPTY until then; never 15/16, listed or not. The Activities page has its
// Apps row only where the listing is listed (with its footer), as the Timers row (review 1.8.4 P2-L3: no switch that does nothing).
static const MSBDLAVersion kMSBDLAAppsListChecked[] = { { 0, 0, 0 } };   // (a row that matches nothing)
static const MSBDLAVersion kMSBDLAAppsHostChecked[] = { { 0, 0, 0 } };
static inline int MSBDLAAppsListed(long major, long minor, long patch) {
    return major >= 17 && MSBDLAVersionListed(kMSBDLAAppsListChecked, sizeof kMSBDLAAppsListChecked / sizeof kMSBDLAAppsListChecked[0], major, minor, patch);
}
static inline int MSBDLAAppsHostListed(long major, long minor, long patch) {
    return major >= 17 && MSBDLAVersionListed(kMSBDLAAppsHostChecked, sizeof kMSBDLAAppsHostChecked / sizeof kMSBDLAAppsHostChecked[0], major, minor, patch);
}
// The Status Bar page's words under the switch: only what this iPadOS shows (no timers or other apps' activities named where they are not listed:
// 7 Nov device pass, the 17.5 with neither).
static inline const char *MSBDLAGroupFooter(int timers, int apps) {
    if (timers && apps) return "Calls, timers, music and other Live Activities show next to the status icons, like on a Mac. Tap one to control it.";
    if (timers) return "Calls, timers and music show next to the status icons, like on a Mac. Tap one to control it.";
    if (apps) return "Calls, music and other Live Activities show next to the status icons, like on a Mac. Tap one to control it.";
    return "Calls and music show next to the status icons, like on a Mac. Tap one to control it.";
}

// How long an activity that ended stays in the bar, greyed and tappable (KT: "a few minutes"), in seconds. A Mac keeps them as long as the app asks,
// up to 4 hours; ours is one length for every kind.
#define MSBD_LA_ENDED_KEEP 180.0
// Shown: live (endedAt 0), or ended less than `keep` ago.
static inline int MSBDLAShown(double endedAt, double now, double keep) { return endedAt <= 0.0 || now - endedAt < keep; }
// When an ended one goes (0: live, it does not).
static inline double MSBDLAGoesAt(double endedAt, double keep) { return endedAt > 0.0 ? endedAt + keep : 0.0; }

// ---- the order ---------------------------------------------------------------------------------------------------------------------------------
// By kind (KT's order); in a kind, live ones before ended ones; then by `rank`, lower first -- a timer's seconds left (the next to ring first), a
// call's start (the older call first), an app activity's relevance turned round (-score: the higher score first, as iOS sorts its Lock Screen);
// last, the identifier's order, so the order never flickers between two equal ones.
typedef struct { int kind; int ended; double rank; const char *uid; } MSBDLAOrderKey;
static inline int MSBDLACompare(const MSBDLAOrderKey *a, const MSBDLAOrderKey *b) {
    if (a->kind != b->kind) return a->kind < b->kind ? -1 : 1;
    if ((a->ended != 0) != (b->ended != 0)) return a->ended ? 1 : -1;
    if (a->rank != b->rank) return a->rank < b->rank ? -1 : 1;
    int c = strcmp(a->uid ? a->uid : "", b->uid ? b->uid : "");
    return c < 0 ? -1 : c > 0 ? 1 : 0;
}

// ---- what fits -----------------------------------------------------------------------------------------------------------------------------------
// The pills in order (their widths `w`, `gap` between two) in `room` points. All of them when they fit; else as many as fit with the "+N" pill
// (`plusW` wide) after them, N being the rest -- also none, only "+N", when not even the first fits beside it. Returns how many pills show;
// *plus: how many go into the "+N" pill (0: no "+N" pill). Nothing at all fits: 0 and 0 (no room, no pills).
static inline int MSBDLAFit(const double *w, int n, double room, double gap, double plusW, int *plus) {
    *plus = 0;
    if (n <= 0 || !(room > 0.0)) return 0;
    double all = 0.0;
    for (int i = 0; i < n; i++) all += w[i] + (i ? gap : 0.0);
    if (all <= room) return n;
    if (plusW > room) return 0;
    double used = plusW;
    int shown = 0;
    while (shown < n && used + w[shown] + gap <= room) { used += w[shown] + gap; shown++; }
    *plus = n - shown;
    return shown;
}
// Where the pills start (leading coordinates, x from the bar's leading edge) for a `room` that ends at `end` -- the status icons' start less the gap
// before them -- and starts no closer than `minGap` past the bar's middle (the menus keep the leading half: StatusBar.x titleMaxRight).
static inline double MSBDLARoom(double end, double barWidth, double minGap) {
    double r = end - (barWidth / 2.0 + minGap);
    return r > 0.0 ? r : 0.0;
}

// ---- the texts ---------------------------------------------------------------------------------------------------------------------------------
// A clock text, as iOS's own timer and call show them: "0:05", "4:59", "12:34", "1:02:03". A countdown (up 1) rounds up -- a timer with 4.2 s left
// reads 0:05, as the Clock app's --, a call's time (up 0) rounds down. Negative or not a number: 0.
static inline void MSBDLAClockText(double seconds, int up, char *buf, size_t n) {
    if (!(seconds > 0.0) || !isfinite(seconds)) seconds = 0.0;
    long s = up ? (long)ceil(seconds - 1e-6) : (long)floor(seconds + 1e-6);
    if (s < 0) s = 0;
    long h = s / 3600, m = (s / 60) % 60, sec = s % 60;
    if (h > 0) snprintf(buf, n, "%ld:%02ld:%02ld", h, m, sec);
    else snprintf(buf, n, "%ld:%02ld", m, sec);
}
// The text's shape, every digit a 0 ("12:34" -> "00:00"): the pill is as wide as its shape, so it keeps its width while the digits tick and is laid out
// again only when the shape changes (9:59 -> 10:00).
static inline void MSBDLATextShape(const char *text, char *buf, size_t n) {
    size_t i = 0;
    if (!n) return;
    for (; text && text[i] && i + 1 < n; i++) buf[i] = (text[i] >= '0' && text[i] <= '9') ? '0' : text[i];
    buf[i] = 0;
}

// ---- a timer (MobileTimer's MTTimer, read as it shows outside the Clock app) -----------------------------------------------------------------------
// active: the timer runs or is paused (MTTimer +isActiveTimer:, or the state's word where that is not there); fireIn: seconds until it rings, from its
// fire date (negative: no fire date -- a paused timer has none); remaining: MTTimer's own remaining time (a paused timer's); firing: it rings now.
// Returns 1 running, 2 paused, 3 ringing (the timer's end: shown ended), 0 nothing to show; *left: the seconds the pill counts.
enum { kMSBDLATimerNone = 0, kMSBDLATimerRunning = 1, kMSBDLATimerPaused = 2, kMSBDLATimerRinging = 3 };
static inline int MSBDLATimerState(int active, int firing, double fireIn, double remaining, double *left) {
    *left = 0.0;
    if (firing) return kMSBDLATimerRinging;
    if (!active) return kMSBDLATimerNone;
    if (fireIn >= 0.0) { *left = fireIn; return kMSBDLATimerRunning; }
    if (remaining > 0.0 && isfinite(remaining)) { *left = remaining; return kMSBDLATimerPaused; }
    return kMSBDLATimerNone;
}

// ---- Now Playing ---------------------------------------------------------------------------------------------------------------------------------
// The position now: MediaRemote's elapsed time was `elapsed` when it was stamped `age` seconds ago, running at `rate` (0 paused); never past the
// duration (when known), never below 0.
static inline double MSBDLAElapsedNow(double elapsed, double age, double rate, double duration) {
    if (!isfinite(elapsed) || elapsed < 0.0) elapsed = 0.0;
    double e = elapsed + ((isfinite(age) && age > 0.0 && isfinite(rate)) ? age * rate : 0.0);
    if (e < 0.0) e = 0.0;
    if (duration > 0.0 && isfinite(duration) && e > duration) e = duration;
    return e;
}
// Now Playing's pill: live while the app plays; paused, it counts as ended from the pause on (greyed, gone after MSBD_LA_ENDED_KEEP unless it
// plays again -- a player left paused yesterday must not keep a pill); with no app or nothing to name, there is none. Returns the time it ended
// (0: live; -1: no pill), from `pausedAt` (when it was first seen paused, 0 if never) and `now`.
static inline double MSBDLANowPlayingEnded(int hasApp, int hasTitle, int playing, double pausedAt, double now) {
    if (!hasApp || !hasTitle) return -1.0;
    if (playing) return 0.0;
    return pausedAt > 0.0 ? pausedAt : now;
}

// ---- a call (TelephonyUtilities' TUCall) -------------------------------------------------------------------------------------------------------------
// What the pill says: the call's time once it is connected, "On Hold" while held, else "Calling" (ours, outgoing) or "Incoming". 1: a clock text
// (the caller fills it in from the duration), 0: the word in *word.
static inline int MSBDLACallText(int connected, int held, int incoming, const char **word) {
    if (held) { *word = "On Hold"; return 0; }
    if (connected) { *word = ""; return 1; }
    *word = incoming ? "Incoming" : "Calling";
    return 0;
}

// ---- the "+N" pill's text ---------------------------------------------------------------------------------------------------------------------------
static inline void MSBDLAPlusText(int n, char *buf, size_t size) { snprintf(buf, size, "+%d", n > 0 ? n : 0); }
