// NativeEmbed.h -- showing Apple's own Settings rows on our pages, and hiding them on Apple's pages (MacStatusBar&Dock, 2026-09-25).
//
// Our Pointer, Keyboard and Dock pages show some of Apple's own settings (Pointer Control, Trackpad & Mouse, Hardware Keyboard, the two Dock
// switches of Home Screen & Dock). They are not copies: Apple's own page controller is made (never shown) and its own rows (specifiers) are put on
// our page, still pointing at that controller -- so each row reads and writes exactly as on Apple's page, with Apple's cells, sliders and sub-pages,
// live. The rows found on the device (same identifiers on iPadOS 15 and 16):
//   Accessibility > Pointer Control      AXPointerControlController (AccessibilitySettings.bundle)   row POINTER_CONTROL in AccessibilitySettingsController
//   General > Trackpad (& Mouse)         PSGMousePointerViewController (PreferencesUI)                row POINTERS in PSGGeneralController
//   General > Keyboard > Hardware Keyb.  TIHardwareKeyboardController (KeyboardSettings.bundle)       row "Hardware Keyboard" in KeyboardController
//   Home Screen & Dock                   DBSHomeScreenPadListController                               rows MULTITASKING_DOCK, SHOW_APP_LIBRARY, ALLOW_RECENTS
// While our page is the place for them, the row on Apple's page is taken out (MSNEHideRows), right after Apple's page has built or rebuilt its list,
// through the list's own remove call (so its table stays in step).
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static inline Class MSNEClass(NSString *name, NSArray<NSString *> *bundles) {
    Class c = NSClassFromString(name);
    for (NSString *b in bundles) { if (c) break; [[NSBundle bundleWithPath:b] load]; c = NSClassFromString(name); }
    return c;
}
static inline id MSNECall(id o, NSString *sel) {
    SEL s = NSSelectorFromString(sel);
    return [o respondsToSelector:s] ? ((id (*)(id, SEL))objc_msgSend)(o, s) : nil;
}
static inline void MSNECall1(id o, NSString *sel, id arg) {
    SEL s = NSSelectorFromString(sel);
    if ([o respondsToSelector:s]) ((void (*)(id, SEL, id))objc_msgSend)(o, s, arg);
}
// Apple's page `className` made for `host` (not shown) and its rows; `only` keeps just those row identifiers (with nil, every row). The controller is
// kept alive in `keep` (the rows' target is not retained by the rows). Returns nil if the page is not there on this iOS.
static inline NSArray *MSNESpecifiers(UIViewController *host, NSString *className, NSArray<NSString *> *bundles, NSString *title, NSMutableArray *keep, NSArray<NSString *> *only) {
    Class c = MSNEClass(className, bundles), list = NSClassFromString(@"PSListController"), specClass = NSClassFromString(@"PSSpecifier");
    if (!c || !list || ![c isSubclassOfClass:list] || !specClass) return nil;
    NSArray *specs = nil;
    @try {
        UIViewController *page = [[c alloc] init];
        if (!page) return nil;
        MSNECall1(page, @"setRootController:", MSNECall(host, @"rootController"));
        MSNECall1(page, @"setParentController:", host);
        SEL make = NSSelectorFromString(@"preferenceSpecifierNamed:target:set:get:detail:cell:edit:");
        id spec = ((id (*)(id, SEL, id, id, SEL, SEL, Class, long long, Class))objc_msgSend)(specClass, make, title, nil, NULL, NULL, c, 2, Nil);
        MSNECall1(page, @"setSpecifier:", spec);
        specs = MSNECall(page, @"specifiers");
        if (specs.count) [keep addObject:page];
    } @catch (NSException *e) { return nil; }
    if (![specs isKindOfClass:[NSArray class]] || !specs.count) return nil;
    if (!only) {   // (Apple's page may start without a group of its own -- the Hardware Keyboard page adds its first one late: one is put in front)
        NSMutableArray *all = [specs mutableCopy];
        SEL cellType = NSSelectorFromString(@"cellType");
        id first = all.firstObject;
        if ([first respondsToSelector:cellType] && ((long long (*)(id, SEL))objc_msgSend)(first, cellType) != 0) {
            id g = ((id (*)(id, SEL, id))objc_msgSend)(specClass, NSSelectorFromString(@"groupSpecifierWithName:"), nil);
            if (g) [all insertObject:g atIndex:0];
        }
        return all;
    }
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *want in only) for (id s in specs) if ([[s identifier] isEqual:want]) { [out addObject:s]; break; }
    return out;
}
// Apple's page `list`: its rows `ids` taken out (the list's own remove call, so its table stays in step). Groups last.
static inline void MSNEHideRows(UIViewController *list, NSArray<NSString *> *ids) {
    SEL find = NSSelectorFromString(@"specifierForID:"), rem = NSSelectorFromString(@"removeSpecifier:animated:");
    if (![list respondsToSelector:find] || ![list respondsToSelector:rem]) return;
    for (NSString *i in ids) {
        @try {
            id s = ((id (*)(id, SEL, id))objc_msgSend)(list, find, i);
            if (s) ((void (*)(id, SEL, id, BOOL))objc_msgSend)(list, rem, s, NO);
        } @catch (NSException *e) {}
    }
}
