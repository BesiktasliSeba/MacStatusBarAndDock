// NativeRows.x -- while our Pointer and Keyboard rows are in the Settings sidebar, Apple's own entries for the same settings are taken out of their
// pages, so each setting has one place (MacStatusBar&Dock, 2026-09-25): Accessibility > Pointer Control and General > Trackpad & Mouse (our Pointer
// page shows them, live) while a trackpad or mouse is attached; General > Keyboard > Hardware Keyboard (our Keyboard page shows it) while a hardware
// keyboard is attached. Without the device our row is not there, and Apple's pages are left exactly as they are.
// Done right after Apple's page has built (or rebuilt) its list, through the list's own remove call (see common/NativeEmbed.h).
#import <UIKit/UIKit.h>
#import <unistd.h>
#import <objc/runtime.h>
#import "../common/NativeEmbed.h"

BOOL MSPointerDeviceAttached(void);
BOOL MSKeyboardAttached(void);

@interface PSListController : UIViewController
@end


static void NRLog(UIViewController *list, NSString *what, NSArray *specs) {   // (debug builds: which call brought Apple's row in)
#if DEBUG
    if (access("/tmp/macsettings-debug", F_OK) != 0) return;
    NSMutableString *ids = [NSMutableString string];
    for (id sp in specs) [ids appendFormat:@" %@", [sp identifier]];
    FILE *f = fopen("/tmp/macsettings.log", "a");
    if (f) { fprintf(f, "[nativerows] %s %s:%s\n", NSStringFromClass([list class]).UTF8String, what.UTF8String, ids.UTF8String); fclose(f); }
#endif
}

// Apple's pages also add these rows later, once they learn a device is attached (General adds Trackpad & Mouse a moment after it appears): such an
// insert is simply left out (nothing reaches the table, so it stays in step).
// Only where our rows can be in the sidebar at all: they are added by MacSettings.x's hook of the UIKit root list (PSUIPrefsListController). iPadOS 18
// builds that root in SwiftUI and has no such class -- our Pointer and Keyboard rows never appear there, and taking Apple's out left no way to the
// trackpad, Pointer Control or Hardware Keyboard settings at all (A12Z 18.5 with a Magic Keyboard: General without Trackpad & Mouse, 24 Oct).
static BOOL MSOurSidebarRowsPossible(void) {
    static int possible = -1;
    if (possible < 0) possible = objc_getClass("PSUIPrefsListController") != Nil;
    return possible == 1;
}
static NSArray *MSNativeRowsHidden(UIViewController *list) {
    if (!MSOurSidebarRowsPossible()) return nil;
    NSString *c = NSStringFromClass([list class]);
    if ([c isEqualToString:@"AccessibilitySettingsController"]) return MSPointerDeviceAttached() ? @[@"POINTER_CONTROL"] : nil;
    if ([c isEqualToString:@"PSGGeneralController"]) return MSPointerDeviceAttached() ? @[@"POINTERS"] : nil;
    if ([c isEqualToString:@"KeyboardController"]) return MSKeyboardAttached() ? @[@"Hardware Keyboard"] : nil;
    return nil;
}
static NSArray *MSNativeRowsKept(UIViewController *list, NSArray *specs, NSString *what) {
    NSArray *hidden = MSNativeRowsHidden(list);
    if (!hidden.count) return specs;
    NSMutableArray *kept = [NSMutableArray array];
    for (id sp in specs) if (![hidden containsObject:[sp identifier] ?: @""]) [kept addObject:sp];
    if (kept.count != specs.count) NRLog(list, [what stringByAppendingString:@" (left out)"], specs);
    return kept;
}
%hook PSListController
- (void)insertSpecifier:(id)spec atIndex:(long long)index animated:(BOOL)animated {
    if (spec && !MSNativeRowsKept((UIViewController *)self, @[spec], @"insert at index").count) return;
    %orig;
}
- (void)insertSpecifier:(id)spec afterSpecifierID:(id)ident animated:(BOOL)animated {
    if (spec && !MSNativeRowsKept((UIViewController *)self, @[spec], @"insert after id").count) return;
    %orig;
}
- (void)insertSpecifier:(id)spec afterSpecifier:(id)other animated:(BOOL)animated {
    if (spec && !MSNativeRowsKept((UIViewController *)self, @[spec], @"insert after").count) return;
    %orig;
}
- (void)insertContiguousSpecifiers:(NSArray *)specs atIndex:(long long)index animated:(BOOL)animated {
    NSArray *kept = MSNativeRowsKept((UIViewController *)self, specs, @"insert contiguous");
    if (specs.count && !kept.count) return;
    %orig(kept, index, animated);
}
- (void)insertContiguousSpecifiers:(NSArray *)specs afterSpecifierID:(id)ident animated:(BOOL)animated {
    NSArray *kept = MSNativeRowsKept((UIViewController *)self, specs, @"insert contiguous after id");
    if (specs.count && !kept.count) return;
    %orig(kept, ident, animated);
}
- (void)addSpecifier:(id)spec animated:(BOOL)animated {
    if (spec && !MSNativeRowsKept((UIViewController *)self, @[spec], @"add").count) return;
    %orig;
}
- (void)addSpecifiersFromArray:(NSArray *)specs animated:(BOOL)animated {
    NSArray *kept = MSNativeRowsKept((UIViewController *)self, specs, @"add array");
    if (specs.count && !kept.count) return;
    %orig(kept, animated);
}
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    NSArray *h = MSNativeRowsHidden((UIViewController *)self);
    if (h.count) MSNEHideRows((UIViewController *)self, h);
}
- (void)reloadSpecifiers {
    %orig;
    NSArray *h = MSNativeRowsHidden((UIViewController *)self);
    if (h.count) MSNEHideRows((UIViewController *)self, h);
}
%end
