// CustomShortcutsRule.h -- Custom Shortcuts (Settings > Keyboard, 1.8.5 item 2, off unless switched on): keyboard shortcuts of your own that open an
// app, open a URL, lay out the front window or go Home. Plain C (an Objective-C part at the end), so the Mac test (tools/test-customshortcuts.c)
// runs these very rules; SpringBoard runs the shortcuts (statusbar/CustomShortcuts.h), Settings records them (macsettings/CustomShortcuts.x).
//
// Based on KeyPilot by wanghuangjie (github.com/wanghuangjie/KeyPilot, main 4b2b247, 6 Nov 2026): its rule format (key, keyCode, modifiers, action,
// enabled), the actions' spelling (app:, url:, window:, system:home), the 64-rule limit, the key names and the shortcut's display order (KPShared.m),
// and the window action names with their aliases (KPWindowActions.m) are his, ported here; its author allowed the integration (KT, 7 Nov 2026).
// Differences from KeyPilot, on purpose (plans/keypilot-integration-study.md): Globe is part of a shortcut's match (KeyPilot's mask drops it, so a
// rule on Control-Left also fired on Globe-Control-Left), Caps Lock is not (a rule must not stop working while Caps Lock is on), shortcuts that
// clash with this tweak's own keys are refused when recorded, there are no shell actions, and the keys come to SpringBoard as its own key commands
// (no key hook in every app).
//
// Portions: Copyright (c) 2026 wanghuangjie. MIT License:
//   Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the
//   "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish,
//   distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the
//   following conditions:
//   The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
//   MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
//   CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE
//   OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
// (the full text: third_party/KeyPilot/LICENSE, in the package at /usr/lib/MacStatusBarAndDock/third_party/KeyPilot/LICENSE)
#ifndef MSBD_CUSTOM_SHORTCUTS_RULE_H
#define MSBD_CUSTOM_SHORTCUTS_RULE_H
#include <stdbool.h>
#include <string.h>
#include <strings.h>
#include "../statusbar/WindowKeysRule.h"   // (the modifier flags, and Window Tiling Shortcuts' rows: a shortcut on one of them is refused)

// The preferences: their own domain, read by SpringBoard at each change (the notification) and written by Settings.
#define kMSBDCSDomain   "com.besiktasliseba.customshortcuts"
#define kMSBDCSEnabled  "enabled"        // (the switch: off unless switched on)
#define kMSBDCSRules    "rules"          // (an array of rules, each {key, keyCode, modifiers, action, enabled}, as KeyPilot's)
#define kMSBDCSChanged  "com.besiktasliseba.customshortcuts/prefsChanged"
// Darwin state while Settings records a shortcut: 1, else 0. SpringBoard runs none of the shortcuts then (a key already taken by one of them would
// run it instead of reaching Settings) and leaves them out of its key commands.
#define kMSBDCSRecordingNote "com.besiktasliseba.customshortcuts.recording"
#define kMSBDCSMaxRules 64               // (KeyPilot's KPMaximumRuleCount)

// KeyPilot (its package: com.whj.keypilot): while it is installed ours step aside (both would run each key) and its rules can be imported.
#define kMSBDCSKeyPilotDomain "com.whj.keypilot"
#define kMSBDCSKeyPilotRules  "Rules"

// The modifiers a shortcut is matched on: Shift, Control, Option, Command and Globe (kMSBDModMask, WindowKeysRule.h). Caps Lock and the keypad
// bit are left out.
static inline unsigned long long MSBDCSMods(unsigned long long flags) { return flags & kMSBDModMask; }

// Why a shortcut can't be recorded, or none.
enum {
    kMSBDCSOK = 0,
    kMSBDCSNoKey,          // (a modifier alone, or no key)
    kMSBDCSNeedsModifier,  // (no Command, Option, Control or Globe: the key would stop typing; Shift alone is typing too)
    kMSBDCSWindowTiling,   // (one of Window Tiling Shortcuts' Globe-Control keys)
    kMSBDCSMacSwitcher,    // (the Mac Switcher's Control-Left, -Right, -Up)
    kMSBDCSEscape,         // (Escape: it cancels the recording, and closes our menus and panels)
    kMSBDCSTaken,          // (another custom shortcut has it)
};
// HID usages (keyboard page 7) a shortcut reads by name.
enum { kMSBDCSHIDA = 0x04, kMSBDCSHIDZ = 0x1D, kMSBDCSHID1 = 0x1E, kMSBDCSHID0 = 0x27, kMSBDCSHIDReturn = 0x28, kMSBDCSHIDEscape = 0x29,
       kMSBDCSHIDDelete = 0x2A, kMSBDCSHIDTab = 0x2B, kMSBDCSHIDSpace = 0x2C, kMSBDCSHIDRight = 0x4F, kMSBDCSHIDLeft = 0x50, kMSBDCSHIDDown = 0x51,
       kMSBDCSHIDUp = 0x52 };
// The modifier keys themselves (Control, Shift, Option, Command, left and right; Caps Lock), and no key: usages 0 to 3 are none on the keyboard page
// (no event, roll-over, POST fail, undefined) -- the Globe key, pressed on its own, comes to an app as a press of usage 3 with the Globe flag (M1,
// 15.6.1, Magic Keyboard: it was taken as "Globe-Key 3").
static inline bool MSBDCSIsModifierKey(long usage) { return (usage >= 0xE0 && usage <= 0xE7) || usage == 0x39 || (usage >= 0x0 && usage <= 0x3); }

// A recorded key: whether it may be a shortcut. usage: the press's HID usage; chars: what the key types without modifiers (UTF-8); flags: the
// press's modifier flags.
static inline int MSBDCSCheck(long usage, const char *chars, unsigned long long flags) {
    unsigned long long m = MSBDCSMods(flags);
    if (MSBDCSIsModifierKey(usage)) return kMSBDCSNoKey;
    if (usage == kMSBDCSHIDEscape) return kMSBDCSEscape;
    if (!(m & (kMSBDModControl | kMSBDModOption | kMSBDModCommand | kMSBDModGlobe))) return kMSBDCSNeedsModifier;
    if (MSBDWinKeyRowFor(MSBDWinKeyFor(usage, chars), m) >= 0) return kMSBDCSWindowTiling;
    if (m == kMSBDModControl && (usage == kMSBDCSHIDLeft || usage == kMSBDCSHIDRight || usage == kMSBDCSHIDUp)) return kMSBDCSMacSwitcher;
    return kMSBDCSOK;
}
// Two shortcuts are the same: the same key (its usage) and the same modifiers.
static inline bool MSBDCSSame(long usageA, unsigned long long flagsA, long usageB, unsigned long long flagsB) {
    return usageA == usageB && MSBDCSMods(flagsA) == MSBDCSMods(flagsB);
}

// The actions (KeyPilot's spelling). shell: and sh: are refused (they would run commands from inside SpringBoard); a bare word (KeyPilot reads it
// as an app) is not ours either.
enum { kMSBDCSActNone = 0, kMSBDCSActApp, kMSBDCSActURL, kMSBDCSActWindow, kMSBDCSActHome, kMSBDCSActShell };
static inline bool MSBDCSHasPrefix(const char *s, const char *p) { return s && strncasecmp(s, p, strlen(p)) == 0; }
static inline const char *MSBDCSValue(const char *s, const char *p) {   // (the part after the prefix, spaces before it skipped)
    const char *v = s + strlen(p);
    while (*v == ' ' || *v == '\t') v++;
    return v;
}
// The window layouts, by KeyPilot's names and aliases (KPWindowActions.m KPWindowActionName), to the window API's (statusbar/WindowAPIRule.h:
// "left", "topleft"...). NULL: none.
static inline const char *MSBDCSLayoutName(const char *in) {
    static const char *const map[][2] = {
        { "left-half", "left" }, { "right-half", "right" }, { "top-half", "top" }, { "bottom-half", "bottom" },
        { "top-left", "topleft" }, { "top-right", "topright" }, { "bottom-left", "bottomleft" }, { "bottom-right", "bottomright" },
        { "fill", "fill" }, { "center", "center" }, { "small", "small" }, { "large", "large" },
        // KeyPilot's aliases
        { "left", "left" }, { "right", "right" }, { "top", "top" }, { "bottom", "bottom" }, { "maximize", "fill" }, { "fill-screen", "fill" },
        { "topleft", "topleft" }, { "topright", "topright" }, { "bottomleft", "bottomleft" }, { "bottomright", "bottomright" },
    };
    if (!in) return NULL;
    char n[32]; size_t j = 0;
    while (*in == ' ' || *in == '\t') in++;
    for (; *in && j < sizeof(n) - 1; in++) {   // (lower case; '_' and ' ' as '-', as KeyPilot reads them)
        char c = *in;
        if (c >= 'A' && c <= 'Z') c = (char)(c - 'A' + 'a');
        if (c == '_' || c == ' ') c = '-';
        n[j++] = c;
    }
    while (j && n[j - 1] == '-') j--;   // (trailing spaces)
    n[j] = 0;
    for (size_t i = 0; i < sizeof(map) / sizeof(map[0]); i++) if (!strcmp(n, map[i][0])) return map[i][1];
    return NULL;
}
static inline int MSBDCSActionKind(const char *action) {
    if (!action) return kMSBDCSActNone;
    while (*action == ' ' || *action == '\t') action++;
    if (!strcasecmp(action, "system:home")) return kMSBDCSActHome;
    if (MSBDCSHasPrefix(action, "window:")) return MSBDCSLayoutName(MSBDCSValue(action, "window:")) ? kMSBDCSActWindow : kMSBDCSActNone;
    if (MSBDCSHasPrefix(action, "app:")) return *MSBDCSValue(action, "app:") ? kMSBDCSActApp : kMSBDCSActNone;
    if (MSBDCSHasPrefix(action, "open:")) return *MSBDCSValue(action, "open:") ? kMSBDCSActApp : kMSBDCSActNone;   // (KeyPilot's other spelling)
    if (MSBDCSHasPrefix(action, "url:")) return strchr(MSBDCSValue(action, "url:"), ':') ? kMSBDCSActURL : kMSBDCSActNone;   // (a scheme)
    if (MSBDCSHasPrefix(action, "shell:") || MSBDCSHasPrefix(action, "sh:")) return kMSBDCSActShell;
    return kMSBDCSActNone;
}
// The value an action acts on: the app's bundle ID, the URL, the layout; NULL for Home and none.
static inline const char *MSBDCSActionValue(const char *action) {
    if (!action) return NULL;
    while (*action == ' ' || *action == '\t') action++;
    switch (MSBDCSActionKind(action)) {
        case kMSBDCSActApp: return MSBDCSHasPrefix(action, "app:") ? MSBDCSValue(action, "app:") : MSBDCSValue(action, "open:");
        case kMSBDCSActURL: return MSBDCSValue(action, "url:");
        case kMSBDCSActWindow: return MSBDCSLayoutName(MSBDCSValue(action, "window:"));
        default: return NULL;
    }
}

// The layouts offered when a shortcut is made (the Window menu's order: WindowAPIRule.h kMSBDWinAPILayouts) and their names in that menu.
#define kMSBDCSLayoutCount 12
static const char *const kMSBDCSLayouts[kMSBDCSLayoutCount] = {
    "fill", "center", "left", "right", "top", "bottom", "topleft", "topright", "bottomleft", "bottomright", "small", "large" };
static const char *const kMSBDCSLayoutTitles[kMSBDCSLayoutCount] = {
    "Fill Screen", "Center", "Left Half", "Right Half", "Top Half", "Bottom Half", "Top Left", "Top Right", "Bottom Left", "Bottom Right",
    "Small", "Large" };
static inline const char *MSBDCSLayoutTitle(const char *layout) {
    for (int i = 0; i < kMSBDCSLayoutCount; i++) if (layout && !strcmp(layout, kMSBDCSLayouts[i])) return kMSBDCSLayoutTitles[i];
    return NULL;
}

#ifdef __OBJC__
#import <Foundation/Foundation.h>
// A rule as stored: {key, keyCode, modifiers, action, enabled} (KeyPilot's keys). Valid: a key code, an action we run, enabled.
static inline BOOL MSBDCSRuleUsable(NSDictionary *r) {
    if (![r isKindOfClass:[NSDictionary class]]) return NO;
    id code = r[@"keyCode"], mods = r[@"modifiers"], act = r[@"action"], on = r[@"enabled"];
    if (![code isKindOfClass:[NSNumber class]] || [code longValue] <= 0 || ![mods isKindOfClass:[NSNumber class]] || ![act isKindOfClass:[NSString class]]) return NO;
    if (on && ![on boolValue]) return NO;
    int k = MSBDCSActionKind([act UTF8String]);
    if (!(k == kMSBDCSActApp || k == kMSBDCSActURL || k == kMSBDCSActWindow || k == kMSBDCSActHome)) return NO;
    // (the record-time rules too: a rule written some other way with no Command, Option, Control or Globe, Escape, or a Window Tiling or Mac
    //  Switcher key would take that key from typing everywhere; review 1.8.5-k L1)
    id key = r[@"key"];
    return MSBDCSCheck([code longValue], [key isKindOfClass:[NSString class]] ? [key UTF8String] : "", [mods unsignedLongLongValue]) == kMSBDCSOK;
}
// The key's name, as KeyPilot shows it (KPShared.m KPKeyName): the arrows as arrows, the named keys by name, a character in capitals.
static inline NSString *MSBDCSKeyName(long usage, NSString *key) {
    switch (usage) {
        case kMSBDCSHIDUp: return @"↑";
        case kMSBDCSHIDDown: return @"↓";
        case kMSBDCSHIDLeft: return @"←";
        case kMSBDCSHIDRight: return @"→";
        case kMSBDCSHIDReturn: return @"Return";
        case kMSBDCSHIDTab: return @"Tab";
        case kMSBDCSHIDSpace: return @"Space";
        case kMSBDCSHIDDelete: return @"Delete";
        case kMSBDCSHIDEscape: return @"Esc";
        default: break;
    }
    if (key.length) return key.uppercaseString;
    if (usage >= kMSBDCSHIDA && usage <= kMSBDCSHIDZ) return [NSString stringWithFormat:@"%c", (char)('A' + usage - kMSBDCSHIDA)];
    if (usage >= kMSBDCSHID1 && usage < kMSBDCSHID0) return [NSString stringWithFormat:@"%c", (char)('1' + usage - kMSBDCSHID1)];
    if (usage == kMSBDCSHID0) return @"0";
    return [NSString stringWithFormat:@"Key %ld", usage];
}
// The shortcut as a Mac menu shows it: Globe, Control, Option, Shift, Command, then the key (KeyPilot's order, Globe added first as on a Mac).
static inline NSString *MSBDCSShortcutText(long usage, NSString *key, unsigned long long flags) {
    NSMutableString *s = [NSMutableString string];
    if (flags & kMSBDModGlobe) [s appendString:@"\U0001F310︎"];
    if (flags & kMSBDModControl) [s appendString:@"⌃"];
    if (flags & kMSBDModOption) [s appendString:@"⌥"];
    if (flags & kMSBDModShift) [s appendString:@"⇧"];
    if (flags & kMSBDModCommand) [s appendString:@"⌘"];
    [s appendString:MSBDCSKeyName(usage, key)];
    return s;
}
// KeyPilot's rules made ours (the import): each one with an action we run and a shortcut we accept, its window layout in our spelling, at most
// kMSBDCSMaxRules with ours; the others counted. KeyPilot's modifiers have no Globe (its mask drops it), so its shortcuts are taken as they are.
static inline NSArray<NSDictionary *> *MSBDCSImport(NSArray *theirs, NSArray<NSDictionary *> *ours, NSUInteger *skippedShell, NSUInteger *skippedOther) {
    NSMutableArray *out = [NSMutableArray arrayWithArray:ours ?: @[]];
    NSUInteger shell = 0, other = 0;
    for (NSDictionary *r in [theirs isKindOfClass:[NSArray class]] ? theirs : @[]) {
        if (![r isKindOfClass:[NSDictionary class]] || ![r[@"action"] isKindOfClass:[NSString class]]) { other++; continue; }
        NSString *act = [r[@"action"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        int kind = MSBDCSActionKind(act.UTF8String);
        if (kind == kMSBDCSActShell) { shell++; continue; }
        if (kind == kMSBDCSActWindow) act = [@"window:" stringByAppendingString:@(MSBDCSActionValue(act.UTF8String))];
        else if (kind == kMSBDCSActApp) act = [@"app:" stringByAppendingString:@(MSBDCSActionValue(act.UTF8String))];
        else if (kind == kMSBDCSActHome) act = @"system:home";
        else if (kind != kMSBDCSActURL) { other++; continue; }
        long code = [r[@"keyCode"] isKindOfClass:[NSNumber class]] ? [r[@"keyCode"] longValue] : 0;
        unsigned long long mods = [r[@"modifiers"] isKindOfClass:[NSNumber class]] ? MSBDCSMods([r[@"modifiers"] unsignedLongLongValue]) : 0;
        NSString *key = [r[@"key"] isKindOfClass:[NSString class]] ? r[@"key"] : @"";
        if (MSBDCSCheck(code, key.UTF8String, mods) != kMSBDCSOK || code <= 0) { other++; continue; }
        BOOL taken = NO;
        for (NSDictionary *o in out) {   // (our stored rules: any dictionary; only numbers compared, review 1.8.5-k L2)
            if (![o[@"keyCode"] isKindOfClass:[NSNumber class]] || ![o[@"modifiers"] isKindOfClass:[NSNumber class]]) continue;
            if (MSBDCSSame([o[@"keyCode"] longValue], [o[@"modifiers"] unsignedLongLongValue], code, mods)) { taken = YES; break; }
        }
        if (taken || out.count >= kMSBDCSMaxRules) { other++; continue; }
        [out addObject:@{ @"key": key, @"keyCode": @(code), @"modifiers": @(mods), @"action": act,
                          @"enabled": @([r[@"enabled"] isKindOfClass:[NSNumber class]] ? [r[@"enabled"] boolValue] : YES) }];
    }
    if (skippedShell) *skippedShell = shell;
    if (skippedOther) *skippedOther = other;
    return out;
}
#endif
#endif
