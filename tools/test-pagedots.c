// Mac test of whose page dots Hide Page Dots hides (common/PageDotsOwner.h): the Home Screen's (a page control of SpringBoard's own folder views),
// not iPadOS 18's Control Center's page glyphs (ControlCenterUI's folder view; A12Z 18.5, 1.7.1 item 12). Run by test-pagedots.sh.
#include <stdio.h>
#include "../common/PageDotsOwner.h"
static int fails = 0, checks = 0;
#define CHECK(c, what) do { checks++; if (!(c)) { fails++; printf("FAIL %s:%d %s\n", __FILE__, __LINE__, what); } } while (0)
int main(void) {
    CHECK(MSBDPageDotsHomeScreens("/System/Library/PrivateFrameworks/SpringBoardHome.framework/SpringBoardHome") == 1,
          "the Home Screen's pages (SBRootFolderView) and its folders: hidden");
    CHECK(MSBDPageDotsHomeScreens("/System/Library/PrivateFrameworks/SpringBoard.framework/SpringBoard") == 1, "SpringBoard's own class (18): hidden");
    CHECK(MSBDPageDotsHomeScreens("/System/Library/CoreServices/SpringBoard.app/SpringBoard") == 1, "SpringBoard's own class (15, 16): hidden");
    CHECK(MSBDPageDotsHomeScreens("/System/Library/PrivateFrameworks/ControlCenterUI.framework/ControlCenterUI") == 0,
          "iPadOS 18's Control Center (ControlCenterUI.IconListRootFolderView): its page glyphs stay");
    CHECK(MSBDPageDotsHomeScreens("/var/jb/usr/lib/TweakInject/SomeTweak.dylib") == 0, "a folder view another tweak made: left alone");
    CHECK(MSBDPageDotsHomeScreens("/System/Library/PrivateFrameworks/SpringBoardHomeExtras.framework/SpringBoardHomeExtras") == 0, "only the exact names");
    CHECK(MSBDPageDotsHomeScreens(NULL) == 1 && MSBDPageDotsHomeScreens("") == 1, "no owner known: hidden, as before 1.7.1");
    CHECK(MSBDPageDotsHomeScreens("SpringBoardHome") == 1, "a bare name");
    printf("pagedots: %d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
