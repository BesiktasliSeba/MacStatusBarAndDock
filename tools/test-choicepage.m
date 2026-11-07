// test-choicepage.m -- Mac test of our choice pages' rows (common/ChoicePage.h, 1.8.0): what each row of the Window Engine page shows (as the
// engine page showed it since 1.5.2: the refactor keeps it), of the Control Center Style page and of the Banner Style page (item 2), for every state
// it can be in; the Banner Style's footers.
#import <Foundation/Foundation.h>
#import "../common/ChoicePage.h"

static int gFail = 0, gN = 0;
static void Expect(BOOL ok, NSString *what) { gN++; if (!ok) { gFail++; printf("  FAIL %s\n", what.UTF8String); } }
static BOOL Row(NSDictionary *r, int state, BOOL native, NSString *title, NSString *reason, NSString *url, BOOL hidden) {
    return [r[@"state"] intValue] == state && [r[@"native"] boolValue] == native && [r[@"hidden"] boolValue] == hidden
        && (title ? [r[@"title"] isEqual:title] : !r[@"title"]) && (reason ? [r[@"reason"] isEqual:reason] : !r[@"reason"]) && (url ? [r[@"url"] isEqual:url] : !r[@"url"]);
}

int main(void) {
    @autoreleasepool {
        // ---- Window Engine (state: 0 not installed, 1 an untested build, 2 tested; Stage Manager: on this iPad, its check on this build) ----
        Expect(Row(MSBDChoiceEngineRow(@"aerial", 2, @"Aerial 5.1", NO, 1), 2, NO, nil, nil, nil, NO), @"Aerial installed and tested: Third-Party, can be picked");
        Expect(Row(MSBDChoiceEngineRow(@"aerial", 1, @"Aerial 5.2", NO, 1), 1, NO, @"Aerial 5.2 (Untested, Runs on Its Own)", nil, nil, NO), @"an untested Aerial build: picked, its title says so");
        Expect(Row(MSBDChoiceEngineRow(@"zetsu", 1, nil, NO, 1), 1, NO, @"zetsu (Untested, Runs on Its Own)", nil, nil, NO), @"  ... no version known: its value");
        Expect(Row(MSBDChoiceEngineRow(@"aerial", 0, @"Aerial", NO, 1), 0, NO, nil, nil, @"https://github.com/uz-ra", NO), @"Aerial not installed: greyed, GET to uz-ra's GitHub");
        Expect(Row(MSBDChoiceEngineRow(@"zetsu", 0, @"Zetsu", NO, 1), 0, NO, nil, nil, @"https://dcsyhi1998.github.io/depiction/zetsu", NO), @"Zetsu not installed: GET to its developer's page");
        Expect(Row(MSBDChoiceEngineRow(@"milkyway", 0, @"MilkyWay4", NO, 1), 0, NO, nil, nil, @"https://akusio.github.io/", NO), @"MilkyWay4 not installed: GET to akusio's page");
        Expect(Row(MSBDChoiceEngineRow(@"stagemanager", 2, nil, YES, 1), 2, YES, nil, nil, nil, NO), @"Stage Manager where it runs: Native, can be picked");
        Expect(Row(MSBDChoiceEngineRow(@"stagemanager", 0, nil, YES, 0), 0, YES, nil, @"Not Supported Yet", nil, NO), @"Stage Manager here, its check failed on this build: greyed, \"Not Supported Yet\"");
        Expect(Row(MSBDChoiceEngineRow(@"stagemanager", 0, nil, YES, -1), 0, YES, nil, @"Respring to Check", nil, NO), @"  ... not checked yet: \"Respring to Check\"");
        Expect(Row(MSBDChoiceEngineRow(@"stagemanager", 0, nil, NO, 1), 0, YES, nil, nil, nil, NO), @"no Stage Manager on this iPad: greyed, no reason (the Native footer says why), no GET (Apple's)");
        // ---- Control Center Style (osMajor, our Control Center's verdict, built in, BigSurCenter installed) ----
        Expect(Row(MSBDChoiceCCStyleRow(@"mac", 16, 1, YES, YES, NO), 2, YES, nil, nil, nil, NO), @"Mac on 16, checked: Native, can be picked");
        Expect(Row(MSBDChoiceCCStyleRow(@"mac", 18, 1, YES, NO, NO), 2, YES, nil, nil, nil, NO), @"Mac on 18 where its check passed: can be picked (Apple's 18 grid in the Mac panel, 1.8.0 P5b)");
        Expect(Row(MSBDChoiceCCStyleRow(@"mac", 18, 0, YES, NO, NO), 0, YES, nil, @"Not Supported Yet", nil, NO), @"  ... where it failed: greyed \"Not Supported Yet\"");
        Expect(Row(MSBDChoiceCCStyleRow(@"mac", 26, 1, YES, NO, NO), 0, YES, nil, @"Not Supported Yet", nil, NO), @"Mac after 18: greyed \"Not Supported Yet\"");
        Expect(Row(MSBDChoiceCCStyleRow(@"mac", 17, 0, YES, NO, NO), 0, YES, nil, @"Not Supported Yet", nil, NO), @"Mac where its check failed: the same");
        Expect(Row(MSBDChoiceCCStyleRow(@"mac", 15, -1, YES, NO, NO), 0, YES, nil, @"Respring to Check", nil, NO), @"Mac not checked on this build yet: \"Respring to Check\"");
        Expect(Row(MSBDChoiceCCStyleRow(@"mac", 16, 0, NO, NO, NO), 0, YES, nil, @"Not Supported Yet", nil, NO), @"Mac in a build without our Control Center: greyed");
        Expect(Row(MSBDChoiceCCStyleRow(@"stock", 18, 0, NO, NO, NO), 2, YES, nil, nil, nil, NO) && Row(MSBDChoiceCCStyleRow(@"stock", 15, 1, YES, YES, NO), 2, YES, nil, nil, nil, NO),
               @"iPadOS: Native, always there");
        Expect(Row(MSBDChoiceCCStyleRow(@"bigsurcenter", 16, 1, YES, YES, NO), 2, NO, nil, nil, nil, NO), @"BigSurCenter installed: Third-Party, can be picked");
        Expect(Row(MSBDChoiceCCStyleRow(@"bigsurcenter", 16, 1, YES, NO, NO), 0, NO, nil, nil, @"https://havoc.app/package/bigsurcenter", NO), @"BigSurCenter not installed on 16: GET to its developer's page");
        Expect(Row(MSBDChoiceCCStyleRow(@"bigsurcenter", 15, 1, YES, NO, NO), 0, NO, nil, nil, kMSBDChoiceGetBigSurCenter, NO), @"  ... on 15 too");
        Expect(Row(MSBDChoiceCCStyleRow(@"bigsurcenter", 17, 1, YES, NO, NO), 0, NO, nil, nil, nil, YES), @"BigSurCenter not installed on 17: left off the page (offered up to 16.3.1)");
        Expect(Row(MSBDChoiceCCStyleRow(@"bigsurcenter", 18, 0, YES, YES, NO), 2, NO, nil, nil, nil, NO), @"BigSurCenter installed on 18: can be picked (KT 3 Nov)");
        // the Native group's footer: why Mac is greyed
        Expect(!MSBDChoiceCCStyleNativeFooter(16, 1, YES, @"16.7.7", NO), @"Mac can be picked: no footer");
        Expect(!MSBDChoiceCCStyleNativeFooter(18, 1, YES, @"18.5", NO), @"18 where its check passed: no footer");
        Expect([MSBDChoiceCCStyleNativeFooter(18, 0, YES, @"18.5", NO) isEqual:@"The Mac Control Center isn't supported on iPadOS 18.5 yet."], @"  ... 18 where it failed: not supported on this version yet");
        Expect([MSBDChoiceCCStyleNativeFooter(26, 1, YES, @"26.0", NO) isEqual:@"The Mac Control Center isn't available on iPadOS 26 yet."], @"after 18: not available yet");
        Expect([MSBDChoiceCCStyleNativeFooter(16, 0, YES, @"16.7.7", NO) isEqual:@"The Mac Control Center isn't supported on iPadOS 16.7.7 yet."], @"a failed check: not supported on this version yet");
        Expect([MSBDChoiceCCStyleNativeFooter(17, -1, YES, @"17.5.1", NO) isEqual:@"Respring once to check the Mac Control Center on this iPadOS version."], @"not checked yet: respring once");
        Expect(!MSBDChoiceCCStyleNativeFooter(18, 0, NO, @"18.5", NO), @"a build without our Control Center: nothing said");
        Expect(Row(MSBDChoiceCCStyleRow(@"mac", 17, 1, YES, NO, YES), 0, YES, nil, @"Needs Mac Status Bar", nil, NO) && Row(MSBDChoiceCCStyleRow(@"mac", 15, -1, YES, NO, YES), 0, YES, nil, @"Needs Mac Status Bar", nil, NO),
               @"Mac with Status Bar Style Stock: greyed \"Needs Mac Status Bar\" (the panel runs only with our status bar, 1.8.0)");
        Expect(Row(MSBDChoiceCCStyleRow(@"mac", 18, 1, YES, NO, YES), 0, YES, nil, @"Needs Mac Status Bar", nil, NO), @"  ... on 18 too");
        Expect(Row(MSBDChoiceCCStyleRow(@"mac", 26, 1, YES, NO, YES), 0, YES, nil, @"Not Supported Yet", nil, NO), @"  ... after 18 still \"Not Supported Yet\"");
        Expect(Row(MSBDChoiceCCStyleRow(@"stock", 17, 1, YES, NO, YES), 2, YES, nil, nil, nil, NO) && Row(MSBDChoiceCCStyleRow(@"bigsurcenter", 16, 1, YES, YES, YES), 2, NO, nil, nil, nil, NO),
               @"  ... iPadOS and an installed BigSurCenter can still be picked");
        Expect([MSBDChoiceCCStyleNativeFooter(17, 1, YES, @"17.5.1", YES) isEqual:@"The Mac Control Center works with the Mac status bar. Set Status Bar Style to Mac to use it."], @"  ... its footer says how to get it");
        Expect([MSBDChoiceCCStyleNativeFooter(18, 1, YES, @"18.5", YES) isEqual:@"The Mac Control Center works with the Mac status bar. Set Status Bar Style to Mac to use it."], @"  ... on 18 the same footer");
        Expect([MSBDChoiceCCStyleNativeFooter(26, 1, YES, @"26.0", YES) isEqual:@"The Mac Control Center isn't available on iPadOS 26 yet."], @"  ... after 18 the not-available footer");
        // ---- Banner Style (Destra installed or not) and its footers ----
        Expect(Row(MSBDChoiceBannerRow(@"mac", NO), 2, YES, nil, nil, nil, NO) && Row(MSBDChoiceBannerRow(@"stock", YES), 2, YES, nil, nil, nil, NO), @"Banner Style: Mac and iPadOS Native, always there");
        Expect(Row(MSBDChoiceBannerRow(@"destra", YES), 2, NO, nil, nil, nil, NO), @"Destra installed: Third-Party, can be picked");
        Expect(Row(MSBDChoiceBannerRow(@"destra", NO), 0, NO, nil, @"Not Installed", nil, NO), @"Destra not installed: on the page all the same, greyed \"Not Installed\", no GET (no page of its developer's left; KT 3 Nov)");
        Expect(!MSBDChoiceBannerThirdPartyFooter(YES, YES) && !MSBDChoiceBannerThirdPartyFooter(NO, NO) && !MSBDChoiceBannerThirdPartyFooter(NO, YES), @"Third-Party footer: nothing while Destra is on, or not there");
        Expect([MSBDChoiceBannerThirdPartyFooter(YES, NO) isEqual:@"Destra is turned off in its own settings. Turn on Enabled in Settings > Destra to see its banners."], @"  ... Destra off in its own settings: says where to turn it on");
        Expect([MSBDChoiceBannerGroupFooter(kMSBDBannerMac, NO, NO, 0) isEqual:@"Banners appear at the top right. Only the chosen banner style is loaded."], @"the group's footer, Mac: where ours appear, only the chosen loads");
        Expect([MSBDChoiceBannerGroupFooter(kMSBDBannerStock, YES, YES, 0) isEqual:@"Only the chosen banner style is loaded."] && [MSBDChoiceBannerGroupFooter(kMSBDBannerDestra, YES, YES, 0) isEqual:@"Only the chosen banner style is loaded."],
               @"  ... iPadOS, Destra: only the chosen loads");
        Expect([MSBDChoiceBannerGroupFooter(kMSBDBannerDestra, YES, NO, 0) isEqual:@"Only the chosen banner style is loaded. Destra is turned off in its own settings, so iPadOS's banners are shown."],
               @"  ... Destra picked but off in its own settings: iPadOS's banners show, and why");
        Expect([MSBDChoiceBannerGroupFooter(kMSBDBannerMac, YES, NO, 0) isEqual:@"Banners appear at the top right. Only the chosen banner style is loaded."], @"  ... Destra off in its own settings matters only while it is the style");
        Expect([MSBDChoiceBannerGroupFooter(kMSBDBannerMac, YES, YES, 1) isEqual:@"Banners appear at the top right. Only the chosen banner style is loaded. Destra stays loaded until you respring."], @"  ... Destra still loaded: until the respring");
        Expect([MSBDChoiceBannerGroupFooter(kMSBDBannerDestra, YES, YES, 2) isEqual:@"Only the chosen banner style is loaded. Destra loads after a respring."], @"  ... Destra picked, not loaded yet: after a respring");
        Expect([MSBDChoiceBannerGroupFooter(kMSBDBannerMac, YES, YES, 3) isEqual:@"Banners appear at the top right. Only the chosen banner style is loaded. Install Choicy (or iCleaner Pro) so MacStatusBar&Dock can stop Destra from loading."],
               @"  ... Destra still loaded with nothing to keep it out: Choicy is needed (the pick's alert's words), not a respring");
        // ---- KeyPilot on the Keyboard page (1.8.3): its name and developer, GET to its page while not installed, OPEN its app once it is ----
        NSDictionary *kpGet = MSBDKeyPilotRow(NO), *kpOpen = MSBDKeyPilotRow(YES);
        Expect([kpGet[@"title"] isEqual:@"KeyPilot"] && [kpGet[@"subtitle"] isEqual:@"by wanghuangjie"], @"KeyPilot: its name, \"by wanghuangjie\" under it");
        Expect([kpGet[@"button"] isEqual:@"GET"] && [kpGet[@"url"] isEqual:@"https://github.com/wanghuangjie/KeyPilot/releases"] && !kpGet[@"app"], @"  ... not installed: GET, its releases page");
        Expect([kpOpen[@"button"] isEqual:@"OPEN"] && [kpOpen[@"app"] isEqual:@"com.whj.keypilot.app"] && !kpOpen[@"url"], @"  ... installed: OPEN, its app by bundle ID (no URL scheme)");
        Expect([kpOpen[@"title"] isEqual:@"KeyPilot"] && [kpOpen[@"subtitle"] isEqual:@"by wanghuangjie"], @"  ... the same name either way");
        printf("test-choicepage: %d/%d passed\n", gN - gFail, gN);
    }
    return gFail ? 1 : 0;
}
