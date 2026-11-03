// MainListRows.h -- where our rows go in Settings' main list (15-17: PSUIPrefsListController): the Status Bar, Desktop, Windows & Multitasking
// and Dock rows (statusbar/macstatusbarsettings/StatusBarSettingsRow.x, dock/dockmagnificationsettings/DockSettingsRow.x) and MacSettings'
// sidebar rows (macsettings/MacSettings.x, SidebarGroups.x), found by the rows' identifiers, never by a fixed index (Shuffle and PreferenceLoader
// change the list). Every place is worked out from one list of the rows' identifiers (NSString, or NSNull for a row whose identifier is not
// read), so the rules are pure (tools/test-mainlistrows.sh runs them on the Mac).
// 1.7.9 (Settings crash, 17.5.1, 2 Nov: Preferences-2026-11-02-153127.ips): Settings fills its Apple Account row in on a queue of its own while
// the row is already in the list -- -[PSUIPrefsListController updateSpyglassWithCompletion:], called on the main thread as the list is built
// or reloaded (willBecomeActive's reload too), hands -_appleAccountSpecifier to -_setupAppleAccountSpecifier:completion: on
// com.apple.PreferencesUI.PSUIPrefsListController.Loading, which sets about a dozen of its properties over 50-130 ms. Our rows go in at that
// same moment, and reading every row's identifier then read that row's property dictionary while the queue was growing it: -[PSSpecifier
// identifier] -> -[__NSDictionaryM objectForKey:] on storage just freed. So the identifiers are read once per change, on the main thread, from
// the list as it is now (never a copy kept from an earlier hand-out: with Shuffle that was another array, its indexes another list's), and the
// row Settings fills in is never read at all -- told apart by Apple's own pointer to it, which only the main thread sets. No other row of the
// main list is written off the main thread (17.5.1: Settings' search index, Shuffle and the third-party app rows build new rows of their own
// before handing them over). Foundation and the ObjC runtime only.
#pragma once
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ---- the places, from the rows' identifiers (pure) ----
// The first row of that identifier (any case when asked), else NSNotFound.
static inline NSInteger MSBDMLIndexOf(NSArray *ids, NSString *ident, BOOL anyCase) {
    if (![ident isKindOfClass:[NSString class]]) return NSNotFound;
    for (NSUInteger i = 0; i < ids.count; i++) {
        id s = ids[i];
        if ([s isKindOfClass:[NSString class]] && (anyCase ? [s caseInsensitiveCompare:ident] == NSOrderedSame : [s isEqualToString:ident])) return (NSInteger)i;
    }
    return NSNotFound;
}
// The last row of that identifier (exact), else NSNotFound.
static inline NSInteger MSBDMLLastIndexOf(NSArray *ids, NSString *ident) {
    NSInteger found = NSNotFound;
    for (NSUInteger i = 0; i < ids.count; i++) if ([ids[i] isKindOfClass:[NSString class]] && [ids[i] isEqualToString:ident]) found = (NSInteger)i;
    return found;
}
// Where a row of ours goes: right below General, in General's own block -- General, Status Bar, Desktop, Windows & Multitasking, Dock, Control
// Center. `before` / `after`: one of our rows it goes in front of / right after when that is there (both rows insert themselves, in whichever
// order); else in front of Control Center, else right after General, else in front of Accessibility; NSNotFound when none of these is there.
static inline NSInteger MSBDMLAnchor(NSArray *ids, NSString *before, NSString *after) {
    NSInteger cc = NSNotFound, general = NSNotFound, accessibility = NSNotFound, own = NSNotFound;
    for (NSUInteger i = 0; i < ids.count; i++) {
        id ident = ids[i];
        if (![ident isKindOfClass:[NSString class]]) continue;
        if (before && [ident isEqualToString:before]) own = (NSInteger)i;
        if (after && [ident isEqualToString:after]) own = (NSInteger)i + 1;
        if (cc == NSNotFound && [ident caseInsensitiveCompare:@"ControlCenter"] == NSOrderedSame) cc = (NSInteger)i;
        if (general == NSNotFound && [ident caseInsensitiveCompare:@"General"] == NSOrderedSame) general = (NSInteger)i + 1;
        if (accessibility == NSNotFound && [ident caseInsensitiveCompare:@"ACCESSIBILITY"] == NSOrderedSame) accessibility = (NSInteger)i;
    }
    if (own != NSNotFound) return own;
    if (cc != NSNotFound) return cc;
    if (general != NSNotFound) return general;
    return accessibility;
}
// No known row found (an iPadOS whose main list we have not seen: iPadOS 17 tester, 2026-09-26, got no rows at all): near the top instead -- the
// start of the list's second block, below the Apple account -- so the rows always show. `cellTypes`: each row's cell type (0: PSGroupCell).
static inline NSInteger MSBDMLTop(NSArray<NSNumber *> *cellTypes) {
    for (NSUInteger i = 1; i < cellTypes.count; i++) if ([cellTypes[i] longLongValue] == 0) return (NSInteger)i + 1;
    return cellTypes.count ? 1 : 0;
}
// MacSettings puts Accessibility and everything below it in a section of its own (its group row, `groupID`, right before Accessibility). The
// Status Bar and Dock rows add themselves "just before Accessibility", after that group row, which would pull them into the new section: only
// those two rows (`inserted`: the identifiers of the rows being put in) go in front of the group row instead.
static inline BOOL MSBDMLGoesBeforeAccessibilityGroup(NSArray *inserted) {
    if (!inserted.count) return NO;
    for (id i in inserted) if (![i isKindOfClass:[NSString class]] || (![i isEqualToString:@"MAC_STATUS_BAR"] && ![i isEqualToString:@"DOCK_MAGNIFICATION"])) return NO;
    return YES;
}
// ... in front of the group row when `index` is after it and not after Accessibility; else `index` as it is.
static inline NSInteger MSBDMLAccessibilityGroupIndex(NSArray *ids, NSInteger index, NSString *groupID) {
    NSInteger group = NSNotFound, accessibility = NSNotFound;
    for (NSUInteger i = 0; i < ids.count; i++) {
        id ident = ids[i];
        if (![ident isKindOfClass:[NSString class]]) continue;
        if ([ident isEqualToString:groupID]) group = (NSInteger)i;
        else if (group != NSNotFound && accessibility == NSNotFound && [ident caseInsensitiveCompare:@"ACCESSIBILITY"] == NSOrderedSame) accessibility = (NSInteger)i;
    }
    if (group != NSNotFound && accessibility != NSNotFound && index > group && index <= accessibility) return group;
    return index;
}

// ---- the identifiers, read from the list on the iPad ----
// The row Settings is filling in (or may fill in) on its own queue: the list's -_appleAccountSpecifier (a plain getter of its ivar), when the
// list has that call with its type; else nil (nothing to leave out). Main thread.
static inline id MSBDMLFilledRow(id list) {
    SEL s = NSSelectorFromString(@"_appleAccountSpecifier");
    Method m = list ? class_getInstanceMethod(object_getClass(list), s) : NULL;
    const char *t = m ? method_getTypeEncoding(m) : NULL;
    if (!t || t[0] != '@' || method_getNumberOfArguments(m) != 2) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(list, s);
}
// The list as it is now, without asking for it (asking -specifiers in the middle of one of the list's own changes can build it again): the
// controller's own _specifiers; nil when it has none.
static inline NSArray *MSBDMLLive(id list) {
    Ivar iv = list ? class_getInstanceVariable(object_getClass(list), "_specifiers") : NULL;
    id s = iv ? object_getIvar(list, iv) : nil;
    return [s isKindOfClass:[NSArray class]] ? s : nil;
}
// Each row's identifier (NSString), or NSNull: the row Settings is filling in (never touched), or a row without one. Main thread.
static inline NSArray *MSBDMLIdentifiers(id list, NSArray *specs) {
    id filled = MSBDMLFilledRow(list);
    SEL identSel = NSSelectorFromString(@"identifier");
    NSMutableArray *ids = [NSMutableArray arrayWithCapacity:specs.count];
    for (id sp in specs) {
        id i = sp != filled && [sp respondsToSelector:identSel] ? ((id (*)(id, SEL))objc_msgSend)(sp, identSel) : nil;
        [ids addObject:[i isKindOfClass:[NSString class]] ? i : [NSNull null]];
    }
    return ids;
}
// Whether a row may be read (not the row Settings is filling in). Main thread.
static inline BOOL MSBDMLReadable(id list, id sp) { return sp && sp != MSBDMLFilledRow(list); }
// Each row's cell type (an instance variable of the row, never its properties): -1 for the row Settings is filling in. Main thread.
static inline NSArray<NSNumber *> *MSBDMLCellTypes(id list, NSArray *specs) {
    id filled = MSBDMLFilledRow(list);
    SEL ct = NSSelectorFromString(@"cellType");
    NSMutableArray *o = [NSMutableArray arrayWithCapacity:specs.count];
    for (id sp in specs) [o addObject:@(sp != filled && [sp respondsToSelector:ct] ? ((long long (*)(id, SEL))objc_msgSend)(sp, ct) : -1)];
    return o;
}
// The first row of that identifier (any case when asked), else nil -- never the row Settings is filling in. Main thread.
static inline id MSBDMLRowFor(id list, NSArray *specs, NSString *ident, BOOL anyCase) {
    NSInteger i = MSBDMLIndexOf(MSBDMLIdentifiers(list, specs), ident, anyCase);
    return i == NSNotFound ? nil : specs[(NSUInteger)i];
}
