// Mac test of common/AppMenuRules.h (the app's own menus in the menu bar, 1.8.5 item 3): which menu a command goes in, what our Edit already
// has, and how a shortcut reads. Built and run by tools/test-appmenus.sh.
#import <Foundation/Foundation.h>
#include "../common/AppMenuRules.h"

static int fails = 0, passes = 0;
static void eq(NSString *what, NSString *got, NSString *want) {
    if ((got == nil && want == nil) || [got isEqualToString:want]) { passes++; return; }
    printf("FAIL  %s: got '%s', want '%s'\n", what.UTF8String, got ? got.UTF8String : "(nil)", want ? want.UTF8String : "(nil)");
    fails++;
}
static void yes(NSString *what, BOOL v) { if (v) { passes++; return; } printf("FAIL  %s\n", what.UTF8String); fails++; }

int main(void) {
    @autoreleasepool {
        NSString *S = @"com.apple.mobilesafari", *X = @"com.example.app";
        // 1. Apple's standard menus decide first
        eq(@"File menu id", MSBDAppMenuFor(X, @"com.apple.menu.file", @"doIt:", @"Reload Everything"), kMSBDAppMenuFile);
        eq(@"View menu id", MSBDAppMenuFor(X, @"com.apple.menu.view", @"x:", @"New Thing"), kMSBDAppMenuView);
        eq(@"Window menu id -> Tabs", MSBDAppMenuFor(X, @"com.apple.menu.window", @"x:", @"Show Next Tab"), kMSBDAppMenuTabs);
        eq(@"Format menu id", MSBDAppMenuFor(X, @"com.apple.menu.format", @"x:", @"Bold"), kMSBDAppMenuFormat);
        eq(@"app-name menu left out", MSBDAppMenuFor(X, @"com.apple.menu.application", @"x:", @"About"), @"");
        eq(@"Help left out", MSBDAppMenuFor(X, @"com.apple.menu.help", @"x:", @"Search"), @"");
        eq(@"the app's own top menu: its titles decide", MSBDAppMenuFor(X, @"com.example.menu.mine", @"goBack:", @"Back"), kMSBDAppMenuHistory);
        // 2. Safari's map (macOS Safari's groups)
        eq(@"Safari New Tab", MSBDAppMenuFor(S, nil, @"newTab:", @"New Tab"), kMSBDAppMenuFile);
        eq(@"Safari Close Tab", MSBDAppMenuFor(S, nil, @"closeTab:", @"Close Tab"), kMSBDAppMenuFile);
        eq(@"Safari Open Location", MSBDAppMenuFor(S, nil, @"openLocation:", @"Open Location"), kMSBDAppMenuFile);
        eq(@"Safari Show All Tabs is View", MSBDAppMenuFor(S, nil, @"x:", @"Show All Tabs"), kMSBDAppMenuView);
        eq(@"Safari Show Next Tab", MSBDAppMenuFor(S, nil, @"x:", @"Show Next Tab"), kMSBDAppMenuTabs);
        eq(@"Safari Reload Page", MSBDAppMenuFor(S, nil, @"reload:", @"Reload Page"), kMSBDAppMenuView);
        eq(@"Safari Show Reader", MSBDAppMenuFor(S, nil, @"x:", @"Show Reader"), kMSBDAppMenuView);
        eq(@"Safari Back", MSBDAppMenuFor(S, nil, @"goBack:", @"Back"), kMSBDAppMenuHistory);
        eq(@"Safari Reopen Last Closed Tab", MSBDAppMenuFor(S, nil, @"x:", @"Reopen Last Closed Tab"), kMSBDAppMenuHistory);
        eq(@"Safari Add Bookmark", MSBDAppMenuFor(S, nil, @"x:", @"Add Bookmark"), kMSBDAppMenuBookmarks);
        eq(@"Safari Add to Reading List", MSBDAppMenuFor(S, nil, @"x:", @"Add to Reading List"), kMSBDAppMenuBookmarks);
        eq(@"Safari Find on Page falls through to the title rules: Edit", MSBDAppMenuFor(S, nil, @"find:", @"Find on Page"), kMSBDAppMenuEdit);
        // 3. by title, any app
        eq(@"New Window", MSBDAppMenuFor(X, nil, @"x:", @"New Window"), kMSBDAppMenuFile);
        eq(@"Open…", MSBDAppMenuFor(X, nil, @"x:", @"Open…"), kMSBDAppMenuFile);
        eq(@"Print", MSBDAppMenuFor(X, nil, @"x:", @"Print"), kMSBDAppMenuFile);
        eq(@"Duplicate is File", MSBDAppMenuFor(X, nil, @"x:", @"Duplicate"), kMSBDAppMenuFile);
        eq(@"Reopen Closed Tab is History, not Tabs", MSBDAppMenuFor(X, nil, @"x:", @"Reopen Closed Tab"), kMSBDAppMenuHistory);
        eq(@"Show History", MSBDAppMenuFor(X, nil, @"x:", @"Show History"), kMSBDAppMenuHistory);
        eq(@"Next Tab", MSBDAppMenuFor(X, nil, @"x:", @"Next Tab"), kMSBDAppMenuTabs);
        eq(@"Show All Tabs (not Safari) is Tabs", MSBDAppMenuFor(X, nil, @"x:", @"Show All Tabs"), kMSBDAppMenuTabs);
        eq(@"Bold", MSBDAppMenuFor(X, nil, @"x:", @"Bold"), kMSBDAppMenuFormat);
        eq(@"Zoom In", MSBDAppMenuFor(X, nil, @"x:", @"Zoom In"), kMSBDAppMenuView);
        eq(@"Toggle Sidebar", MSBDAppMenuFor(X, nil, @"x:", @"Toggle Sidebar"), kMSBDAppMenuView);
        eq(@"Find Next is Edit", MSBDAppMenuFor(X, nil, @"x:", @"Find Next"), kMSBDAppMenuEdit);
        eq(@"Copy Link is Edit", MSBDAppMenuFor(X, nil, @"x:", @"Copy Link"), kMSBDAppMenuEdit);
        eq(@"Selected (not a word start of 'select all') is no Edit", MSBDAppMenuFor(X, nil, @"x:", @"Selected Items"), kMSBDAppMenuActions);
        eq(@"tabs as a whole word only: 'Table' is Format", MSBDAppMenuFor(X, nil, @"x:", @"Table"), kMSBDAppMenuFormat);
        eq(@"'Establish' has no tab in it", MSBDAppMenuFor(X, nil, @"x:", @"Establish Link"), kMSBDAppMenuActions);
        eq(@"an unknown command: Actions", MSBDAppMenuFor(X, nil, @"x:", @"Refile Message"), kMSBDAppMenuActions);
        eq(@"case and the ellipsis don't matter", MSBDAppMenuForTitle(@"  SAVE AS...  "), kMSBDAppMenuFile);
        eq(@"an empty title: no rule", MSBDAppMenuForTitle(@""), nil);
        // destructive commands: never under our Find (review M4)
        eq(@"Delete Message is no Edit command: Actions", MSBDAppMenuFor(X, nil, @"deleteMessage:", @"Delete Message"), kMSBDAppMenuActions);
        eq(@"Delete in the app's Edit menu: Actions, not under our Find", MSBDAppMenuFor(X, @"com.apple.menu.edit", @"delete:", @"Delete"), kMSBDAppMenuActions);
        eq(@"Clear History stays History", MSBDAppMenuFor(X, nil, @"x:", @"Clear History"), kMSBDAppMenuHistory);
        eq(@"Find Next stays Edit", MSBDAppMenuFor(X, @"com.apple.menu.edit", @"findNext:", @"Find Next"), kMSBDAppMenuEdit);
        yes(@"destructive: Delete Note, Remove from Reading List, Erase, Clear…", MSBDAppMenuDestructive(@"Delete Note") && MSBDAppMenuDestructive(@"Remove from Reading List")
            && MSBDAppMenuDestructive(@"Erase") && MSBDAppMenuDestructive(@"Clear…"));
        yes(@"not destructive: Deleted Items, Clearance, Find", !MSBDAppMenuDestructive(@"Deleted Items") && !MSBDAppMenuDestructive(@"Clearance") && !MSBDAppMenuDestructive(@"Find"));
        // our Edit
        yes(@"ours has Copy", MSBDAppMenuOursHas(@"Copy"));
        yes(@"ours has Find…", MSBDAppMenuOursHas(@"Find…"));
        yes(@"ours has Undo Typing", MSBDAppMenuOursHas(@"Undo Typing"));
        yes(@"ours lacks Find Next", !MSBDAppMenuOursHas(@"Find Next"));
        yes(@"ours lacks Paste and Match Style", !MSBDAppMenuOursHas(@"Paste and Match Style"));
        yes(@"ours has ⌘F (Find in Page)", MSBDAppMenuOursHasHint(@"⌘F"));
        yes(@"ours lacks ⌘E", !MSBDAppMenuOursHasHint(@"⌘E"));
        yes(@"no hint: not ours", !MSBDAppMenuOursHasHint(nil));
        // shortcuts
        long cmd = 1L << 20, shift = 1L << 17, alt = 1L << 19, ctrl = 1L << 18;
        eq(@"⌘T", MSBDAppMenuHint(@"t", cmd), @"⌘T");
        eq(@"⇧⌘T", MSBDAppMenuHint(@"t", cmd | shift), @"⇧⌘T");
        eq(@"⌃⌥⇧⌘ order", MSBDAppMenuHint(@"k", cmd | shift | alt | ctrl), @"⌃⌥⇧⌘K");
        eq(@"arrow", MSBDAppMenuHint(@"UIKeyInputLeftArrow", cmd), @"⌘←");
        eq(@"return", MSBDAppMenuHint(@"\r", cmd), @"⌘↩");
        eq(@"tab", MSBDAppMenuHint(@"\t", ctrl), @"⌃⇥");
        eq(@"punctuation", MSBDAppMenuHint(@"]", cmd | shift), @"⇧⌘]");
        eq(@"no input", MSBDAppMenuHint(@"", cmd), nil);
        eq(@"an input with no glyph", MSBDAppMenuHint(@"UIKeyInputSomethingNew", cmd), nil);
        // a row's key and the picked row's state (review H1, M1, L2)
        NSString *k1 = @"Find Next|findNext:|g|1048576", *k2 = @"Find Previous|findPrevious:|g|1179648";
        yes(@"a row's key: the same for the same command", MSBDAppMenuKey(k1) == MSBDAppMenuKey([k1 mutableCopy]));
        yes(@"a row's key: another for another command", MSBDAppMenuKey(k1) != MSBDAppMenuKey(k2));
        yes(@"a row's key is never 0 (FNV-1a of nothing is not 0 either)", MSBDAppMenuKey(@"") != 0 && MSBDAppMenuKey(nil) != 0);
        uint64_t st = MSBDAppMenuActState(0xDEADBEEFu, 0x12345678u);
        yes(@"the picked row's state: the key and the nonce come back as they went", MSBDAppMenuActKey(st) == 0xDEADBEEFu && MSBDAppMenuActNonce(st) == 0x12345678u);
        yes(@"the picked row's state: a nonce with its top bit set doesn't touch the key", MSBDAppMenuActKey(MSBDAppMenuActState(7, 0xFFFFFFFFu)) == 7);
        // order
        NSArray *o = MSBDAppMenuOrder();
        yes(@"File first, Actions last", [o.firstObject isEqualToString:kMSBDAppMenuFile] && [o.lastObject isEqualToString:kMSBDAppMenuActions]);
        yes(@"View before History before Bookmarks before Tabs", [o indexOfObject:kMSBDAppMenuView] < [o indexOfObject:kMSBDAppMenuHistory]
            && [o indexOfObject:kMSBDAppMenuHistory] < [o indexOfObject:kMSBDAppMenuBookmarks] && [o indexOfObject:kMSBDAppMenuBookmarks] < [o indexOfObject:kMSBDAppMenuTabs]);
        yes(@"slots cover every menu but Edit (Actions too, review L7)", kMSBDAppMenuSlots >= (int)o.count - 1);
    }
    printf("test-appmenus rules: %d pass, %d fail\n", passes, fails);
    return fails ? 1 : 0;
}
