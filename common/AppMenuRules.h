// common/AppMenuRules.h -- the app's own menus in the menu bar (1.8.5 item 3): which menu a command of the app in front goes in, the menus' order,
// and how its shortcut reads (Mac-tested: tools/test-appmenus.m). Shared by MacAppBridge (in the app: it sorts its commands) and SpringBoard (it
// lays the titles out). Foundation only.
//
// Where a command comes from: the app's own key commands (UIKeyCommand, every responder from the one typing up to the app; the same list iPadOS's
// shortcut overlay shows while Cmd is held) and, where the app builds a main menu (UIMenuBuilder, iPadOS 15 on), that menu's commands, under the
// menu the app put them in. A command goes in:
//   1. the menu the app put it in, when that is one of Apple's standard menus (File, Edit, Format, View, Window...) -- MSBDAppMenuForMenuID;
//   2. else, for an app with a curated map (Safari), the map's menu (by the command's action or title) -- MSBDAppMenuCurated;
//   3. else the first rule of MSBDAppMenuForTitle that its title matches (File: New, Open, Close, Save, Print...; History: Back, Forward...);
//   4. else "Actions", the app's commands that fit nowhere else.
// Edit is ours (statusbar's Edit menu: Undo, Redo, Cut, Copy, Paste, Select All, Find): the app's Edit commands that ours already has are left
// out, the others are added under ours (MSBDAppMenuOursHas). Our Go and Window menus stay ours: the app's Window commands (tabs, windows) go in
// "Tabs" for a browser, else in "Window" items of View.
#pragma once
#import <Foundation/Foundation.h>

// The app menus' titles, in the bar's order (after the app's name; File before our Edit, the rest after it and before our Go and Window).
#define kMSBDAppMenuFile      @"File"
#define kMSBDAppMenuEdit      @"Edit"
#define kMSBDAppMenuFormat    @"Format"
#define kMSBDAppMenuView      @"View"
#define kMSBDAppMenuHistory   @"History"
#define kMSBDAppMenuBookmarks @"Bookmarks"
#define kMSBDAppMenuTabs      @"Tabs"
#define kMSBDAppMenuActions   @"Actions"
static inline NSArray<NSString *> *MSBDAppMenuOrder(void) {
    return @[kMSBDAppMenuFile, kMSBDAppMenuEdit, kMSBDAppMenuFormat, kMSBDAppMenuView, kMSBDAppMenuHistory, kMSBDAppMenuBookmarks, kMSBDAppMenuTabs, kMSBDAppMenuActions];
}
#define kMSBDAppMenuMaxItems 24   // (rows per menu: more is cut, the app's first ones kept)

// A row's key: FNV-1a of what its command is (title, action, key, modifiers), the same in every snapshot while the app offers that command -- a
// row shown from an older snapshot still finds its command, and one the app no longer offers finds none (review 1.8.5 H1). 0 is never a key.
static inline uint32_t MSBDAppMenuKey(NSString *what) {
    uint32_t h = 2166136261u;
    for (const char *c = what.UTF8String ?: ""; *c; c++) { h ^= (uint8_t)*c; h *= 16777619u; }
    return h ?: 1;
}
// A picked row as SpringBoard sends it (the notify state of "menuact.<hash>"): its key above, the app process's nonce below. The nonce is only in
// the app's answer, in its own container: a row from a process that has gone (the app relaunched) or from anyone but SpringBoard is refused (M1, L2).
static inline uint64_t MSBDAppMenuActState(uint32_t key, uint32_t nonce) { return ((uint64_t)key << 32) | nonce; }
static inline uint32_t MSBDAppMenuActKey(uint64_t state) { return (uint32_t)(state >> 32); }
static inline uint32_t MSBDAppMenuActNonce(uint64_t state) { return (uint32_t)(state & 0xFFFFFFFFu); }
#define kMSBDAppMenuSlots 7       // (titles of the app's own menus the bar can show: every one but Edit, which is ours and needs none -- review L7)

// 1. Apple's standard menu identifiers (UIMenuIdentifier) -> our menu. nil: not a standard one (the app's own menu: its title decides, or rules 2-4).
static inline NSString *MSBDAppMenuForMenuID(NSString *menuID) {
    if (!menuID.length) return nil;
    static NSDictionary<NSString *, NSString *> *map;
    if (!map) map = @{
        @"com.apple.menu.file": kMSBDAppMenuFile, @"com.apple.menu.new-scene": kMSBDAppMenuFile, @"com.apple.menu.close": kMSBDAppMenuFile,
        @"com.apple.menu.print": kMSBDAppMenuFile, @"com.apple.menu.document": kMSBDAppMenuFile, @"com.apple.menu.open-recent": kMSBDAppMenuFile,
        @"com.apple.menu.edit": kMSBDAppMenuEdit, @"com.apple.menu.undo-redo": kMSBDAppMenuEdit, @"com.apple.menu.standard-edit": kMSBDAppMenuEdit,
        @"com.apple.menu.find": kMSBDAppMenuEdit, @"com.apple.menu.replace": kMSBDAppMenuEdit, @"com.apple.menu.share": kMSBDAppMenuFile,
        @"com.apple.menu.text-style": kMSBDAppMenuFormat, @"com.apple.menu.spelling": kMSBDAppMenuEdit, @"com.apple.menu.spelling-panel": kMSBDAppMenuEdit,
        @"com.apple.menu.spelling-options": kMSBDAppMenuEdit, @"com.apple.menu.substitutions": kMSBDAppMenuEdit, @"com.apple.menu.substitutions-panel": kMSBDAppMenuEdit,
        @"com.apple.menu.substitution-options": kMSBDAppMenuEdit, @"com.apple.menu.transformations": kMSBDAppMenuEdit, @"com.apple.menu.speech": kMSBDAppMenuEdit,
        @"com.apple.menu.lookup": kMSBDAppMenuEdit, @"com.apple.menu.learn": kMSBDAppMenuEdit,
        @"com.apple.menu.format": kMSBDAppMenuFormat, @"com.apple.menu.font": kMSBDAppMenuFormat, @"com.apple.menu.text-size": kMSBDAppMenuFormat,
        @"com.apple.menu.text-color": kMSBDAppMenuFormat, @"com.apple.menu.text-stylepasteboard": kMSBDAppMenuFormat, @"com.apple.menu.text": kMSBDAppMenuFormat,
        @"com.apple.menu.writing-direction": kMSBDAppMenuFormat, @"com.apple.menu.alignment": kMSBDAppMenuFormat,
        @"com.apple.menu.view": kMSBDAppMenuView, @"com.apple.menu.toolbar": kMSBDAppMenuView, @"com.apple.menu.sidebar": kMSBDAppMenuView,
        @"com.apple.menu.fullscreen": kMSBDAppMenuView, @"com.apple.menu.inspector": kMSBDAppMenuView,
        @"com.apple.menu.window": kMSBDAppMenuTabs, @"com.apple.menu.minimize-and-zoom": kMSBDAppMenuTabs, @"com.apple.menu.bring-all-to-front": kMSBDAppMenuTabs,
    };
    NSString *m = map[menuID];
    if (m) return m;
    if ([menuID hasPrefix:@"com.apple.menu.application"] || [menuID hasPrefix:@"com.apple.menu.about"] || [menuID hasPrefix:@"com.apple.menu.preferences"]
        || [menuID hasPrefix:@"com.apple.menu.services"] || [menuID hasPrefix:@"com.apple.menu.hide"] || [menuID hasPrefix:@"com.apple.menu.quit"]
        || [menuID hasPrefix:@"com.apple.menu.help"] || [menuID isEqualToString:@"com.apple.menu.root"] || [menuID isEqualToString:@"com.apple.menu.main"])
        return @"";   // (the app-name and Help menus: ours has About, Settings and Force Quit; Help has nothing here -- left out)
    return nil;
}

// A title compared without case, its trailing "…" or "..." and surrounding spaces.
static inline NSString *MSBDAppMenuNorm(NSString *t) {
    NSString *s = [[t ?: @"" lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([s hasSuffix:@"…"] || [s hasSuffix:@"."]) s = [s substringToIndex:s.length - 1];
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}
static inline BOOL MSBDAMStarts(NSString *s, NSArray<NSString *> *words) {
    for (NSString *w in words) if ([s isEqualToString:w] || [s hasPrefix:[w stringByAppendingString:@" "]]) return YES;
    return NO;
}
static inline BOOL MSBDAMHas(NSString *s, NSArray<NSString *> *words) {
    for (NSString *w in words) {
        NSRange r = [s rangeOfString:w];
        if (r.location == NSNotFound) continue;
        BOOL startOK = r.location == 0 || [[NSCharacterSet letterCharacterSet] characterIsMember:[s characterAtIndex:r.location - 1]] == NO;
        NSUInteger end = NSMaxRange(r);
        BOOL endOK = end == s.length || [[NSCharacterSet letterCharacterSet] characterIsMember:[s characterAtIndex:end]] == NO;
        if (startOK && endOK) return YES;   // (whole words: "tab" in "Show All Tabs" is "tabs", matched by the list's own "tabs")
    }
    return NO;
}

// 3. By the command's title (English; an app in another language keeps its titles and they mostly land in Actions -- the menus still work).
static inline NSString *MSBDAppMenuForTitle(NSString *title) {
    NSString *s = MSBDAppMenuNorm(title);
    if (!s.length) return nil;
    // Edit first: these are what our Edit menu is for (whatever else their title says)
    // ("delete" is not one: "Delete Message" deletes what the app has open, not the selection -- never under our Find, MSBDAppMenuDestructive)
    if (MSBDAMStarts(s, @[@"undo", @"redo", @"cut", @"copy", @"paste", @"select all", @"find", @"find and replace", @"replace",
                          @"use selection for find", @"jump to selection", @"emoji & symbols", @"spelling", @"check spelling", @"start dictation", @"paste and match style",
                          @"paste and go", @"paste and search"]))
        return kMSBDAppMenuEdit;
    // History before File and Tabs: "Reopen Closed Tab", "Reopen Last Closed Window", "Show History" are history
    if (MSBDAMStarts(s, @[@"back", @"go back", @"forward", @"go forward", @"home", @"reopen", @"show history", @"history", @"clear history", @"recently closed"])
        || MSBDAMHas(s, @[@"history"]))
        return kMSBDAppMenuHistory;
    if (MSBDAMHas(s, @[@"bookmark", @"bookmarks", @"reading list", @"favorites", @"favourites"]))
        return kMSBDAppMenuBookmarks;
    if (MSBDAMStarts(s, @[@"new", @"open", @"close", @"save", @"save as", @"print", @"export", @"import", @"share", @"rename", @"move to", @"download",
                          @"downloads", @"show downloads", @"revert", @"send", @"attach", @"email", @"mail", @"duplicate"]))
        return kMSBDAppMenuFile;
    if (MSBDAMHas(s, @[@"tab", @"tabs", @"tab overview", @"tab group", @"tab groups"]) || MSBDAMStarts(s, @[@"next window", @"previous window", @"switch to"]))
        return kMSBDAppMenuTabs;
    if (MSBDAMStarts(s, @[@"bold", @"italic", @"underline", @"strikethrough", @"indent", @"outdent", @"increase indent", @"decrease indent", @"align",
                          @"heading", @"subheading", @"title", @"body", @"monostyled", @"checklist", @"bulleted list", @"dashed list", @"numbered list",
                          @"table", @"block quote", @"font", @"bigger", @"smaller", @"text size", @"style"]))
        return kMSBDAppMenuFormat;
    if (MSBDAMStarts(s, @[@"zoom in", @"zoom out", @"zoom", @"actual size", @"reload", @"reload page", @"refresh", @"stop", @"stop loading", @"show", @"hide",
                          @"toggle", @"enter full screen", @"exit full screen", @"full screen", @"reader", @"show reader", @"view", @"sort", @"sort by",
                          @"make text bigger", @"make text smaller", @"increase", @"decrease", @"scroll", @"page up", @"page down", @"go to top", @"go to bottom",
                          @"jump", @"focus", @"collapse", @"expand", @"as icons", @"as list"])
        || MSBDAMHas(s, @[@"sidebar", @"toolbar", @"reader", @"full screen", @"zoom", @"text size"]))
        return kMSBDAppMenuView;
    return nil;
}

// What our Edit menu has already (statusbar's DMOpenEditMenu): those of the app's Edit commands are not added again.
static inline BOOL MSBDAppMenuOursHas(NSString *title) {
    NSString *s = MSBDAppMenuNorm(title);
    return [@[@"undo", @"redo", @"cut", @"copy", @"paste", @"select all", @"find"] containsObject:s] || [s hasPrefix:@"undo "] || [s hasPrefix:@"redo "];
}

// ... or its shortcut is one of ours (Reynard's "Find in Page" ⌘F is our Find…): the hint as MSBDAppMenuHint writes it.
static inline BOOL MSBDAppMenuOursHasHint(NSString *hint) {
    return hint.length && [@[@"⌘Z", @"⇧⌘Z", @"⌘X", @"⌘C", @"⌘V", @"⌘A", @"⌘F"] containsObject:hint];
}

// 2. Curated maps: an app whose shortcuts are known (Safari), by its command's action (selector name) first, then its title. nil: not in the map.
static inline NSString *MSBDAppMenuCurated(NSString *bundle, NSString *action, NSString *title) {
    if (![bundle isEqualToString:@"com.apple.mobilesafari"]) return nil;
    NSString *a = [action lowercaseString] ?: @"";
    NSString *s = MSBDAppMenuNorm(title);
    // Safari's own groups, as Safari on a Mac has them (File: windows and tabs opened, closed, saved; View: reader, zoom, reload, sidebar, tab
    // overview; History; Bookmarks; Window: tab switching -- "Tabs" here, our Window menu being the windows')
    if ([s isEqualToString:@"show all tabs"] || [s isEqualToString:@"show tab overview"] || [s isEqualToString:@"tab overview"]) return kMSBDAppMenuView;
    if ([s hasPrefix:@"new"] || [s hasPrefix:@"open location"] || [s hasPrefix:@"close"] || [s hasPrefix:@"save"] || [s hasPrefix:@"print"]
        || [s hasPrefix:@"email"] || [s hasPrefix:@"share"] || [s isEqualToString:@"open search"] || [s hasPrefix:@"open link"]) return kMSBDAppMenuFile;
    if ([s hasPrefix:@"show next tab"] || [s hasPrefix:@"show previous tab"] || [s hasPrefix:@"next tab"] || [s hasPrefix:@"previous tab"]
        || [s hasPrefix:@"switch to tab"] || [s hasPrefix:@"move tab"]) return kMSBDAppMenuTabs;
    if ([s hasPrefix:@"reload"] || [s hasPrefix:@"stop"] || [s containsString:@"reader"] || [s containsString:@"zoom"] || [s isEqualToString:@"actual size"]
        || [s containsString:@"sidebar"] || [s hasPrefix:@"show downloads"] || [s hasPrefix:@"hide downloads"] || [s containsString:@"text size"]
        || [s hasPrefix:@"make text"] || [a containsString:@"zoom"] || [a containsString:@"reader"] || [a containsString:@"sidebar"]) return kMSBDAppMenuView;
    if ([s hasPrefix:@"back"] || [s hasPrefix:@"forward"] || [s hasPrefix:@"reopen"] || [s containsString:@"history"] || [a hasPrefix:@"goback"]
        || [a hasPrefix:@"goforward"]) return kMSBDAppMenuHistory;
    if ([s containsString:@"bookmark"] || [s containsString:@"reading list"] || [s containsString:@"favorites"]) return kMSBDAppMenuBookmarks;
    return nil;
}

// A destructive command by its title (review 1.8.5 M4): it starts with Delete, Clear, Erase or Remove. The app keeps such a command only as its
// own shortcut (appbridge/AppMenus.h: performed exactly as that shortcut, the app's confirmation with it), and never under our Edit menu's Find.
static inline BOOL MSBDAppMenuDestructive(NSString *title) {
    return MSBDAMStarts(MSBDAppMenuNorm(title), @[@"delete", @"clear", @"erase", @"remove"]);
}

// The menu a command goes in (rules 1-4). "" (an empty string): left out (the app-name and Help menus' commands, which have ours or nothing).
// A destructive one the app put in Edit goes in Actions: under our Find it would read as Edit > Delete, which deletes the selection on a Mac.
static inline NSString *MSBDAppMenuFor(NSString *bundle, NSString *menuID, NSString *action, NSString *title) {
    NSString *m = MSBDAppMenuForMenuID(menuID);
    if ([m isEqualToString:kMSBDAppMenuEdit] && MSBDAppMenuDestructive(title)) return kMSBDAppMenuActions;
    if (m) return m;
    m = MSBDAppMenuCurated(bundle, action, title);
    if (m) return m;
    m = MSBDAppMenuForTitle(title);
    return m ?: kMSBDAppMenuActions;
}

// The shortcut as a Mac menu shows it: ⌃⌥⇧⌘ then the key. flags: UIKeyModifierFlags' values (AlphaShift 1<<16, Shift 1<<17, Control 1<<18,
// Alternate 1<<19, Command 1<<20, NumericPad 1<<21). An empty input or one with no Mac glyph: no shortcut shown.
static inline NSString *MSBDAppMenuHint(NSString *input, long flags) {
    if (!input.length) return nil;
    static NSDictionary<NSString *, NSString *> *keys;
    if (!keys) keys = @{ @"UIKeyInputUpArrow": @"↑", @"UIKeyInputDownArrow": @"↓", @"UIKeyInputLeftArrow": @"←", @"UIKeyInputRightArrow": @"→",
                         @"UIKeyInputEscape": @"⎋", @"UIKeyInputPageUp": @"⇞", @"UIKeyInputPageDown": @"⇟", @"UIKeyInputHome": @"↖", @"UIKeyInputEnd": @"↘",
                         @"UIKeyInputDelete": @"⌦", @"\t": @"⇥", @"\r": @"↩", @"\n": @"↩", @" ": @"Space", @"\b": @"⌫", @"\x7f": @"⌫",
                         @"UIKeyInputF1": @"F1", @"UIKeyInputF2": @"F2", @"UIKeyInputF3": @"F3", @"UIKeyInputF4": @"F4", @"UIKeyInputF5": @"F5",
                         @"UIKeyInputF6": @"F6", @"UIKeyInputF7": @"F7", @"UIKeyInputF8": @"F8", @"UIKeyInputF9": @"F9", @"UIKeyInputF10": @"F10",
                         @"UIKeyInputF11": @"F11", @"UIKeyInputF12": @"F12" };
    NSString *k = keys[input];
    if (!k) {
        if (input.length != 1) return nil;   // (an input UIKit has no glyph for here)
        unichar c = [input characterAtIndex:0];
        if (c < 0x20) return nil;
        k = [input uppercaseString];
    }
    NSMutableString *h = [NSMutableString string];
    if (flags & (1L << 18)) [h appendString:@"⌃"];
    if (flags & (1L << 19)) [h appendString:@"⌥"];
    if (flags & (1L << 17)) [h appendString:@"⇧"];
    if (flags & (1L << 20)) [h appendString:@"⌘"];
    [h appendString:k];
    return h;
}
