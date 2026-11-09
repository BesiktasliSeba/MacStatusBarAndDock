// test-liveactivities.c: Live Activities in the menu bar, the plain C (common/LiveActivities.h, 1.8.4 item 1): the switches as stored, how long an
// ended one stays, KT's order, what fits beside the "+N" pill, the clock texts and their shapes, a timer read from MTTimer's parts, Now Playing's
// position and its pause, a call's words.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "../common/LiveActivities.h"
static int fails = 0;
static void check(const char *what, int ok) { printf("%s  %s\n", ok ? "PASS" : "FAIL", what); if (!ok) fails = 1; }
static int near(double a, double b) { return fabs(a - b) < 0.001; }
static int cmp(const void *a, const void *b) { return MSBDLACompare((const MSBDLAOrderKey *)a, (const MSBDLAOrderKey *)b); }
int main(void) {
    // ---- the switches: MSBDLASwitchOn(stored as a boolean, its value)
    check("Live Activities in Menu Bar and each kind never set (a new install, an update): on", MSBDLASwitchOn(0, 0) == 1);
    check("  ... switched off: off; switched on: on", MSBDLASwitchOn(1, 0) == 0 && MSBDLASwitchOn(1, 1) == 1);
    check("the keys: liveActivities and its four kinds", !strcmp(MSBD_LA_KEY, "liveActivities") && !strcmp(MSBD_LA_NP_KEY, "liveActivitiesNowPlaying")
          && !strcmp(MSBD_LA_TIMERS_KEY, "liveActivitiesTimers") && !strcmp(MSBD_LA_CALLS_KEY, "liveActivitiesCalls") && !strcmp(MSBD_LA_APPS_KEY, "liveActivitiesApps"));

    // ---- an ended one: shown for MSBD_LA_ENDED_KEEP (3 minutes), then gone
    check("a live one is shown, and never goes by itself", MSBDLAShown(0, 1e9, MSBD_LA_ENDED_KEEP) && MSBDLAGoesAt(0, MSBD_LA_ENDED_KEEP) == 0.0);
    check("ended at 100: shown at 100 and 279.9, gone at 280 (3 minutes)", MSBD_LA_ENDED_KEEP == 180.0 && MSBDLAShown(100, 100, 180) && MSBDLAShown(100, 279.9, 180)
          && !MSBDLAShown(100, 280, 180) && near(MSBDLAGoesAt(100, 180), 280));

    // ---- KT's order: call, timer, Now Playing, the rest; live before ended in a kind; then the rank
    MSBDLAOrderKey k[] = {
        { kMSBDLAApp, 0, -0.2, "app:b" }, { kMSBDLANowPlaying, 0, 0, "np" }, { kMSBDLATimer, 0, 300, "timer:2" }, { kMSBDLAApp, 0, -0.9, "app:a" },
        { kMSBDLACall, 1, 10, "call:old" }, { kMSBDLATimer, 0, 42, "timer:1" }, { kMSBDLACall, 0, 50, "call:new" }, { kMSBDLAApp, 0, -0.9, "app:0" },
    };
    qsort(k, sizeof k / sizeof k[0], sizeof k[0], cmp);
    const char *want[] = { "call:new", "call:old", "timer:1", "timer:2", "np", "app:0", "app:a", "app:b" };
    int ok = 1;
    for (int i = 0; i < 8; i++) if (strcmp(k[i].uid, want[i])) ok = 0;
    check("the order: the live call, the ended call, the timer ringing first, the other timer, Now Playing, apps by relevance (higher first, then by id)", ok);

    // ---- what fits: MSBDLAFit(widths, n, room, gap, plusW, &plus)
    double w[] = { 60, 70, 50, 80 };
    int plus = -1;
    int shown = MSBDLAFit(w, 4, 400, 6, 30, &plus);
    check("room for all four (260 + 3 gaps of 6 = 278 in 400): all, no \"+N\"", shown == 4 && plus == 0);
    shown = MSBDLAFit(w, 4, 278, 6, 30, &plus);
    check("  ... exactly 278: still all", shown == 4 && plus == 0);
    shown = MSBDLAFit(w, 4, 200, 6, 30, &plus);
    check("200: the first two (60 + 6 + 70 + 6 + 30 = 172; with the third 228), \"+2\"", shown == 2 && plus == 2);
    shown = MSBDLAFit(w, 4, 50, 6, 30, &plus);
    check("50: no pill fits beside \"+N\" (30 + 60 + 6 > 50): \"+4\" alone", shown == 0 && plus == 4);
    shown = MSBDLAFit(w, 4, 20, 6, 30, &plus);
    check("20: not even \"+N\": nothing", shown == 0 && plus == 0);
    shown = MSBDLAFit(w, 1, 40, 6, 30, &plus);
    check("one pill of 60 in 40: \"+1\" alone (the card has it)", shown == 0 && plus == 1);
    shown = MSBDLAFit(w, 0, 400, 6, 30, &plus);
    check("nothing to show: nothing", shown == 0 && plus == 0);
    int never = 1;
    for (double room = 0; room <= 500; room += 7) for (int n = 1; n <= 4; n++) {
        int p = 0, s = MSBDLAFit(w, n, room, 6, 30, &p);
        double used = 0; for (int i = 0; i < s; i++) used += w[i] + (i ? 6 : 0);
        if (p) used += (s ? 6 : 0) + 30;
        if (used > room + 1e-9 || s + p > n || (p == 0 && s != n && s != 0)) never = 0;
    }
    check("  ... whatever the room: never wider than it, never more than there are, and the rest is always in \"+N\"", never);
    check("the room: from the status icons' start (800) to 12 pt past the middle of a 1194 pt bar (597): 191; none past the middle",
          near(MSBDLARoom(800, 1194, 12), 191) && MSBDLARoom(600, 1194, 12) == 0.0);

    // ---- the texts
    char t[32], s[32];
    MSBDLAClockText(4.2, 1, t, sizeof t); MSBDLAClockText(4.2, 0, s, sizeof s);
    check("a countdown of 4.2 s reads 0:05 (up, as the Clock app); a call of 4.2 s reads 0:04", !strcmp(t, "0:05") && !strcmp(s, "0:04"));
    MSBDLAClockText(299.0, 1, t, sizeof t); MSBDLAClockText(754, 0, s, sizeof s);
    check("4:59 and 12:34", !strcmp(t, "4:59") && !strcmp(s, "12:34"));
    MSBDLAClockText(3723, 0, t, sizeof t); MSBDLAClockText(-3, 1, s, sizeof s);
    check("1:02:03 past an hour; a negative time reads 0:00", !strcmp(t, "1:02:03") && !strcmp(s, "0:00"));
    MSBDLAClockText(NAN, 1, t, sizeof t);
    check("  ... not a number: 0:00", !strcmp(t, "0:00"));
    MSBDLATextShape("12:34", s, sizeof s);
    char s2[32]; MSBDLATextShape("9:59", s2, sizeof s2);
    char s3[32]; MSBDLATextShape("1:02:03", s3, sizeof s3);
    check("the shapes: 12:34 -> 00:00, 9:59 -> 0:00, 1:02:03 -> 0:00:00 (a new shape: laid out again)", !strcmp(s, "00:00") && !strcmp(s2, "0:00") && !strcmp(s3, "0:00:00"));
    MSBDLAPlusText(3, t, sizeof t);
    check("the \"+N\" pill says +3", !strcmp(t, "+3"));

    // ---- a timer: MSBDLATimerState(active, firing, fireIn, remaining, &left)
    double left = -1;
    check("running: its fire date 299 s away counts down from 299", MSBDLATimerState(1, 0, 299, 300, &left) == kMSBDLATimerRunning && near(left, 299));
    check("paused (no fire date): its remaining time, 120", MSBDLATimerState(1, 0, -1, 120, &left) == kMSBDLATimerPaused && near(left, 120));
    check("ringing: ended (shown greyed), 0 left", MSBDLATimerState(1, 1, -1, 0, &left) == kMSBDLATimerRinging && left == 0.0);
    check("not active (stopped, or never started): nothing", MSBDLATimerState(0, 0, 50, 50, &left) == kMSBDLATimerNone);
    check("  ... active with neither a fire date nor time left: nothing", MSBDLATimerState(1, 0, -1, 0, &left) == kMSBDLATimerNone);

    // ---- Now Playing
    check("the position: 30 s stamped 2 s ago at rate 1 is 32; paused (rate 0) stays 30", near(MSBDLAElapsedNow(30, 2, 1, 200), 32) && near(MSBDLAElapsedNow(30, 2, 0, 200), 30));
    check("  ... never past the duration (199 + 5 s of 200 is 200), never below 0", near(MSBDLAElapsedNow(199, 5, 1, 200), 200) && MSBDLAElapsedNow(-4, 0, 1, 0) == 0.0);
    check("  ... an unknown duration (0) does not stop it", near(MSBDLAElapsedNow(500, 10, 1, 0), 510));
    check("Now Playing playing: live (0)", MSBDLANowPlayingEnded(1, 1, 1, 0, 1000) == 0.0);
    check("  ... first seen paused at 1000: ended at 1000 (gone at 1180); still paused later: still 1000", near(MSBDLANowPlayingEnded(1, 1, 0, 0, 1000), 1000) && near(MSBDLANowPlayingEnded(1, 1, 0, 1000, 1100), 1000));
    check("  ... no app, or nothing to name: no pill (-1)", MSBDLANowPlayingEnded(0, 1, 1, 0, 5) < 0 && MSBDLANowPlayingEnded(1, 0, 1, 0, 5) < 0);

    // ---- a call's words
    const char *word = NULL;
    check("a connected call: its time", MSBDLACallText(1, 0, 0, &word) == 1);
    check("  ... held: \"On Hold\"", MSBDLACallText(1, 1, 0, &word) == 0 && !strcmp(word, "On Hold"));
    check("  ... not connected yet: \"Calling\" (ours) or \"Incoming\"", MSBDLACallText(0, 0, 0, &word) == 0 && !strcmp(word, "Calling") && MSBDLACallText(0, 0, 1, &word) == 0 && !strcmp(word, "Incoming"));
    // ---- where the timers source and the seek run (review 1.8.4 M1, P2-L3): the lists SpringBoard and Settings ask, the versions the device pass
    //      proved (KT's yes, 7 Nov): 17.5.1 (the 17.5) and 18.5 (the A12Z); every other version off until it is tested
    long tried[][3] = { { 15, 6, 1 }, { 16, 7, 7 }, { 17, 5, 1 }, { 18, 5, 0 }, { 0, 0, 0 } };
    check("timers and the seek listed for 17.5.1 and 18.5, as the device pass proved them", MSBDLATimersListed(17, 5, 1) && MSBDLATimersListed(18, 5, 0)
          && MSBDLASeekListed(17, 5, 1) && MSBDLASeekListed(18, 5, 0));
    long off[][3] = { { 15, 6, 1 }, { 16, 7, 7 }, { 17, 5, 0 }, { 17, 5, 2 }, { 17, 6, 1 }, { 18, 5, 1 }, { 18, 6, 0 }, { 18, 7, 2 }, { 26, 0, 0 }, { 0, 0, 0 } };
    int anyOff = 0;
    for (size_t i = 0; i < sizeof off / sizeof off[0]; i++) if (MSBDLATimersListed(off[i][0], off[i][1], off[i][2]) || MSBDLASeekListed(off[i][0], off[i][1], off[i][2])) anyOff = 1;
    check("  ... and for no other version (15.6.1, 16.7.7 whose MobileTimer lacks +isActiveTimer:, 17.5, 17.5.2, 17.6.1, 18.5.1, 18.6, 18.7.2, 26): off, no Timers row", !anyOff);
    check("  ... exactly those two rows in each list", sizeof kMSBDLATimersChecked / sizeof kMSBDLATimersChecked[0] == 2 && sizeof kMSBDLASeekChecked / sizeof kMSBDLASeekChecked[0] == 2);
    int noApps = 1;
    for (int i = 0; i < 4; i++) if (MSBDLAAppsListed(tried[i][0], tried[i][1], tried[i][2]) || MSBDLAAppsHostListed(tried[i][0], tried[i][1], tried[i][2])) noApps = 0;
    check("  ... other apps' activities (the listing, the live view) listed for none either: off, and no Apps row in Settings", noApps);
    check("  ... the Status Bar page's words: timers named only with timers, other apps' activities only with apps (device pass)",
          !strstr(MSBDLAGroupFooter(0, 0), "timers") && !strstr(MSBDLAGroupFooter(0, 0), "other") && strstr(MSBDLAGroupFooter(1, 0), "timers") && !strstr(MSBDLAGroupFooter(1, 0), "other")
          && strstr(MSBDLAGroupFooter(0, 1), "other Live Activities") && !strstr(MSBDLAGroupFooter(0, 1), "timers") && strstr(MSBDLAGroupFooter(1, 1), "timers") && strstr(MSBDLAGroupFooter(1, 1), "other Live Activities"));
    MSBDLAVersion sample[] = { { 0, 0, 0 }, { 17, 5, 1 } };
    check("  ... a listed version matches exactly (17.5.1 yes; 17.5, 17.5.2, 18.5.1 no)", MSBDLAVersionListed(sample, 2, 17, 5, 1) && !MSBDLAVersionListed(sample, 2, 17, 5, 0)
          && !MSBDLAVersionListed(sample, 2, 17, 5, 2) && !MSBDLAVersionListed(sample, 2, 18, 5, 1));
    return fails;
}
