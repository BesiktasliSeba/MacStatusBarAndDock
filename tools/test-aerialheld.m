// test-aerialheld.m -- Mac test of Aerial 5's own settings while it is our engine (statusbar/AerialHeld.h): the values held -- its four rows in an
// app icon's Haptic Touch menu off (1.8.1 item 4: Open in Aerial and Remove Stage State too), the rest as before -- and which values in Aerial's
// preferences go into the user's copy (an earlier build's "on" for those two rows is ours, not the user's). Run by test-aerialheld.sh.
#import <Foundation/Foundation.h>
#import "../statusbar/AerialHeld.h"

static int gFail = 0, gN = 0;
static void Check(BOOL ok, NSString *what) {
    gN++;
    if (!ok) { gFail++; printf("  FAIL %s\n", what.UTF8String); } else printf("  ok   %s\n", what.UTF8String);
}
int main(void) {
    @autoreleasepool {
        for (int ios16 = 0; ios16 < 2; ios16++) for (int halves = 0; halves < 2; halves++) {
            NSDictionary *w = MSBDA5HeldPrefs(ios16, halves);
            NSString *on = [NSString stringWithFormat:@"(iOS %d, side halves %d)", ios16 ? 16 : 15, halves];
            Check([w[@"shortcut_openInAerial"] isEqual:@NO] && [w[@"shortcut_removeState"] isEqual:@NO],
                  [@"Open in Aerial and Remove Stage State held off: not in any icon menu " stringByAppendingString:on]);
            Check([w[@"shortcut_flexResize"] isEqual:@NO] && [w[@"shortcut_keyboardAvoidance"] isEqual:@NO], [@"the flex resize and keyboard avoidance rows off, as before " stringByAppendingString:on]);
            Check([w[@"useNewRotationMethod"] isEqual:@(ios16)] && [w[@"contextMenu_showMinimize"] isEqual:@NO] && [w[@"minusHandleDefaultSwipeMode"] isEqual:@1],
                  [@"rotation method by iOS, window menu Minimize off, bottom handle in Resize Mode: as before " stringByAppendingString:on]);
            Check([w[@"contextMenu_showClose"] isEqual:@YES] && [w[@"splitMenu_showUpperHalf"] isEqual:@YES] && [w[@"useNewDesign"] isEqual:@YES], [@"the others at Aerial's default " stringByAppendingString:on]);
            Check(halves ? ([w[@"splitMenu_showLeftHalf"] isEqual:@YES] && [w[@"splitMenu_showRightHalf"] isEqual:@YES]) : (!w[@"splitMenu_showLeftHalf"] && !w[@"splitMenu_showRightHalf"]),
                  [@"5.1's side halves only on a build that has them " stringByAppendingString:on]);
        }
        NSDictionary *wanted = MSBDA5HeldPrefs(NO, YES);
        // the M1 updated from 1.8.0: Aerial's preferences hold 1.8.0's "on" for both rows, the copy (made before our first change) has neither key
        NSMutableDictionary *user = [@{ @"useNewDesign": @YES, @"contextMenu_showMinimize": @NO } mutableCopy];
        NSDictionary *cur = @{ @"useNewDesign": @YES, @"contextMenu_showMinimize": @NO, @"shortcut_openInAerial": @YES, @"shortcut_removeState": @YES, @"shortcut_flexResize": @NO };
        NSArray *rec = MSBDA5RecordUser(user, cur, wanted, YES);
        Check(rec.count == 0 && !user[@"shortcut_openInAerial"] && !user[@"shortcut_removeState"], @"after an update: 1.8.0's \"on\" is ours, the copy keeps Aerial's default (no key)");
        // a user who had Open in Aerial off before our first change: the copy keeps their "off"
        user = [@{ @"shortcut_openInAerial": @NO } mutableCopy];
        rec = MSBDA5RecordUser(user, @{ @"shortcut_openInAerial": @YES }, wanted, YES);
        Check(rec.count == 0 && [user[@"shortcut_openInAerial"] isEqual:@NO], @"after an update: the user's own \"off\" stays in the copy");
        // once the copy is this build's (marked): an "on" set in Aerial's own Settings page is the user's
        user = [@{ @"shortcut_openInAerial": @NO } mutableCopy];
        rec = MSBDA5RecordUser(user, @{ @"shortcut_openInAerial": @YES }, wanted, NO);
        Check([rec isEqual:@[@"shortcut_openInAerial"]] && [user[@"shortcut_openInAerial"] isEqual:@YES], @"marked copy: Open in Aerial switched on in Aerial's Settings is recorded as the user's");
        // our own held value is never recorded, marked or not
        user = [NSMutableDictionary dictionary];
        rec = MSBDA5RecordUser(user, @{ @"shortcut_openInAerial": @NO, @"shortcut_removeState": @NO }, wanted, NO);
        Check(rec.count == 0 && user.count == 0, @"the held \"off\" is ours: nothing recorded");
        // another key changed in Aerial's Settings is the user's either way (as before 1.8.1)
        user = [NSMutableDictionary dictionary];
        rec = MSBDA5RecordUser(user, @{ @"contextMenu_showClose": @NO }, wanted, YES);
        Check([rec isEqual:@[@"contextMenu_showClose"]] && [user[@"contextMenu_showClose"] isEqual:@NO], @"a change of another held key is the user's, before and after the mark");
        // Aerial's own other keys mirror its preferences; per-app keys are never the user's to keep
        user = [@{ @"someAerialKey": @1, @"flexResizeDisabled_com.apple.tips": @YES } mutableCopy];
        rec = MSBDA5RecordUser(user, @{}, wanted, NO);
        Check(!user[@"someAerialKey"] && [user[@"flexResizeDisabled_com.apple.tips"] isEqual:@YES], @"an unheld key gone from Aerial's preferences is dropped from the copy; per-app keys are left");
        Check(MSBDA5IsPerAppKey(@"keyboardAvoidanceEnabled_x") && MSBDA5IsPerAppKey(@"flexResizeDisabled_x") && !MSBDA5IsPerAppKey(@"shortcut_flexResize"), @"per-app keys by name");
        // Down to an earlier build and back up (code review 1.8.1, 6). An earlier build holds both rows on, sees our "off" in Aerial's preferences and records it as the user's (as this code with
        // no earlier values); back here the two rows on at once are not the user's, and the copy gets back what the mark kept. "Clearing the mark" alone would leave the down leg's "off" in the
        // copy: those who had them on, Aerial's default and most people, would lose them. Each kind of user comes back with their own.
        NSMutableDictionary *held180 = [wanted mutableCopy]; held180[@"shortcut_openInAerial"] = @YES; held180[@"shortcut_removeState"] = @YES;
        for (NSDictionary *own in @[ @{}, @{ @"shortcut_openInAerial": @NO, @"shortcut_removeState": @NO }, @{ @"shortcut_openInAerial": @YES, @"shortcut_removeState": @NO }, @{ @"shortcut_openInAerial": @YES, @"shortcut_removeState": @YES } ]) {
            NSMutableDictionary *copy = [own mutableCopy];
            NSDictionary *markHere = MSBDA5MarkValues(copy);   // (this build's last pass)
            NSMutableDictionary *now = [wanted mutableCopy];
            NSString *who = own.count ? [[own description] stringByReplacingOccurrencesOfString:@"\n" withString:@" "] : @"never changed them";
            Check(!MSBDA5EarlierBuildRan(now), [@"on this build: no earlier build seen, user who " stringByAppendingString:who]);
            MSBDA5RecordUser(copy, now, held180, NO);   // (the down leg, as the earlier build's pass)
            Check([copy[@"shortcut_openInAerial"] isEqual:@NO] && [copy[@"shortcut_removeState"] isEqual:@NO], @"  ... the earlier build records this build's off as the user's (the down leg, not ours to fix)");
            now[@"shortcut_openInAerial"] = @YES; now[@"shortcut_removeState"] = @YES;
            Check(MSBDA5EarlierBuildRan(now), @"  ... back up: both rows on at once: an earlier build ran");
            NSArray *back = MSBDA5RecordUser(copy, now, wanted, YES);
            MSBDA5UserBackFromMark(copy, markHere);
            Check(back.count == 0 && [copy isEqualToDictionary:own], [@"  ... the copy as it was before going down, user who " stringByAppendingString:who]);
            NSData *written = [NSPropertyListSerialization dataWithPropertyList:markHere format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];
            Check(written != nil && [[NSPropertyListSerialization propertyListWithData:written options:0 format:NULL error:nil] isEqual:markHere], @"  ... the mark's values are a property list, read back the same");
        }
        Check(!MSBDA5EarlierBuildRan(@{ @"shortcut_openInAerial": @YES, @"shortcut_removeState": @NO }) && !MSBDA5EarlierBuildRan(@{ @"shortcut_removeState": @YES }) && !MSBDA5EarlierBuildRan(@{}), @"one row switched on in Aerial's Settings is no earlier build: the user's, recorded as before");
        NSMutableDictionary *noMark = [@{ @"shortcut_openInAerial": @NO, @"other": @1 } mutableCopy];
        MSBDA5UserBackFromMark(noMark, nil);
        Check([noMark isEqualToDictionary:(@{ @"shortcut_openInAerial": @NO, @"other": @1 })], @"a beta's empty mark: nothing to give back, the copy left as it is");
        NSMutableDictionary *other = [@{ @"shortcut_openInAerial": @NO, @"other": @1 } mutableCopy];
        MSBDA5UserBackFromMark(other, @{});
        Check([other isEqualToDictionary:(@{ @"other": @1 })], @"a mark without a key: that key was not in the copy (Aerial's default); other keys left");
        printf("aerialheld: %d checks, %d failed\n", gN, gFail);
        return gFail ? 1 : 0;
    }
}
