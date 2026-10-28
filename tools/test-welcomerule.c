// Mac test of the one-time welcome's decisions (common/WelcomeRule.h): the helper's at install time, SpringBoard's at its start, and the stories
// they make together -- above all the 1.6.0 one: an iPadOS 18 install made while 18 was untested is not greeted as new by the update that tests 18
// (A12Z, 1.6.0~rc5). Run by test-welcomerule.sh.
#include <stdio.h>
#include "../common/WelcomeRule.h"
static int fails = 0;
#define CHECK(c, ...) do { if (!(c)) { fails++; printf("FAIL %s:%d ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)
// One install, then SpringBoard's start: shown 1 when the welcome comes up. *pending / *shownPref carry the device's state on.
static int Run(int *pending, int *shownPref, int enableAnywaySet, int notFirst, int tested, int tweakRuns) {
    switch (MSBDWelcomeAtInstall(*pending, enableAnywaySet, notFirst)) {
        case kMSBDWelcomeMarkPending: *pending = 1; break;
        case kMSBDWelcomeMarkShown: *shownPref = 1; break;
        case kMSBDWelcomeKeep: break;
    }
    if (!tweakRuns) return 0;   // (an untested version without Enable Anyway: our status bar does not run, nothing is decided)
    switch (MSBDWelcomeAtStart(*pending, *shownPref, tested)) {
        case kMSBDWelcomeShow: *shownPref = 1; return 1;   // (written as it appears)
        case kMSBDWelcomeDoneUnshown: *shownPref = 1; return 0;
        case kMSBDWelcomeNone: return 0;
    }
    return 0;
}
int main(void) {
    // the helper at install time
    CHECK(MSBDWelcomeAtInstall(0, 0, 0) == kMSBDWelcomeMarkPending, "a first install: pending");
    CHECK(MSBDWelcomeAtInstall(0, 0, 1) == kMSBDWelcomeMarkShown, "an update with no marker (before the welcome existed): marked shown");
    CHECK(MSBDWelcomeAtInstall(0, 1, 1) == kMSBDWelcomeMarkShown, "an update with no marker, Enable Anyway set: marked shown");
    CHECK(MSBDWelcomeAtInstall(1, 0, 0) == kMSBDWelcomeKeep, "a marker, never run on an untested version: kept for its first real run");
    CHECK(MSBDWelcomeAtInstall(1, 1, 0) == kMSBDWelcomeMarkShown, "a marker left by an install that ran under Enable Anyway: consumed");
    // SpringBoard at its start
    CHECK(MSBDWelcomeAtStart(0, 0, 1) == kMSBDWelcomeNone, "no marker: nothing");
    CHECK(MSBDWelcomeAtStart(1, 1, 1) == kMSBDWelcomeNone, "shown before: nothing");
    CHECK(MSBDWelcomeAtStart(1, 1, 0) == kMSBDWelcomeNone, "shown before, untested: nothing");
    CHECK(MSBDWelcomeAtStart(1, 0, 1) == kMSBDWelcomeShow, "a first install on a tested version: shown");
    CHECK(MSBDWelcomeAtStart(1, 0, 0) == kMSBDWelcomeDoneUnshown, "untested (Enable Anyway on): done for this install, unshown");

    int p, s;
    // 1. A first install on a tested version (15-17, 18 since 1.6.0): greeted once, never again after updates.
    p = 0; s = 0;
    CHECK(Run(&p, &s, 0, 0, 1, 1) == 1, "story 1: the first start greets");
    CHECK(Run(&p, &s, 0, 1, 1, 1) == 0 && Run(&p, &s, 0, 1, 1, 1) == 0, "story 1: updates do not");
    // 2. THE 1.6.0 CASE, as the builds before 1.6.0 left it: first install on untested 18, Enable Anyway on, the old SpringBoard refused without a
    //    record (nothing here: the marker stays, welcomeShown absent), updates kept the marker. The 1.6.0 update (18 tested) must not greet.
    p = 1; s = 0;
    CHECK(Run(&p, &s, 1, 1, 1, 1) == 0 && s == 1, "story 2: the update that tests 18 does not greet an 18 user of the untested days");
    CHECK(Run(&p, &s, 1, 1, 1, 1) == 0, "story 2: nor any update after it");
    // 3. The same with this build from the start on an untested version (19): refused and recorded at once, so the later update that tests 19
    //    does not greet either -- even with the key gone by then.
    p = 0; s = 0;
    CHECK(Run(&p, &s, 0, 0, 0, 1) == 0 && p == 1 && s == 1, "story 3: untested + Enable Anyway: no welcome, recorded");
    CHECK(Run(&p, &s, 0, 1, 1, 1) == 0, "story 3: the update that tests the version does not greet");
    // 4. Installed on an untested version but never run there (no Enable Anyway): the update that tests the version is its first real run.
    p = 0; s = 0;
    CHECK(Run(&p, &s, 0, 0, 0, 0) == 0 && p == 1 && s == 0, "story 4: nothing decided while the tweak does not run");
    CHECK(Run(&p, &s, 0, 1, 1, 1) == 1, "story 4: greeted at its first real run");
    // 5. A first install, then an update before SpringBoard could show it (a quick Sileo update): still greeted once.
    p = 0; s = 0;
    CHECK(MSBDWelcomeAtInstall(p, 0, 0) == kMSBDWelcomeMarkPending, "story 5: first install");
    p = 1;
    CHECK(Run(&p, &s, 0, 1, 1, 1) == 1, "story 5: the update keeps it, the first start greets");
    printf(fails ? "welcomerule: %d FAIL\n" : "welcomerule: all passed\n", fails);
    return fails != 0;
}
