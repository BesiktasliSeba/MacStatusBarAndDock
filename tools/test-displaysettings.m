// test-displaysettings.m -- Mac test of what a display's rows show and of the one writer (1.8.7 commits 11 and 12; common/DisplayRowStore.h),
// which the Display Settings window (SpringBoard) and Settings' Displays page both use: run against the Mac's own cfprefsd in scratch domains
// (MSBD_DISP_DOMAIN and the two iPad domains, given by tools/test-displaysettings.sh) with a scratch crash guard list (MSBD_GUARD_RECENT).
#import <Foundation/Foundation.h>
#include "../common/DisplayRowStore.h"

static int fails = 0, passes = 0;
#define EXPECT(c, msg) do { if (c) passes++; else { fails++; printf("FAIL  %s\n", msg); } } while (0)
static NSString *const TV = @"u-4C2D0372-0000-0000-0120-0103808E5078", *const OLD = @"u-4C2DFF71-0000-0000-0120-0103808E5078";
static void setIn(CFStringRef dom, NSString *k, id v) { CFPreferencesSetValue((__bridge CFStringRef)k, (__bridge CFPropertyListRef)v, dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost); CFPreferencesSynchronize(dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost); }
static id shown(NSString *d, const char *rowId, int *from) { return MSBDDispRowShownValue(MSBDDispStoreAll(), d, MSBDDispRowById(rowId), from); }
static NSString *recent(void) { return [NSString stringWithContentsOfFile:@MSBD_GUARD_RECENT encoding:NSUTF8StringEncoding error:nil] ?: @""; }

int main(void) {
    @autoreleasepool {
        CFStringRef D = CFSTR(MSBD_DISP_DOMAIN), B = CFSTR(MSBD_DISP_MSB_DOMAIN), K = CFSTR(MSBD_DISP_DOCK_DOMAIN);
        // the registry as SpringBoard writes it: the TV connected with its desktop, an older display remembered
        setIn(D, @MSBD_DISP_CONNECTED_KEY, @[TV]);
        setIn(D, [TV stringByAppendingString:@"/info"], @{ @"name": @"SAMSUNG", @"px": @"3840x2160", @"desktop": @YES, @"lastSeen": @200 });
        setIn(D, [OLD stringByAppendingString:@"/info"], @{ @"name": @"SAMSUNG", @"px": @"2560x1440", @"lastSeen": @100 });
        NSDictionary *all = MSBDDispStoreAll();
        EXPECT([MSBDDispStoreRemembered(all) isEqualToArray:(@[TV, OLD])], "remembered: the connected one first, then the one seen most recently");
        EXPECT([MSBDDispStoreMode(MSBDDispStoreInfo(all, TV)) isEqualToString:@"3840 x 2160"] && [MSBDDispStoreName(MSBDDispStoreInfo(all, TV)) isEqualToString:@"SAMSUNG"], "name and mode from the registry");
        EXPECT([MSBDDispStoreName(nil) isEqualToString:@"External Display"], "no name read: External Display");
        // the iPad's values, read only (never set: the row's iPad default; the guard's false for Menu Bar Size is Small)
        int from = -1;
        EXPECT([shown(TV, "DOCK_SIZE", &from) doubleValue] == 0.85 && from == kMSBDDispFromIPad, "never set anywhere: the iPad's default, from the iPad");
        setIn(K, @"dockIconSize", @0.6); setIn(B, @"menuBarSize", @2); setIn(B, @"windowSize", @"small"); setIn(K, @"showTrash", @NO);
        EXPECT([shown(TV, "DOCK_SIZE", NULL) doubleValue] == 0.6 && [shown(TV, "MENU_BAR_SIZE", NULL) intValue] == 2 && [shown(TV, "WINDOW_SIZE", NULL) isEqual:@"small"], "no override: the TV follows the iPad live");
        setIn(B, @"menuBarSize", @NO);
        EXPECT([shown(TV, "MENU_BAR_SIZE", NULL) intValue] == 0, "the crash guard's false for Menu Bar Size reads as Small");
        setIn(B, @"menuBarSize", @2);
        EXPECT([shown(TV, "SHOW_TRASH", &from) boolValue] && from == kMSBDDispFromDefault, "Show Trash in Dock: on for the TV with the iPad's off (its display default)");
        EXPECT(![shown(nil, "SHOW_TRASH", &from) boolValue] && from == kMSBDDispFromIPad, "the iPad itself: its own value");
        // a change through the writer (what the window and the page both call)
        EXPECT([MSBDDispStoreWrite(TV, "dock", "dockIconSize", @1.0, NO, @"Dock Size") isEqualToString:[TV stringByAppendingString:@"/dock/dockIconSize"]], "the writer: the flat key");
        EXPECT([shown(TV, "DOCK_SIZE", &from) doubleValue] == 1.0 && from == kMSBDDispFromOverride, "... the TV's own from then");
        setIn(K, @"dockIconSize", @0.77);
        EXPECT([shown(TV, "DOCK_SIZE", NULL) doubleValue] == 1.0, "... and it sticks while the iPad's changes");
        CFPreferencesSynchronize(K, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        EXPECT([(__bridge_transfer id)CFPreferencesCopyValue(CFSTR("dockIconSize"), K, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) doubleValue] == 0.77, "the iPad's own key never written by the writer");
        MSBDDispStoreWrite(TV, "msb", "menuBarSize", @2, NO, @"Menu Bar Size");
        EXPECT([shown(TV, "MENU_BAR_SIZE", &from) intValue] == 2 && from == kMSBDDispFromOverride, "an override equal to the iPad's still sticks (KT: from then it sticks)");
        // wrong forms count as not set (never clamped)
        setIn(D, [TV stringByAppendingString:@"/msb/windowSize"], @3);
        EXPECT([shown(TV, "WINDOW_SIZE", &from) isEqual:@"small"] && from == kMSBDDispFromIPad, "a number for a text choice: not set, the iPad's");
        setIn(D, [TV stringByAppendingString:@"/dock/magnification"], @9.0);
        EXPECT([shown(TV, "MAGNIFICATION_AMOUNT", &from) doubleValue] == 1.22 && from == kMSBDDispFromIPad, "a number out of range: not set");
        setIn(D, [TV stringByAppendingString:@"/msb/menuBarSize"], @"Large");
        EXPECT([shown(TV, "MENU_BAR_SIZE", &from) intValue] == 2 && from == kMSBDDispFromIPad, "a text for a numeric choice: not set");
        setIn(D, [TV stringByAppendingString:@"/msb/menuBarSize"], @5);
        EXPECT([shown(TV, "MENU_BAR_SIZE", &from) intValue] == 2 && from == kMSBDDispFromIPad, "a numeric choice out of range: not set (never clamped)");
        setIn(D, [TV stringByAppendingString:@"/msb/menuBarSize"], @YES);
        EXPECT([shown(TV, "MENU_BAR_SIZE", &from) intValue] == 2 && from == kMSBDDispFromIPad, "a switch for a numeric choice: not set");
        setIn(D, [TV stringByAppendingString:@"/msb/newWindowsFill"], @1);
        EXPECT([shown(TV, "NEW_WINDOWS_FILL", &from) boolValue] && from == kMSBDDispFromOverride, "a switch stored as the number 1 (defaults write -int) is taken");
        // switches and the crash guard's list
        unlink(MSBD_GUARD_RECENT);
        MSBDDispStoreWrite(TV, "msb", "autoHideStatusBar", (__bridge id)kCFBooleanTrue, NO, @"Automatically Hide and Show the Menu Bar");
        EXPECT(([recent() containsString:[NSString stringWithFormat:@" %s %@/msb/autoHideStatusBar Automatically Hide", MSBD_DISP_DOMAIN, TV]]), "a switch turned on for a display: its RecentlyOn line by the flat key");
        MSBDDispStoreWrite(TV, "msb", "autoHideStatusBar", (__bridge id)kCFBooleanFalse, YES, @"Automatically Hide and Show the Menu Bar");
        EXPECT(![recent() containsString:@"autoHideStatusBar"], "... turned off: the line goes");
        MSBDDispStoreWrite(TV, "dock", "showTrash", (__bridge id)kCFBooleanFalse, YES, @"Show Trash in Dock");
        EXPECT(![shown(TV, "SHOW_TRASH", &from) boolValue] && from == kMSBDDispFromOverride, "the TV's Trash off for itself");
        MSBDDispStoreWrite(TV, "dock", "showTrash", nil, NO, @"Show Trash in Dock");
        EXPECT([shown(TV, "SHOW_TRASH", &from) boolValue] && from == kMSBDDispFromDefault, "its reset: back to the display default (on)");
        EXPECT(MSBDDispStoreWrite(TV, "msb", "a/b", @1, NO, nil) == nil && MSBDDispStoreWrite(nil, "msb", "menuBarSize", @1, NO, nil) == nil && MSBDDispStoreWrite(TV, "xyz", "menuBarSize", @1, NO, nil) == nil, "a key the layer refuses is not written");
        // the master switch off: every override dormant
        setIn(D, @MSBD_DISP_MASTER_KEY, @NO);
        EXPECT([shown(TV, "DOCK_SIZE", &from) doubleValue] == 0.77 && from == kMSBDDispFromIPad && [shown(TV, "SHOW_TRASH", NULL) boolValue], "Display Settings off: the iPad's values, the display defaults stand");
        setIn(D, @MSBD_DISP_MASTER_KEY, nil);
        // Use iPad Settings and Forget
        MSBDDispStoreWrite(OLD, "dock", "dockIconSize", @0.5, NO, nil);
        MSBDDispStoreWrite(TV, "msb", "autoHideStatusBar", (__bridge id)kCFBooleanTrue, NO, @"Automatically Hide and Show the Menu Bar");
        int n = MSBDDispStoreUseIPad(TV);
        all = MSBDDispStoreAll();
        BOOL tvLeft = NO; for (NSString *k in all) if ([k hasPrefix:[TV stringByAppendingString:@"/"]] && ![k hasSuffix:@"/info"]) tvLeft = YES;
        EXPECT(n >= 4 && !tvLeft && MSBDDispStoreInfo(all, TV) && [all[[OLD stringByAppendingString:@"/dock/dockIconSize"]] doubleValue] == 0.5, "Use iPad Settings: that display's overrides go, its info and other displays' stay");
        EXPECT(![recent() containsString:@"autoHideStatusBar"], "... a switch's crash guard line with them");
        EXPECT([shown(TV, "SHOW_TRASH", NULL) boolValue], "... the Trash back to its display default (open question 1's default)");
        // Use iPad Settings and its button: the rows' own keys only (shown or not), never More Space's records (review: the crash revert's record kept)
        NSString *pend = [TV stringByAppendingString:@"/disp/" MSBD_DISP_SCALE_PENDING_KEY], *req = [TV stringByAppendingString:@"/disp/" MSBD_DISP_SCALE_REQUEST_KEY];
        setIn(D, pend, @{ @"old": @1, @"new": @2, @"at": @((long)time(NULL)) }); setIn(D, req, @2);
        all = MSBDDispStoreAll();
        EXPECT(!MSBDDispStoreHasOwn(all, TV) && MSBDDispStoreOwnKeys(all, TV).count == 0, "only More Space's records: no change of this display's (the button greyed in both hosts)");
        EXPECT(MSBDDispStoreUseIPad(TV) == 0 && [MSBDDispStoreAll()[pend] isKindOfClass:[NSDictionary class]] && MSBDDispStoreAll()[req], "... Use iPad Settings: 0 changes, the pending record and the request kept");
        setIn(D, [TV stringByAppendingString:@"/disp/scale"], @2);
        EXPECT(!MSBDDispStoreHasOwn(MSBDDispStoreAll(), TV), "the Resolution row's key is Apple's store, not an own setting");
        setIn(D, [TV stringByAppendingString:@"/disp/scale"], nil);
        setIn(D, [TV stringByAppendingString:@"/msb/windowSize"], @3);
        EXPECT(!MSBDDispStoreHasOwn(MSBDDispStoreAll(), TV), "an override of the wrong form: no change shown, the button greyed");
        MSBDDispStoreWrite(TV, "dock", "showTrash", (__bridge id)kCFBooleanFalse, YES, @"Show Trash in Dock");
        EXPECT(MSBDDispStoreHasOwn(MSBDDispStoreAll(), TV), "a row's change, shown or not (the TV's Trash, hidden with Finder off): offered in both hosts");
        EXPECT(MSBDDispStoreUseIPad(TV) == 2 && [MSBDDispStoreAll()[pend] isKindOfClass:[NSDictionary class]] && MSBDDispStoreAll()[req], "... Use iPad Settings: both rows' keys go, More Space's records stay");
        EXPECT([shown(TV, "SHOW_TRASH", NULL) boolValue] && !MSBDDispStoreHasOwn(MSBDDispStoreAll(), TV), "... the TV's Trash back on");
        setIn(D, pend, nil); setIn(D, req, nil);
        // "has our Dock": the line on and the Dock's own switch not off (only a stored false), the same for the window and the page
        EXPECT(MSBDDispStoreOurDock(YES), "the Dock's line on, its switch never set: our Dock");
        setIn(K, @"tweakEnabled", @YES); EXPECT(MSBDDispStoreOurDock(YES), "... its switch on: our Dock");
        setIn(K, @"tweakEnabled", @NO); EXPECT(!MSBDDispStoreOurDock(YES), "... its switch off (MacDock loaded): no Dock rows, in both hosts");
        setIn(K, @"tweakEnabled", nil); setIn(K, @"tweakEnabled", @0); EXPECT(MSBDDispStoreOurDock(YES), "... a number stored: not a switch's false (as Dock.x reads it)");
        setIn(K, @"tweakEnabled", nil); EXPECT(!MSBDDispStoreOurDock(NO), "the line off (not loaded, Choicy / iCleaner), its switch unset: no Dock rows");
        setIn(K, @"tweakEnabled", @YES); EXPECT(!MSBDDispStoreOurDock(NO), "... the line off with its switch on: none either");
        setIn(K, @"tweakEnabled", nil);
        EXPECT(MSBDDispStoreForget(TV) == -1 && MSBDDispStoreInfo(MSBDDispStoreAll(), TV), "Forget refuses a display connected now");
        EXPECT(MSBDDispStoreForget(OLD) == 2, "Forget This Display: its info and its overrides");
        all = MSBDDispStoreAll();
        BOOL oldLeft = NO; for (NSString *k in all) if ([k hasPrefix:[OLD stringByAppendingString:@"/"]]) oldLeft = YES;
        EXPECT(!oldLeft && [MSBDDispStoreRemembered(all) isEqualToArray:(@[TV])], "... nothing of it left; the TV kept");
        // the window and the page write the same keys: the rows' flat keys
        for (int i = 0; i < MSBD_DISP_ROW_COUNT; i++) {
            const MSBDDispRow *r = MSBDDispRowAt(i);
            EXPECT(([MSBDDispRowFlat(TV, r) isEqualToString:[NSString stringWithFormat:@"%@/%s/%s", TV, r->part, r->key]]), "a row's flat key: <display>/<part>/<key>");
        }
        // the displays domain's two switches (the crash guard's targets displaySettings and displayScale): their rows in Settings write them back on
        all = MSBDDispStoreAll();
        EXPECT(MSBDDispStoreSwitchOn(all, MSBD_DISP_MASTER_KEY) && MSBDDispStoreSwitchOn(all, MSBD_DISP_SCALE_SWITCH_KEY), "both switches: on when never set");
        EXPECT(!MSBDDispStoreScaleSwitchShown(all), "More Space's switch: not offered while on with no display listing two scales (the A12Z's and the iPad 2's TVs)");
        EXPECT(MSBDDispStoreSetSwitch(MSBD_DISP_SCALE_SWITCH_KEY, NO) && !MSBDDispStoreSwitchOn(MSBDDispStoreAll(), MSBD_DISP_SCALE_SWITCH_KEY) && !MSBDDispStoreScaleOn(MSBDDispStoreAll()), "More Space off (as the guard's step sets it)");
        EXPECT(MSBDDispStoreScaleSwitchShown(MSBDDispStoreAll()), "... its switch offered while off, so it can be switched back on");
        EXPECT(MSBDDispStoreSetSwitch(MSBD_DISP_SCALE_SWITCH_KEY, YES) && MSBDDispStoreScaleOn(MSBDDispStoreAll()), "... and back on through it");
        setIn(D, [OLD stringByAppendingString:@"/info"], @{ @"name": @"Monitor", @"scales": @(2 | 4), @"lastSeen": @50 });
        EXPECT(MSBDDispStoreScaleSwitchShown(MSBDDispStoreAll()), "More Space's switch offered once a remembered display lists two scales");
        setIn(D, [OLD stringByAppendingString:@"/info"], nil);
        setIn(D, @MSBD_DISP_MASTER_KEY, @NO);
        EXPECT(MSBDDispStoreSetSwitch(MSBD_DISP_MASTER_KEY, YES) && MSBDDispStoreLayerOn(MSBDDispStoreAll()), "Display Settings set off by the guard: switched back on through its row");
        EXPECT(!MSBDDispStoreSetSwitch("menuBarSize", NO) && !MSBDDispStoreSetSwitch(NULL, NO), "the switches' writer writes those two keys only");
        // "connected" where SpringBoard's part does not keep it (Display Settings off, the stock bar, Mac Status Bar off): let go, so a TV gone since is
        // Not Connected with Forget, and the store refuses nothing
        setIn(D, @MSBD_DISP_MASTER_KEY, @NO);
        setIn(D, @MSBD_DISP_CONNECTED_KEY, @[TV]);
        EXPECT(MSBDDispStoreForget(TV) == -1, "a stale connected list: Forget refused (the finding's state)");
        EXPECT(MSBDDispStoreDropConnected(), "the master switch off: the connected list let go");
        all = MSBDDispStoreAll();
        EXPECT(MSBDDispStoreConnected(all).count == 0 && all[@MSBD_DISP_CONNECTED_KEY] == nil && MSBDDispStoreInfo(all, TV), "... only that key: the TV's info stays");
        EXPECT([MSBDDispStoreRemembered(all) isEqualToArray:(@[TV])] && ![MSBDDispStoreConnected(all) containsObject:TV], "... so Settings lists it Not Connected, with Forget offered");
        EXPECT(!MSBDDispStoreDropConnected(), "... nothing to let go a second time: no write");
        setIn(D, @MSBD_DISP_CONNECTED_KEY, @[]);
        EXPECT(!MSBDDispStoreDropConnected(), "an empty list: nothing written");
        EXPECT(MSBDDispStoreForget(TV) >= 1 && !MSBDDispStoreInfo(MSBDDispStoreAll(), TV), "Forget This Display then takes it (the store refuses nothing)");
        setIn(D, @MSBD_DISP_MASTER_KEY, nil);
        printf("test-displaysettings: %d passed, %d failed\n", passes, fails);
    }
    return fails ? 1 : 0;
}
