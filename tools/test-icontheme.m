// test-icontheme.m -- Mac test of the Dock items' app-icon identities (1.7.5 item 7): the shared rules in common/IconThemeIDs.h, run as they are.
#import <Foundation/Foundation.h>
#include "../common/IconThemeIDs.h"
static int fails = 0;
static void ok(NSString *what, BOOL yes) { printf("%s  %s\n", yes ? "PASS" : "FAIL", what.UTF8String); if (!yes) fails++; }
int main(void) {
    @autoreleasepool {
        // the published identifiers (README: for theme makers) -- never change
        ok(@"Finder's id", [MSBDIconID(MSBDIconFinder) isEqualToString:@"com.besiktasliseba.finder"]);
        ok(@"Launchpad's id", [MSBDIconID(MSBDIconLaunchpad) isEqualToString:@"com.besiktasliseba.macstatusbar.launchpad"]);
        ok(@"classic Launchpad's id", [MSBDIconID(MSBDIconLaunchpadClassic) isEqualToString:@"com.besiktasliseba.macstatusbar.launchpad.classic"]);
        ok(@"Downloads' id", [MSBDIconID(MSBDIconDownloads) isEqualToString:@"com.besiktasliseba.macstatusbar.downloads"]);
        ok(@"the empty Trash's id", [MSBDIconID(MSBDIconTrashEmpty) isEqualToString:@"com.besiktasliseba.macstatusbar.trash"]);
        ok(@"the full Trash's id", [MSBDIconID(MSBDIconTrashFull) isEqualToString:@"com.besiktasliseba.macstatusbar.trash.full"]);
        ok(@"Activity Monitor's id (since 1.7.2, never renamed)", [MSBDIconID(MSBDIconActivityMonitor) isEqualToString:@"com.besiktasliseba.macstatusbar.activitymonitor"]);
        ok(@"no id past the last item", MSBDIconID(MSBDIconItemCount) == nil && MSBDIconLookup(MSBDIconItemCount).count == 0);
        NSMutableSet *all = [NSMutableSet set];
        for (NSInteger i = 0; i < MSBDIconItemCount; i++) [all addObject:MSBDIconID((MSBDIconItem)i)];
        ok(@"every item has its own id", all.count == MSBDIconItemCount);
        // the order asked
        ok(@"Finder: its own id, then com.apple.finder (published in 1.2)", [MSBDIconLookup(MSBDIconFinder) isEqualToArray:(@[@"com.besiktasliseba.finder", @"com.apple.finder"])]);
        ok(@"classic Launchpad: its own id, then Launchpad's", [MSBDIconLookup(MSBDIconLaunchpadClassic) isEqualToArray:(@[@"com.besiktasliseba.macstatusbar.launchpad.classic", @"com.besiktasliseba.macstatusbar.launchpad"])]);
        ok(@"grid Launchpad: its own id only", [MSBDIconLookup(MSBDIconLaunchpad) isEqualToArray:@[@"com.besiktasliseba.macstatusbar.launchpad"]]);
        ok(@"the full Trash: its own id only (a theme's empty bin never stands for a full Trash)", [MSBDIconLookup(MSBDIconTrashFull) isEqualToArray:@[@"com.besiktasliseba.macstatusbar.trash.full"]]);
        ok(@"the empty Trash, Downloads, Activity Monitor: their own ids only",
           [MSBDIconLookup(MSBDIconTrashEmpty) isEqualToArray:@[MSBDIconID(MSBDIconTrashEmpty)]] && [MSBDIconLookup(MSBDIconDownloads) isEqualToArray:@[MSBDIconID(MSBDIconDownloads)]]
           && [MSBDIconLookup(MSBDIconActivityMonitor) isEqualToArray:@[MSBDIconID(MSBDIconActivityMonitor)]]);
        BOOL round = YES;
        for (NSInteger i = 0; i < MSBDIconItemCount; i++) for (NSString *ident in MSBDIconLookup((MSBDIconItem)i)) {
            MSBDIconItem back = MSBDIconItemForID(ident);
            if (back >= MSBDIconItemCount) round = NO;
            if (![ident isEqualToString:@"com.apple.finder"] && back != (MSBDIconItem)MSBDIconItemForID(MSBDIconID(back))) round = NO;
        }
        ok(@"every id asked draws a known item's picture (com.apple.finder: Finder's)", round && MSBDIconItemForID(@"com.apple.finder") == MSBDIconFinder);
        ok(@"an unknown id draws nothing", MSBDIconItemForID(@"com.apple.Preferences") == MSBDIconItemCount && MSBDIconItemForID(nil) == MSBDIconItemCount);
        ok(@"Trash look -> item", MSBDIconTrashItem(NO) == MSBDIconTrashEmpty && MSBDIconTrashItem(YES) == MSBDIconTrashFull);
        ok(@"Launchpad style -> item", MSBDIconLaunchpadItem(NO) == MSBDIconLaunchpad && MSBDIconLaunchpadItem(YES) == MSBDIconLaunchpadClassic);
        ok(@"names", [MSBDIconName(MSBDIconTrashFull) isEqualToString:@"Trash"] && [MSBDIconName(MSBDIconLaunchpadClassic) isEqualToString:@"Launchpad"]
           && [MSBDIconName(MSBDIconActivityMonitor) isEqualToString:@"Activity Monitor"] && [MSBDIconName(MSBDIconFinder) isEqualToString:@"Finder"]);
        // the canvas: pictures with transparent margins mark it, tiles don't
        ok(@"the bins and the round rocket mark their canvas", MSBDIconHasMargins(MSBDIconTrashEmpty) && MSBDIconHasMargins(MSBDIconTrashFull) && MSBDIconHasMargins(MSBDIconLaunchpadClassic));
        ok(@"the tiles do not", !MSBDIconHasMargins(MSBDIconFinder) && !MSBDIconHasMargins(MSBDIconLaunchpad) && !MSBDIconHasMargins(MSBDIconDownloads) && !MSBDIconHasMargins(MSBDIconActivityMonitor));
        enum { W = 120, H = 120 };
        static unsigned char a[W * H];
        memset(a, 0, sizeof a);
        for (int y = 20; y < 104; y++) for (int x = 30; x < 92; x++) a[y * W + x] = 255;   // (a bin: 62 x 84 in the middle)
        MSBDAlphaInsets before = MSBDIconAlphaInsets(a, W, H);
        ok(@"a theme engine's margin crop would cut a bin's canvas (20/30/16/28)", before.top == 20 && before.left == 30 && before.bottom == 16 && before.right == 28);
        MSBDCanvasMarks m = MSBDIconCanvasMarks(W, H);
        a[m.y0 * W + m.x0] = 1; a[m.y1 * W + m.x1] = 1;   // (alpha 1/255)
        MSBDAlphaInsets after = MSBDIconAlphaInsets(a, W, H);
        ok(@"the two marks keep the whole canvas (no crop)", after.top == 0 && after.left == 0 && after.bottom == 0 && after.right == 0);
        ok(@"the marks sit in two opposite corners", m.x0 == 0 && m.y0 == 0 && m.x1 == W - 1 && m.y1 == H - 1);
        MSBDAlphaInsets none = MSBDIconAlphaInsets(NULL, 0, 0);
        ok(@"an empty bitmap: no crop", none.top == 0 && none.left == 0 && none.bottom == 0 && none.right == 0);
        // the pick
        BOOL t0[3] = { NO, NO, NO }, t1[3] = { NO, YES, NO }, t2[3] = { YES, YES, NO };
        ok(@"nothing themed: the first id's (ours, as the engine shaped it)", MSBDIconPick(t0, 3) == 0);
        ok(@"the first themed id wins", MSBDIconPick(t1, 3) == 1 && MSBDIconPick(t2, 3) == 0);
        ok(@"no ids: 0", MSBDIconPick(t0, 0) == 0);
        // the shapes as the runtime reports them (17.5.1's type strings)
        ok(@"the data source's picture methods", MSBDIconTypesAre("@56@0:8@16{SBIconImageInfo={CGSize=dd}dd}24", MSBDIconSourceMethodTypes()));
        ok(@"the icon's picture methods", MSBDIconTypesAre("@48@0:8{SBIconImageInfo={CGSize=dd}dd}16", MSBDIconImageMethodTypes()));
        ok(@"a picture method of another shape is refused", !MSBDIconTypesAre("@64@0:8{SBIconImageInfo={CGSize=dd}ddd}16", MSBDIconImageMethodTypes()) && !MSBDIconTypesAre(NULL, @"@@:"));
        // where it runs
        ok(@"iPadOS 15 to 17 only (18: our own pictures, KT 1 Nov)", !MSBDIconThemeOS(14) && MSBDIconThemeOS(15) && MSBDIconThemeOS(16) && MSBDIconThemeOS(17) && !MSBDIconThemeOS(18) && !MSBDIconThemeOS(26));
        ok(@"SnowBoard's refresh notification", !strcmp(kMSBDIconThemeSnowBoardRefreshed, "com.spark.snowboard.refreshComplete"));
    }
    printf("test-icontheme rules: %d failure(s)\n", fails);
    return fails ? 1 : 0;
}
