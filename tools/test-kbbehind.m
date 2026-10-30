// test-kbbehind.m -- Mac test of which windows may not take the hardware keyboard (statusbar/KeyboardBehind.h, used by StatusBar.x
// DMKeyboardFocusBehindWindows): KT's 30 Oct case (Amazon's window behind Settings' must not get the keys back), the active app's windows never kept
// from it, nothing without a hardware keyboard or without a window engine of SpringBoard's windows.
#import <Foundation/Foundation.h>
#include "../statusbar/KeyboardBehind.h"
static int fails = 0, checks = 0;
static void Expect(const char *what, NSSet *got, NSArray *want) {
    checks++; NSSet *w = [NSSet setWithArray:want];
    if (![got isEqualToSet:w]) { fails++; printf("FAIL  %s (got %s, want %s)\n", what, [[got.allObjects componentsJoinedByString:@","] UTF8String], [[want componentsJoinedByString:@","] UTF8String]); }
    else printf("PASS  %s\n", what);
}
int main(void) {
    @autoreleasepool {
        NSString *amazon = @"com.amazon.Amazon", *prefs = @"com.apple.Preferences", *maps = @"com.apple.Maps";
        Expect("KT: Settings' window in front of Amazon's (hardware keyboard): Amazon's kept from the keys", MSBDKeyboardBehind(@[amazon, prefs], prefs, YES, YES), @[amazon]);
        Expect("  ... and once Amazon is clicked to the front: Settings' kept, Amazon types", MSBDKeyboardBehind(@[amazon, prefs], amazon, YES, YES), @[prefs]);
        Expect("three windows: every one but the active app's", MSBDKeyboardBehind(@[amazon, maps, prefs], maps, YES, YES), (@[amazon, prefs]));
        Expect("an app with two windows, active: neither kept", MSBDKeyboardBehind(@[prefs, prefs, maps], prefs, YES, YES), @[maps]);
        Expect("no active app (the Home Screen, or Finder's window in front): every window kept", MSBDKeyboardBehind(@[amazon, prefs], nil, YES, YES), (@[amazon, prefs]));
        Expect("a full-screen app active (a tap reclaimed it), windows behind: every window kept", MSBDKeyboardBehind(@[amazon, prefs], @"com.apple.mobilesafari", YES, YES), (@[amazon, prefs]));
        Expect("no hardware keyboard: nothing kept (each app's keyboard comes with a tap in its own field, as before)", MSBDKeyboardBehind(@[amazon, prefs], prefs, NO, YES), @[]);
        Expect("no window engine of SpringBoard's windows (Stage Manager, none): nothing kept", MSBDKeyboardBehind(@[amazon, prefs], prefs, YES, NO), @[]);
        Expect("one window, active: nothing kept", MSBDKeyboardBehind(@[prefs], prefs, YES, YES), @[]);
        Expect("a window without a bundle: never named", MSBDKeyboardBehind(@[@"", prefs], nil, YES, YES), @[prefs]);
    }
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
