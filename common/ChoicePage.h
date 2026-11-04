// ChoicePage.h -- the rows of our choice pages (1.8.0): a choice whose options are our own and Apple's ("Native") and other tweaks' ("Third-Party",
// with its developer's page behind a GET button while it is not installed, where there is one), only one of them loaded (common/ExclusiveChoice.h).
// Window Engine (since 1.5.2: the Windows & Multitasking page), Control Center Style (common/CCStyle.h) and Banner Style (common/BannerStyle.h,
// item 2). What each row shows, from the state it is given -- pure, so the Mac test runs every case (tools/test-choicepage.sh);
// MSBRootListController.m's MSBChoiceListController reads the state on the iPad and draws the rows: its groups, its checkmark, its GET button or the
// reason where the checkmark would be.
// A row is a dictionary:
//  - state: 2 it can be picked, 1 it can be picked and runs on its own (an untested engine build, its title says so), 0 greyed and not picked --
//    then url (its GET button: the developer's page) or reason (in grey where the checkmark would be), or neither;
//  - native: in the Native group, else Third-Party; hidden: left off the page (not offered on this iPadOS); title: instead of the plist's.
#pragma once
#import <Foundation/Foundation.h>
#include "CCStyle.h"
#include "BannerStyle.h"

#define kMSBDChoiceGetAerial   @"https://github.com/uz-ra"                         // (the GitHub link in Aerial's own Settings bundle)
#define kMSBDChoiceGetZetsu    @"https://dcsyhi1998.github.io/depiction/zetsu"     // (its developer's GitHub-hosted page)
#define kMSBDChoiceGetMilkyWay @"https://akusio.github.io/"                        // (the same)
// BigSurCenter's: its developer's own page (nicho1asdev, on the Havoc repository), whichever repository an installed copy came from.
#define kMSBDChoiceGetBigSurCenter @"https://havoc.app/package/bigsurcenter"

static inline NSDictionary *MSBDChoiceRowMake(int state, BOOL native, NSString *title, NSString *reason, NSString *url, BOOL hidden) {
    NSMutableDictionary *r = [NSMutableDictionary dictionaryWithDictionary:@{@"state": @(state), @"native": @(native), @"hidden": @(hidden)}];
    if (title) r[@"title"] = title;
    if (reason) r[@"reason"] = reason;
    if (url) r[@"url"] = url;
    return r;
}
// Window Engine: state as OwnPageState.h's MSBDEngineState (0 not installed, 1 an installed build not tested with us, 2 tested); nameVersion: the
// engine with its package's version ("Aerial 5.1"); Stage Manager: smAvailable (Stage Manager on this iPad, natively or through TrollPad) and
// smVerdict (the engine's check on this build: 1 passed, 0 failed, -1 not checked yet).
static inline NSDictionary *MSBDChoiceEngineRow(NSString *value, int state, NSString *nameVersion, BOOL smAvailable, int smVerdict) {
    if ([value isEqualToString:@"stagemanager"]) {   // (greyed, and why, where it can't run yet; no GET: it is Apple's)
        NSString *reason = smAvailable && smVerdict != 1 ? (smVerdict == 0 ? @"Not Supported Yet" : @"Respring to Check") : nil;   // (not checked: SpringBoard checks at its start)
        return MSBDChoiceRowMake(state, YES, nil, reason, nil, NO);
    }
    NSDictionary *pages = @{@"aerial": kMSBDChoiceGetAerial, @"zetsu": kMSBDChoiceGetZetsu, @"milkyway": kMSBDChoiceGetMilkyWay};
    NSString *title = state == 1 ? [NSString stringWithFormat:@"%@ (Untested, Runs on Its Own)", nameVersion ?: value] : nil;   // (never "Recommended": not tested)
    return MSBDChoiceRowMake(state, NO, title, nil, state == 0 ? pages[value] : nil, NO);
}
// Control Center Style: osMajor, our own Control Center's verdict on this build (macVerdict, CCStyleNow.h) and whether this build has it
// (macBuilt), BigSurCenter installed, Status Bar Style Stock (stockBar: Mac greyed, our Control Center runs only with the Mac status bar).
static inline NSDictionary *MSBDChoiceCCStyleRow(NSString *value, int osMajor, int macVerdict, BOOL macBuilt, BOOL bscInstalled, BOOL stockBar) {
    if ([value isEqualToString:@"mac"]) {
        int s = MSBDCCMacRowState(osMajor, macVerdict, macBuilt, stockBar);
        return MSBDChoiceRowMake(s == 0 ? 2 : 0, YES, nil, s == 1 ? @"Not Supported Yet" : s == 2 ? @"Respring to Check" : s == 3 ? @"Needs Mac Status Bar" : nil, nil, NO);
    }
    if ([value isEqualToString:@"bigsurcenter"]) {
        int s = MSBDCCBigSurCenterRowState(osMajor, bscInstalled);
        return MSBDChoiceRowMake(s == 2 ? 2 : 0, NO, nil, nil, s == 0 ? kMSBDChoiceGetBigSurCenter : nil, s < 0);
    }
    return MSBDChoiceRowMake(2, YES, nil, nil, nil, NO);   // (iPadOS's own: always there)
}
// The Native group's footer of the Control Center Style page: why Mac is greyed (nil where it can be picked, or in a build without it).
static inline NSString *MSBDChoiceCCStyleNativeFooter(int osMajor, int macVerdict, BOOL macBuilt, NSString *osVersion, BOOL stockBar) {
    if (!macBuilt) return nil;
    if (osMajor > 18) return [NSString stringWithFormat:@"The Mac Control Center isn't available on iPadOS %d yet.", osMajor];
    if (osMajor >= 15 && stockBar) return @"The Mac Control Center works with the Mac status bar. Set Status Bar Style to Mac to use it.";
    if (macVerdict == -1) return @"Respring once to check the Mac Control Center on this iPadOS version.";
    if (macVerdict == 0) return [NSString stringWithFormat:@"The Mac Control Center isn't supported on iPadOS %@ yet.", osVersion.length ? osVersion : @"(this version)"];
    return nil;
}
// Banner Style: Mac and iPadOS (Native) and Destra (Third-Party), always there (KT 3 Nov: Destra visible as an option); Destra greyed "Not
// Installed" while it is not installed, with no GET: there is no page of its developer's left to get it from (BannerStyle.h).
static inline NSDictionary *MSBDChoiceBannerRow(NSString *value, BOOL destraInstalled) {
    if ([value isEqualToString:@"destra"]) {
        int s = MSBDBannerDestraRowState(destraInstalled);
        return MSBDChoiceRowMake(s == 2 ? 2 : 0, NO, nil, s == 2 ? nil : @"Not Installed", nil, NO);
    }
    return MSBDChoiceRowMake(2, YES, nil, nil, nil, NO);   // (ours and iPadOS's own: always there)
}
// The Banner Style page's Third-Party footer: Destra installed but switched off in its own settings shows nothing when picked (nil otherwise).
static inline NSString *MSBDChoiceBannerThirdPartyFooter(BOOL destraInstalled, BOOL destraOwnOn) {
    return destraInstalled && !destraOwnOn ? @"Destra is turned off in its own settings. Turn on Enabled in Settings > Destra to see its banners." : nil;
}
// The Notifications group's footer on the Status Bar page: where ours appear, that only the chosen style loads, Destra picked but switched off in
// its own settings, and what a respring still has to do (note: MSBDBannerRespringNote, from SpringBoard's word) -- or what it can't (3: the words
// of the pick's own alert, Choicy is needed).
static inline NSString *MSBDChoiceBannerGroupFooter(int style, BOOL destraInstalled, BOOL destraOwnOn, int note) {
    NSMutableString *s = [NSMutableString string];
    if (style == kMSBDBannerMac) [s appendString:@"Banners appear at the top right. "];
    [s appendString:@"Only the chosen banner style is loaded."];
    if (style == kMSBDBannerDestra && destraInstalled && !destraOwnOn) [s appendString:@" Destra is turned off in its own settings, so iPadOS's banners are shown."];
    if (note == 1) [s appendString:@" Destra stays loaded until you respring."];
    else if (note == 2) [s appendString:@" Destra loads after a respring."];
    else if (note == 3) [s appendString:@" Install Choicy (or iCleaner Pro) so MacStatusBar&Dock can stop Destra from loading."];
    return s;
}
