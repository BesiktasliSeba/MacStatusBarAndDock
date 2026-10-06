// Mac test of the words our UI gives VoiceOver and the other assistive features (common/AXText.h, 1.3.7): menu shortcuts in words, the
// Wi-Fi details, the item values, the joins. Every shortcut string the menus use is listed (tools/test-axtext.sh checks the list is complete).
#import <Foundation/Foundation.h>
#include "../common/AXText.h"

static int fails = 0, checks = 0;
static void eq(NSString *what, NSString *got, NSString *want) {
    checks++;
    if (got == want || [got isEqualToString:want]) return;
    fails++;
    printf("FAIL %s: got \"%s\", want \"%s\"\n", what.UTF8String, got ? got.UTF8String : "(nil)", want ? want.UTF8String : "(nil)");
}

int main(int argc, char **argv) {
    @autoreleasepool {
        // every hint the menus set (statusbar/*.x, *.h) -- keep in step with the grep in test-axtext.sh
        NSDictionary<NSString *, NSString *> *menuHints = @{
            @"⌘⌫": @"Command Delete", @"⌘↑": @"Command Up Arrow", @"⌘]": @"Command Right Bracket", @"⌘[": @"Command Left Bracket",
            @"⌘Z": @"Command Z", @"⌘W": @"Command W", @"⌘O": @"Command O", @"⌘M": @"Command M", @"⌘I": @"Command I", @"⌘F": @"Command F",
            @"⌘D": @"Command D", @"⌘C": @"Command C", @"⌘V": @"Command V", @"⌘2": @"Command 2", @"⌘1": @"Command 1", @"⇧⌘Z": @"Shift Command Z",
            @"⇧⌘N": @"Shift Command N", @"⇧⌘G": @"Shift Command G", @"⇧⌘D": @"Shift Command D", @"⇧⌘.": @"Shift Command Period",
            @"⌘A": @"Command A", @"⌘X": @"Command X",
            @"›": @"Submenu", @"↩︎": @"Return", @"Space": @"Space", @"GET": @"Get",
        };
        for (NSString *k in menuHints) eq([NSString stringWithFormat:@"menu hint %@", k], MSBDAXShortcutSpoken(k), menuHints[k]);
        if (argc > 1) {   // (the hints found in the sources, one per argument: each must be in the table above)
            for (int i = 1; i < argc; i++) {
                NSString *h = [NSString stringWithUTF8String:argv[i]];
                h = [h stringByReplacingOccurrencesOfString:@"\\u21A9\\uFE0E" withString:@"↩︎"];
                checks++;
                if (!menuHints[h]) { fails++; printf("FAIL a menu hint in the sources is not in the test's table: \"%s\" (spoken: \"%s\")\n", h.UTF8String, MSBDAXShortcutSpoken(h).UTF8String ?: "(nil)"); }
            }
        }
        // the other keys the table knows, and edge cases
        eq(@"option-control", MSBDAXShortcutSpoken(@"⌃⌥⌘Q"), @"Control Option Command Q");
        eq(@"lower-case letter", MSBDAXShortcutSpoken(@"⌘q"), @"Command Q");
        eq(@"escape", MSBDAXShortcutSpoken(@"⎋"), @"Escape");
        eq(@"written Esc", MSBDAXShortcutSpoken(@"Esc"), @"Esc");
        eq(@"tab", MSBDAXShortcutSpoken(@"⇥"), @"Tab");
        eq(@"arrows", MSBDAXShortcutSpoken(@"⌥←"), @"Option Left Arrow");
        eq(@"return VS16", MSBDAXShortcutSpoken(@"↩️"), @"Return");
        eq(@"slash", MSBDAXShortcutSpoken(@"⌘/"), @"Command Slash");
        eq(@"equals", MSBDAXShortcutSpoken(@"⌘="), @"Command Equals");
        eq(@"minus", MSBDAXShortcutSpoken(@"⌘-"), @"Command Minus");
        eq(@"unknown symbol kept", MSBDAXShortcutSpoken(@"⌘§"), @"Command §");
        eq(@"blank", MSBDAXShortcutSpoken(@"  "), nil);
        eq(@"empty", MSBDAXShortcutSpoken(@""), nil);
        eq(@"nil", MSBDAXShortcutSpoken(nil), nil);
        eq(@"not a string", MSBDAXShortcutSpoken((NSString *)(id)@42), nil);
        eq(@"get lower", MSBDAXShortcutSpoken(@"get"), @"Get");
        eq(@"triangle submenu", MSBDAXShortcutSpoken(@"▸"), @"Submenu");
        eq(@"padded", MSBDAXShortcutSpoken(@" ⌘O "), @"Command O");
        // joins
        eq(@"join", MSBDAXJoin(@[@"a", @"", @" b ", [NSNull null], @"c"]), @"a, b, c");
        eq(@"join empty", MSBDAXJoin(@[@"", @"  "]), nil);
        eq(@"join none", MSBDAXJoin(@[]), nil);
        // Wi-Fi
        eq(@"wifi secure 2/3", MSBDAXWiFiDetails(YES, 2, 3), @"Secure network, signal strength 2 of 3 bars");
        eq(@"wifi open 3/3", MSBDAXWiFiDetails(NO, 3, 3), @"signal strength 3 of 3 bars");
        eq(@"wifi bars clamped", MSBDAXWiFiDetails(NO, 5, 3), @"signal strength 3 of 3 bars");
        eq(@"wifi no bars", MSBDAXWiFiDetails(YES, 0, 3), @"Secure network");
        eq(@"wifi nothing", MSBDAXWiFiDetails(NO, 0, 3), nil);
        // items
        eq(@"item full", MSBDAXItemValue(@"PDF document", @"2 MB", @"Today at 10:12"), @"PDF document, 2 MB, Today at 10:12");
        eq(@"item folder", MSBDAXItemValue(@"Folder", @"--", @"Yesterday"), @"Folder, Yesterday");
        eq(@"item kind only", MSBDAXItemValue(@"Folder", nil, nil), @"Folder");
        eq(@"item nothing", MSBDAXItemValue(nil, nil, nil), nil);
    }
    printf("%s: %d checks, %d failed\n", fails ? "FAIL" : "PASS", checks, fails);
    return fails ? 1 : 0;
}
