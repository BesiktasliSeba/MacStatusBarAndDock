// Mac test of common/CCModuleList.h (run by test-ccmodule.sh).
#import <Foundation/Foundation.h>
#include "../common/CCModuleList.h"
#include "../ccmodule/RAMCPULayout.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

int main(void) {
    @autoreleasepool {
        // 18.5's directories (URLs, as -_initWithDirectoryURLs: gets them)
        NSArray *urls = @[[NSURL fileURLWithPath:@"/System/Library/ControlCenter/Bundles"], [NSURL fileURLWithPath:@"/System/Cryptexes/App/System/Library/ControlCenter/Bundles"]];
        NSArray *u2 = MSBDCCWithOurDirectory(urls);
        CHECK(u2.count == 3, "one folder added (%lu)", (unsigned long)u2.count);
        CHECK([u2.lastObject isKindOfClass:[NSURL class]] && [[u2.lastObject path] isEqualToString:kMSBDCCModuleDir], "ours, as a URL");
        CHECK([u2[0] isEqual:urls[0]] && [u2[1] isEqual:urls[1]], "Apple's folders kept, in order");
        CHECK(MSBDCCWithOurDirectory(u2).count == 3, "added once (the list already has it)");
        // paths (a list of strings)
        NSArray *paths = @[@"/System/Library/ControlCenter/Bundles"];
        NSArray *p2 = MSBDCCWithOurDirectory(paths);
        CHECK(p2.count == 2 && [p2.lastObject isKindOfClass:[NSString class]] && [p2.lastObject isEqualToString:kMSBDCCModuleDir], "ours, as a path");
        CHECK(MSBDCCWithOurDirectory([paths arrayByAddingObject:[kMSBDCCModuleDir stringByAppendingString:@"/"]]).count == 2, "a trailing slash is the same folder");
        CHECK(MSBDCCWithOurDirectory(nil) == nil, "no list: none made");
        // allowed list: a set (17.5 / 18.5) or an array
        NSSet *allowed = [NSSet setWithArray:@[@"com.apple.control-center.MuteModule", @"com.apple.FocusUIModule"]];
        NSSet *a2 = MSBDCCWithOurIdentifier(allowed);
        CHECK(a2.count == 3 && [a2 containsObject:kMSBDCCModuleID] && [allowed isSubsetOfSet:a2], "set: ours added, Apple's kept");
        CHECK(MSBDCCWithOurIdentifier(a2) == a2, "set: added once");
        NSArray *arr = @[@"com.apple.control-center.MuteModule"];
        NSArray *arr2 = MSBDCCWithOurIdentifier(arr);
        CHECK(arr2.count == 2 && [arr2.lastObject isEqualToString:kMSBDCCModuleID], "array: ours added at the end");
        CHECK(MSBDCCWithOurIdentifier(nil) == nil, "no allowed list (everything loads): nothing added");
    }
    // the tile's lines (ccmodule/RAMCPULayout.h): Control Center's own 2 x 1 tile (142 x 66, iPad 2 16.7.7) as before 1.6.0's square layout;
    // BigSurCenter's square tile (75 x 75): every line at least 50 points wide (laid out for 2 x 1 there: 18 and 15 points, "..." on the screen)
    CGRect f[kRCCount];
    CHECK(!MSBDRAMCPUSquare(CGSizeMake(142, 66)) && !MSBDRAMCPUSquare(CGSizeMake(153, 69)), "2 x 1 tiles (16.7.7, 17.5) are laid out as 2 x 1");
    MSBDRAMCPUFrames(CGRectMake(0, 0, 142, 66), f);
    CHECK(fabs(f[kRCRamValue].size.width - 60.7616) < 0.01 && fabs(f[kRCCpuValue].size.width - 40.9184) < 0.01, "2 x 1: the widths 16.7.7 showed (%.4f, %.4f)", f[kRCRamValue].size.width, f[kRCCpuValue].size.width);
    CHECK(f[kRCUsed].size.width > 0 && f[kRCDivider].size.width == 0, "2 x 1: the used line, no divider");
    CHECK(CGRectGetMaxX(f[kRCCpuValue]) <= 142 && CGRectGetMaxY(f[kRCUsed]) <= 66, "2 x 1: inside the tile");
    CHECK(MSBDRAMCPUSquare(CGSizeMake(75, 75)), "BigSurCenter's 75 x 75 tile is square");
    MSBDRAMCPUFrames(CGRectMake(0, 0, 75, 75), f);
    int wide = 1, inside = 1;
    for (int i = 0; i < kRCCount; i++) {
        if (i == kRCUsed) { CHECK(f[i].size.width == 0, "square: no used line"); continue; }
        if (i != kRCDivider && f[i].size.width < 50.0) wide = 0;
        if (CGRectGetMaxX(f[i]) > 75.0 || CGRectGetMaxY(f[i]) > 75.0 || f[i].origin.x < 0 || f[i].origin.y < 0) inside = 0;
    }
    CHECK(wide, "square: every line at least 50 points wide");
    CHECK(inside, "square: every line inside the tile");
    CHECK(CGRectGetMaxY(f[kRCRamValue]) <= f[kRCDivider].origin.y && f[kRCDivider].origin.y < f[kRCCpuCaption].origin.y, "square: the memory, the line, then the CPU");
    printf("test-ccmodule: %d passed, %d failed\n", passes, fails);
    return fails ? 1 : 0;
}
