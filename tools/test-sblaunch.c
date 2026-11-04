// Mac test of which -[SpringBoard launchApplicationWithIdentifier:suspended:] calls open the app as every other launch does with a window engine
// (1.8.0 item 8, GitHub #10): statusbar/SBLaunchRule.h, which StatusBar.x DMSBLaunchOpensWindow asks. Run by test-sblaunch.sh, which also checks
// the hook as built.
#include <stdio.h>
#include <stdint.h>
#include "../statusbar/SBLaunchRule.h"

static int fails = 0, passes = 0;
// A stack of callers played through the walk: each caller's image path (the immediate caller first), its address a fake one the image is read from.
static const char *gImages[16];
static const char *FakeImageOf(const void *a) { uintptr_t i = (uintptr_t)a - 1; return i < 16 ? gImages[i] : NULL; }
static const char *Walk(const char *const *images, int n, const char *ours) {
    void *callers[16];
    for (int i = 0; i < n && i < 16; i++) { gImages[i] = images[i]; callers[i] = (void *)(uintptr_t)(i + 1); }
    return MSBDSBLaunchEngineCaller(callers, n, FakeImageOf, ours);
}
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

int main(void) {
    // the engines' own images (dladdr's paths on Dopamine and palera1n)
    CHECK(MSBDSBLaunchCallerIsEngine("/var/jb/usr/lib/TweakInject/Zetsu.dylib"), "Zetsu's own call (it builds its windows with it)");
    CHECK(MSBDSBLaunchCallerIsEngine("/var/jb/usr/lib/TweakInject/Aerial.dylib"), "Aerial's own call");
    CHECK(MSBDSBLaunchCallerIsEngine("/var/jb/usr/lib/TweakInject/MilkyWay4.dylib") && MSBDSBLaunchCallerIsEngine("/var/jb/usr/lib/TweakInject/MilkyWay3SubModule.dylib"), "MilkyWay4's own calls");
    CHECK(MSBDSBLaunchCallerIsEngine("/private/preboot/ABC/jb-XYZ/procursus/usr/lib/TweakInject/Zetsu.dylib"), "  ... wherever the jailbreak keeps it");
    CHECK(!MSBDSBLaunchCallerIsEngine("/var/jb/usr/lib/TweakInject/InstaLauncher.dylib"), "a launcher tweak is not an engine");
    CHECK(!MSBDSBLaunchCallerIsEngine("/var/jb/usr/lib/MacStatusBarAndDock/MacStatusBarCore.dylib"), "our own code is not an engine (the Today View's rows)");
    CHECK(!MSBDSBLaunchCallerIsEngine("/System/Library/CoreServices/SpringBoard.app/SpringBoard"), "SpringBoard is not an engine");
    CHECK(!MSBDSBLaunchCallerIsEngine("/var/jb/usr/lib/TweakInject/NotZetsu.dylib") && !MSBDSBLaunchCallerIsEngine("/var/jb/usr/lib/TweakInject/Zetsu.dylib.bak"), "only the engines' own names, whole");
    CHECK(!MSBDSBLaunchCallerIsEngine(NULL) && !MSBDSBLaunchCallerIsEngine("") && !MSBDSBLaunchCallerIsEngine("Zetsu.dylib"), "no path: not an engine");
    // the rule
    const char *launcher = "/var/jb/usr/lib/TweakInject/InstaLauncher.dylib", *zetsu = "/var/jb/usr/lib/TweakInject/Zetsu.dylib";
    CHECK(MSBDSBLaunchToWindow(0, 0, 0, 0, 1, launcher), "a launcher's call with a window engine: as a launch (its window forward, or a new window)");
    CHECK(MSBDSBLaunchToWindow(0, 0, 0, 0, 1, NULL), "  ... a caller not known: the same");
    CHECK(!MSBDSBLaunchToWindow(1, 0, 0, 0, 1, launcher), "in the background (suspended): left as it is");
    CHECK(!MSBDSBLaunchToWindow(0, 1, 0, 0, 1, launcher), "our own full-screen launch: left as it is");
    CHECK(!MSBDSBLaunchToWindow(0, 0, 0, 1, 1, launcher), "the Stage Manager engine: its own way (SMDesktop.h)");
    CHECK(!MSBDSBLaunchToWindow(0, 0, 0, 0, 0, launcher), "no window engine: left as it is");
    CHECK(!MSBDSBLaunchToWindow(0, 0, 0, 0, 1, zetsu), "Zetsu's own call: left as it is (a window being built)");
    CHECK(!MSBDSBLaunchToWindow(0, 0, 1, 0, 1, launcher), "the Lock Screen or the Cover Sheet up: SpringBoard's own launch (it asks for the unlock or puts the Cover Sheet away first; 1.8.0 review 6)");
    CHECK(!MSBDSBLaunchToWindow(0, 0, 1, 0, 1, NULL), "  ... a caller not known: the same");
    // the engine making the call, found up its callers (1.8.0 review 8): another tweak that hooks this call after ours and calls through puts
    // its own frame between the engine and us
    const char *other = "/var/jb/usr/lib/TweakInject/SomeLauncherHook.dylib", *other2 = "/var/jb/usr/lib/TweakInject/AnotherHook.dylib";
    const char *uikit = "/System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore", *sb = "/System/Library/CoreServices/SpringBoard.app/SpringBoard";
    const char *objc = "/usr/lib/libobjc.A.dylib", *ours = "/var/jb/usr/lib/MacStatusBarAndDock/MacStatusBarCore.dylib", *aerial = "/var/jb/usr/lib/TweakInject/Aerial.dylib";
    CHECK(Walk((const char *[]){zetsu, uikit}, 2, ours) == zetsu, "Zetsu's own call, ours the only hook: Zetsu (the immediate caller, as before)");
    CHECK(Walk((const char *[]){other, zetsu, uikit}, 3, ours) == zetsu, "  ... another tweak's hook of the call between: still Zetsu's own call");
    CHECK(Walk((const char *[]){other, other2, zetsu}, 3, ours) == zetsu && Walk((const char *[]){NULL, zetsu}, 2, ours) == zetsu, "  ... two hooks between, or a hook's trampoline with no image: Zetsu");
    CHECK(Walk((const char *[]){other, aerial}, 2, ours) == aerial, "  ... Aerial's own the same");
    CHECK(!Walk((const char *[]){other, uikit, zetsu}, 3, ours), "a launcher's call from a tap (UIKit under it): not an engine's, whatever is further up (an engine's touch hook)");
    CHECK(!Walk((const char *[]){sb, zetsu}, 2, ours) && !Walk((const char *[]){other, objc, zetsu}, 3, ours), "  ... SpringBoard's own call, or iPadOS's code between: not an engine's");
    CHECK(!Walk((const char *[]){ours, zetsu}, 2, ours), "  ... our own call (the Today View's rows): ours, not the engine's above it");
    CHECK(!Walk((const char *[]){other, other, other, other, other, other, zetsu}, 7, ours) && kMSBDSBLaunchCallerDepth >= 3 && kMSBDSBLaunchCallerDepth <= 8,
          "  ... looked for in the first %d callers only", kMSBDSBLaunchCallerDepth);
    CHECK(!Walk((const char *[]){other}, 1, ours) && !Walk(NULL, 0, ours), "  ... no engine there, or no callers: none");
    CHECK(!MSBDSBLaunchToWindow(0, 0, 0, 0, 1, Walk((const char *[]){other, zetsu, uikit}, 3, ours)), "Zetsu's call through another tweak's hook: left to SpringBoard (its window being built, never surfaced)");
    CHECK(MSBDSBLaunchToWindow(0, 0, 0, 0, 1, Walk((const char *[]){other, uikit}, 2, ours)), "  ... a launcher's through another hook: as a launch (its window forward, or a new window)");
    printf("test-sblaunch: %d passed, %d failed\n", passes, fails);
    return fails ? 1 : 0;
}
