// test-choicybool.m -- Mac test of Choicy's switches as the root helper and Settings read them (1.8.7.5, audit L23 of 1.8.7.2): a value in
// Choicy's SpringBoard block that is no switch (an array, a dictionary, data, a date: a damaged file, or another package's write) is off, never
// an exception; a number or a string reads as Choicy reads it (-boolValue). Run on the real code: common/ExclusiveChoice.h (CB_X: the code as
// built, or another copy) and sshtoggled's MacStatusBarSwitchedOff with its ChoicyMode, Exists and IsRegular cut out of main.m (cut.inc, made by
// tools/test-choicybool.sh), with Choicy's file in a scratch folder (CB_DIR). Each scenario on its own: an exception is caught and counted, so
// the code before the fix shows every case it raised on.
#import <Foundation/Foundation.h>
#include <sys/stat.h>
#include "../common/DpkgState.h"
#include CB_X
#define TWEAKDIR CB_DIR "/TweakInject"
#define PREFSDIR CB_DIR "/Preferences"
#include "cut.inc"

static int gN = 0, gFail = 0;
static void Expect(BOOL ok, NSString *what) { gN++; if (!ok) { gFail++; printf("  FAIL %s\n", what.UTF8String); } else printf("  ok   %s\n", what.UTF8String); }
// Runs one scenario; NO (and the exception's name) when it raised.
static BOOL Survives(NSString **raised, void (^b)(void)) {
    @try { b(); return YES; } @catch (NSException *e) { *raised = e.name; return NO; }
}
static NSMutableDictionary *Deep(NSDictionary *d) {   // (a deep mutable copy: what the helper and Settings read from the file)
    return (NSMutableDictionary *)CFBridgingRelease(CFPropertyListCreateDeepCopy(NULL, (__bridge CFDictionaryRef)d, kCFPropertyListMutableContainersAndLeaves));
}
static NSString *const kChoicyStatus = @"Package: com.opa334.choicy\nStatus: install ok installed\nVersion: 1.6\n\n";

int main(void) {
    @autoreleasepool {
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:@CB_DIR "/Preferences" withIntermediateDirectories:YES attributes:nil error:nil];
        [fm createDirectoryAtPath:@CB_DIR "/TweakInject" withIntermediateDirectories:YES attributes:nil error:nil];
        [@"x" writeToFile:@CB_DIR "/TweakInject/MacStatusBar.dylib" atomically:NO encoding:NSUTF8StringEncoding error:nil];
        NSString *file = @CB_DIR "/Preferences/com.opa334.choicyprefs.plist";
        // the values: what each one must read as (Choicy reads its switches with -boolValue)
        NSArray *names = @[@"an array", @"a dictionary", @"data", @"a date", @"@YES", @"@\"1\"", @"@0", @"@\"YES\"", @"@\"0\"", @"missing"];
        NSArray *vals = @[@[@YES], @{@"on": @YES}, [NSData dataWithBytes:"\x01" length:1], [NSDate dateWithTimeIntervalSince1970:1793000000], @YES, @"1", @0, @"YES", @"0", [NSNull null]];
        BOOL want[] = { NO, NO, NO, NO, YES, YES, NO, YES, NO, NO };
        for (NSUInteger i = 0; i < names.count; i++) {
            NSString *n = names[i]; id v = vals[i] == [NSNull null] ? nil : vals[i]; BOOL on = want[i];
            printf("customTweakConfigurationEnabled = %s (reads %s):\n", n.UTF8String, on ? "on" : "off");
            // 1. ExclusiveChoice.h MSBDExChoicyApply (the helper's ChoicyApplyChoices and Settings' pick): SpringBoard's own allow list follows
            //    the pick only where Choicy's custom configuration for SpringBoard is on
            NSMutableDictionary *sb = [NSMutableDictionary dictionaryWithDictionary:@{@"allowDenyMode": @1, @"allowedTweaks": @[@"MacStatusBar", @"Zetsu"]}];
            if (v) sb[@"customTweakConfigurationEnabled"] = v;
            NSMutableDictionary *prefs = Deep(@{@"globalDeniedTweaks": @[], @"appSettings": @{@"com.apple.springboard": sb}}), *record = [NSMutableDictionary dictionary];
            __block BOOL changed = NO; NSString *raised = nil;
            BOOL ok = Survives(&raised, ^{ changed = MSBDExChoicyApply(prefs, record, @[@"Aerial"], @[@"Zetsu"], @[], [NSMutableArray array]); });
            NSArray *allowed = prefs[@"appSettings"][@"com.apple.springboard"][@"allowedTweaks"];
            Expect(ok && changed && [prefs[@"globalDeniedTweaks"] isEqual:@[@"Zetsu"]]
                   && (on ? [allowed isEqual:(@[@"MacStatusBar", @"Aerial"])] && [record[@"springboard.allowedTweaks"] isEqual:(@{@"Aerial": @"added", @"Zetsu": @"removed"})]
                          : [allowed isEqual:(@[@"MacStatusBar", @"Zetsu"])] && !record[@"springboard.allowedTweaks"]),
                   [NSString stringWithFormat:@"MSBDExChoicyApply: %@%@", on ? @"SpringBoard's allow list follows the pick" : @"the global list only, SpringBoard's list left alone",
                    ok ? @"" : [NSString stringWithFormat:@" -- raised %@", raised]]);
            // 2. sshtoggled MacStatusBarSwitchedOff (its watcher, every apply, the slow fallback): Mac Status Bar left out of SpringBoard's allow
            //    list is a switch-off only where the custom configuration is on
            NSMutableDictionary *fsb = [NSMutableDictionary dictionaryWithDictionary:@{@"allowDenyMode": @1, @"allowedTweaks": @[@"Aerial"]}];
            if (v) fsb[@"customTweakConfigurationEnabled"] = v;
            [@{@"globalDeniedTweaks": @[], @"appSettings": @{@"com.apple.springboard": fsb}} writeToFile:file atomically:YES];
            __block BOOL off = NO; __block NSString *how = nil; raised = nil;
            ok = Survives(&raised, ^{ off = MacStatusBarSwitchedOff(kChoicyStatus, &how); });
            Expect(ok && off == on && (!on || [how isEqualToString:@"Choicy (SpringBoard)"]),
                   [NSString stringWithFormat:@"MacStatusBarSwitchedOff: %@%@", on ? @"switched off in Choicy (SpringBoard)" : @"not switched off",
                    ok ? @"" : [NSString stringWithFormat:@" -- raised %@", raised]]);
            // 3. ExclusiveChoice.h MSBDExUserOff (the defaults' and Control Center Style's reader): named in SpringBoard's deny list is the user's
            //    own switch-off only where the custom configuration is on (as before: this one never raised)
            NSMutableDictionary *usb = [NSMutableDictionary dictionaryWithDictionary:@{@"allowDenyMode": @2, @"deniedTweaks": @[@"BigSurCenter"]}];
            if (v) usb[@"customTweakConfigurationEnabled"] = v;
            __block BOOL userOff = NO; raised = nil;
            ok = Survives(&raised, ^{ userOff = MSBDExUserOff(@"BigSurCenter", @{@"appSettings": @{@"com.apple.springboard": usb}}, nil, @[], YES, NO); });
            Expect(ok && userOff == on, [NSString stringWithFormat:@"MSBDExUserOff: %@%@", on ? @"the user's own switch-off" : @"not the user's",
                                         ok ? @"" : [NSString stringWithFormat:@" -- raised %@", raised]]);

            printf("tweakInjectionDisabled = %s (reads %s), custom configuration on:\n", n.UTF8String, on ? "on" : "off");
            // 4. MacStatusBarSwitchedOff: every tweak off in SpringBoard is not a switch-off of ours; off, Mac Status Bar left out of the allow list is
            NSMutableDictionary *tsb = [NSMutableDictionary dictionaryWithDictionary:@{@"customTweakConfigurationEnabled": @YES, @"allowDenyMode": @1, @"allowedTweaks": @[@"Aerial"]}];
            if (v) tsb[@"tweakInjectionDisabled"] = v;
            [@{@"appSettings": @{@"com.apple.springboard": tsb}} writeToFile:file atomically:YES];
            off = NO; how = nil; raised = nil;
            ok = Survives(&raised, ^{ off = MacStatusBarSwitchedOff(kChoicyStatus, &how); });
            Expect(ok && off == !on, [NSString stringWithFormat:@"MacStatusBarSwitchedOff: %@%@", on ? @"every tweak off in SpringBoard -- not a switch-off of ours" : @"switched off in Choicy (SpringBoard)",
                                      ok ? @"" : [NSString stringWithFormat:@" -- raised %@", raised]]);

            printf("overwriteGlobalTweakConfiguration = %s (reads %s), SpringBoard's deny list in force:\n", n.UTF8String, on ? "on" : "off");
            // 5. MSBDExChoicyApply with SpringBoard's deny list: the libraries kept out are listed there only where it overrides the global list
            NSMutableDictionary *osb = [NSMutableDictionary dictionaryWithDictionary:@{@"customTweakConfigurationEnabled": @YES, @"allowDenyMode": @2, @"deniedTweaks": @[@"Aerial"]}];
            if (v) osb[@"overwriteGlobalTweakConfiguration"] = v;
            prefs = Deep(@{@"globalDeniedTweaks": @[], @"appSettings": @{@"com.apple.springboard": osb}}); record = [NSMutableDictionary dictionary];
            changed = NO; raised = nil;
            ok = Survives(&raised, ^{ changed = MSBDExChoicyApply(prefs, record, @[@"Aerial"], @[@"Zetsu"], @[], [NSMutableArray array]); });
            NSArray *denied = prefs[@"appSettings"][@"com.apple.springboard"][@"deniedTweaks"];
            Expect(ok && changed && [denied isEqual:on ? @[@"Zetsu"] : @[]], [NSString stringWithFormat:@"MSBDExChoicyApply: Aerial out of SpringBoard's deny list%@%@",
                                     on ? @", Zetsu in it (it overrides the global list)" : @", Zetsu only in the global list", ok ? @"" : [NSString stringWithFormat:@" -- raised %@", raised]]);
        }
        // the rest of the block as before: a block that is no dictionary, Choicy's global list
        [@{@"appSettings": @{@"com.apple.springboard": @[@"x"]}} writeToFile:file atomically:YES];
        NSString *how = nil;
        Expect(!MacStatusBarSwitchedOff(kChoicyStatus, &how), @"SpringBoard's block that is no dictionary: not switched off (as before)");
        [@{@"globalDeniedTweaks": @[@"MacStatusBar"]} writeToFile:file atomically:YES];
        Expect(MacStatusBarSwitchedOff(kChoicyStatus, &how) && [how isEqualToString:@"Choicy (all processes)"], @"Mac Status Bar in Choicy's global list: switched off (as before)");
        Expect(!MacStatusBarSwitchedOff(@"", &how), @"Choicy not installed: not switched off (as before)");
    }
    printf("test-choicybool (compiled): %d checks, %d failed\n", gN, gFail);
    return gFail ? 1 : 0;
}
