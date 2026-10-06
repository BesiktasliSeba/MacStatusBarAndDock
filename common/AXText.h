// AXText.h -- the words VoiceOver, Switch Control, Voice Control and Full Keyboard Access get for our own UI (1.3.7, audit M-3). Plain Foundation
// (no UIKit), so the Mac test (tools/test-axtext.sh) runs the same code the parts do.
#pragma once
#import <Foundation/Foundation.h>

// The non-empty parts, joined with ", " (VoiceOver pauses at a comma): nil when nothing is left.
static inline NSString *MSBDAXJoin(NSArray *parts) {
    NSMutableArray<NSString *> *kept = [NSMutableArray array];
    for (id p in parts) {
        if (![p isKindOfClass:[NSString class]]) continue;
        NSString *t = [(NSString *)p stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (t.length) [kept addObject:t];
    }
    return kept.count ? [kept componentsJoinedByString:@", "] : nil;
}

// A shortcut as a menu shows it, like a Mac ("⇧⌘N", "⌘⌫", "⌘↑", "Space", "↩︎"), in words ("Shift Command N", "Command Delete", "Command Up
// Arrow", "Space", "Return"). The row's other right-hand marks: "›" (opens more choices) -> "Submenu", "GET" (an app to download) -> "Get".
// Characters it does not know are kept as they are (VoiceOver reads them itself); nil or blank -> nil.
static inline NSString *MSBDAXShortcutSpoken(NSString *keys) {
    if (![keys isKindOfClass:[NSString class]]) return nil;
    NSString *k = [[keys stringByReplacingOccurrencesOfString:@"︎" withString:@""] stringByReplacingOccurrencesOfString:@"️" withString:@""];
    k = [k stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!k.length) return nil;
    if ([k isEqualToString:@"›"] || [k isEqualToString:@"▸"]) return @"Submenu";
    if ([k caseInsensitiveCompare:@"GET"] == NSOrderedSame) return @"Get";
    if ([k rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]].location == NSNotFound && k.length > 1) {
        // (a written key name, "Space", "Esc", "Tab": as it is; a run of symbols and one key: word by word below)
        NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
        BOOL allLetters = YES;
        for (NSUInteger i = 0; i < k.length; i++) if (![letters characterIsMember:[k characterAtIndex:i]]) { allLetters = NO; break; }
        if (allLetters) return k;
    }
    static NSDictionary<NSString *, NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @{ @"⌃": @"Control", @"⌥": @"Option", @"⇧": @"Shift", @"⌘": @"Command", @"⇪": @"Caps Lock", @"fn": @"Function",
                   @"⌫": @"Delete", @"⌦": @"Forward Delete", @"↩": @"Return", @"⏎": @"Return", @"⌤": @"Enter", @"⎋": @"Escape", @"⇥": @"Tab",
                   @"↑": @"Up Arrow", @"↓": @"Down Arrow", @"←": @"Left Arrow", @"→": @"Right Arrow", @"⇞": @"Page Up", @"⇟": @"Page Down",
                   @"↖": @"Home", @"↘": @"End", @"[": @"Left Bracket", @"]": @"Right Bracket", @".": @"Period", @",": @"Comma",
                   @"/": @"Slash", @"\\": @"Backslash", @"=": @"Equals", @"-": @"Minus", @"+": @"Plus", @";": @"Semicolon",
                   @"'": @"Apostrophe", @"`": @"Grave Accent", @" ": @"Space" };
    });
    NSMutableArray<NSString *> *words = [NSMutableArray array];
    // (composed characters, so a symbol made of two code units stays one key)
    [k enumerateSubstringsInRange:NSMakeRange(0, k.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *ch, NSRange r, NSRange er, BOOL *stop) {
        NSString *w = names[ch];
        if (!w) w = ch.uppercaseString;
        if (w.length) [words addObject:w];
    }];
    return words.count ? [words componentsJoinedByString:@" "] : nil;
}

// A Wi-Fi network's details for its row and for the menu bar item: "Secure network, signal strength 2 of 3 bars". bars < 1: no signal part.
static inline NSString *MSBDAXWiFiDetails(BOOL secure, NSInteger bars, NSInteger maxBars) {
    NSString *signal = (bars > 0 && maxBars > 0) ? [NSString stringWithFormat:@"signal strength %ld of %ld bars", (long)MIN(bars, maxBars), (long)maxBars] : nil;
    return MSBDAXJoin(@[secure ? @"Secure network" : @"", signal ?: @""]);
}

// What a Finder or desktop item is called out as: its name, then (value) its kind, size and date where known. nil parts are left out.
static inline NSString *MSBDAXItemValue(NSString *kind, NSString *size, NSString *date) {
    return MSBDAXJoin(@[kind ?: @"", ([size isEqualToString:@"--"] ? @"" : (size ?: @"")), date ?: @""]);
}
