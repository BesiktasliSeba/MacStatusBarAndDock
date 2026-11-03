// test-homefolder.c -- Mac test of the windows stepping aside for a Home Screen folder (common/HomeFolderRule.h, 1.7.9; code review): from the
// folder's own opening until it closes or an app or a window comes to the front -- iPadOS keeps a folder open behind the app launched from it,
// and the windows must not stay faded over that app.
#include <stdio.h>
#include "../common/HomeFolderRule.h"
static int fails = 0, checks = 0;
static void Expect(const char *what, long long got, long long want) { checks++; if (got != want) { fails++; printf("FAIL  %s (got %lld, want %lld)\n", what, got, want); } else printf("PASS  %s\n", what); }
int main(void) {
    uint64_t settings = MSBDHomeFolderFrontID("com.apple.Preferences"), clock = MSBDHomeFolderFrontID("com.apple.mobiletimer"), none = 0;
    Expect("the front's number: 0 for no app (NULL or empty)", MSBDHomeFolderFrontID(NULL) == 0 && MSBDHomeFolderFrontID("") == 0, 1);
    Expect("  ... never 0 for an app, the same for the same app, another for another", settings != 0 && clock != 0 && settings == MSBDHomeFolderFrontID("com.apple.Preferences") && settings != clock, 1);

    MSBDHomeFolderState s = {0, 0, 0};
    Expect("no folder open: the windows stay", MSBDHomeFolderStep(&s, 0, settings, 0), 0);
    Expect("a folder opens over Settings' window (the Home Screen behind the windows): the windows step aside", MSBDHomeFolderStep(&s, 1, settings, 0), 1);
    Expect("  ... and stay aside at the next looks, Settings still in front", MSBDHomeFolderStep(&s, 1, settings, 0) && MSBDHomeFolderStep(&s, 1, settings, 0), 1);
    Expect("  ... no app in front for a moment (on the way): no change", MSBDHomeFolderStep(&s, 1, none, 0) && MSBDHomeFolderStep(&s, 1, settings, 0), 1);
    Expect("Clock launched from the folder (it comes to the front, iPadOS keeps the folder open behind it): the windows come back", MSBDHomeFolderStep(&s, 1, clock, 0), 0);
    Expect("  ... and stay while the folder stays open behind Clock", MSBDHomeFolderStep(&s, 1, clock, 0), 0);
    Expect("  ... also with Settings in front again (the folder still open behind)", MSBDHomeFolderStep(&s, 1, settings, 0), 0);
    Expect("  ... and on the Home Screen, which shows the folder open again (no app in front)", MSBDHomeFolderStep(&s, 1, none, 0), 0);
    Expect("the folder closes: the windows stay", MSBDHomeFolderStep(&s, 0, none, 0), 0);
    Expect("  ... opened again: they step aside again", MSBDHomeFolderStep(&s, 1, none, 0), 1);
    Expect("a full-screen app launched from it with no window anywhere (no engine): the folder no longer counts (Finder can open over the app)", MSBDHomeFolderStep(&s, 1, clock, 0), 0);
    MSBDHomeFolderStep(&s, 0, clock, 0);

    MSBDHomeFolderState c = {0, 0, 0};
    Expect("a folder opened behind a full-screen app (the Finder menu's row): the windows stay (nothing of the folder to see)", MSBDHomeFolderStep(&c, 1, clock, 1), 0);
    Expect("  ... also when the app goes and the Home Screen shows the folder (opened behind, as left open behind an app)", MSBDHomeFolderStep(&c, 1, none, 0), 0);
    Expect("  ... closed and opened on the Home Screen: it counts", MSBDHomeFolderStep(&c, 0, none, 0) == 0 && MSBDHomeFolderStep(&c, 1, none, 0) == 1, 1);

    MSBDHomeFolderState m = {0, 0, 0};
    MSBDHomeFolderStep(&m, 1, settings, 0);
    MSBDHomeFolderMovedOn(&m, 1);
    Expect("an app icon tapped while the folder counts (Settings' own icon: no other app comes forward): the windows come back", MSBDHomeFolderStep(&m, 1, settings, 0), 0);
    Expect("  ... and stay while it is open", MSBDHomeFolderStep(&m, 1, none, 0), 0);
    Expect("  ... closed and opened again: it counts again", MSBDHomeFolderStep(&m, 0, none, 0) == 0 && MSBDHomeFolderStep(&m, 1, settings, 0) == 1, 1);
    MSBDHomeFolderStep(&m, 0, none, 0);
    MSBDHomeFolderMovedOn(&m, 1);
    Expect("an app icon tapped in a folder the looks had not seen open yet: their first look does not count it", MSBDHomeFolderStep(&m, 1, settings, 0), 0);
    MSBDHomeFolderStep(&m, 0, none, 0);
    MSBDHomeFolderMovedOn(&m, 0);
    Expect("an app icon tapped with no folder open: the next folder to open counts as usual", MSBDHomeFolderStep(&m, 1, settings, 0), 1);
    MSBDHomeFolderMovedOn(&m, 1);
    Expect("a native window made active (Finder opened from the menu bar) while the folder counts: the windows come back", MSBDHomeFolderStep(&m, 1, settings, 0), 0);
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
