// General18Group.h -- iPadOS 18: our Settings rows in one group at the top of General.
// 18 builds Settings' root list in SwiftUI (no PSUIPrefsListController), so the Status Bar and Dock rows that 15-17 put into the main list
// (StatusBarSettingsRow.x, DockSettingsRow.x) cannot be there: PreferenceLoader lists the two pages at the end of General, among the other tweaks.
// General's page is still a PSListController on 18.5 (PSGGeneralController; the header card is its first group, PLACARD_GROUP), so our rows go
// into one group of ours right below that card, "MacStatusBar&Dock": Status Bar and Dock (the row tweaks, which load on every iPadOS version,
// "Enable Anyway" or not), then MacSettings' switches (SSH, Home Bar; Pointer / Keyboard where Apple's own pages are not as expected).
// Whoever comes first makes the group (id MAC_GENERAL18_GROUP); each puts its rows at its own place in it (after the rows listed as before it,
// else first), so the order is the same whichever comes first. The Status Bar and Dock rows take the identifiers PreferenceLoader's entries
// have (MSBD_PL_<bundle>), and those entries go while ours are there: Settings' own links (prefs:root=General&path=MSBD_PL_MacStatusBarPrefs)
// find our row then, as they found the entry before.
// Only where the SwiftUI root is in use and General's page is as expected (its class, -specifiers, its insert and remove calls, each with its
// types): otherwise nothing is done, and PreferenceLoader's entries stay where they are. 15-17: nothing here runs.
#pragma once
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define MSBD_G18_GROUP_ID @"MAC_GENERAL18_GROUP"
#define MSBD_G18_GROUP_NAME @"MacStatusBar&Dock"
#define MSBD_G18_MARK @"msbdGeneral18"   // (a property on our own rows: told apart from PreferenceLoader's entries of the same identifier)

// The SwiftUI root of iPadOS 18: Settings has no PSUIPrefsListController.
__attribute__((unused)) static BOOL MSBDG18Root(void) {
    return objc_getClass("PSUIPrefsListController") == Nil && objc_getClass("PSListController") != Nil;
}
// (a method's return and argument types, offsets aside, as expected)
__attribute__((unused)) static BOOL MSBDG18Types(Class c, SEL sel, const char *ret, NSArray<NSString *> *args) {
    Method m = c ? class_getInstanceMethod(c, sel) : NULL;
    BOOL ok = m && method_getNumberOfArguments(m) == args.count + 2;
    if (ok) { char r[16] = {0}; method_getReturnType(m, r, sizeof(r)); ok = strcmp(r, ret) == 0; }
    for (NSUInteger i = 0; ok && i < args.count; i++) { char a[16] = {0}; method_getArgumentType(m, (unsigned)(i + 2), a, sizeof(a)); ok = strcmp(a, args[i].UTF8String) == 0; }
    return ok;
}
// General's page as expected: a PSListController with -specifiers and the insert / remove calls our rows go in and PreferenceLoader's go out by.
__attribute__((unused)) static BOOL MSBDG18PageOK(Class c) {
    Class list = objc_getClass("PSListController");
    return c && list && [c isSubclassOfClass:list] && MSBDG18Types(c, @selector(specifiers), "@", @[])
        && MSBDG18Types(c, NSSelectorFromString(@"insertContiguousSpecifiers:atIndex:animated:"), "v", @[@"@", @"q", @"B"])
        && MSBDG18Types(c, NSSelectorFromString(@"removeSpecifier:animated:"), "v", @[@"@", @"B"]);
}
__attribute__((unused)) static NSString *MSBDG18Ident(id sp) {
    id i = [sp respondsToSelector:@selector(identifier)] ? ((id (*)(id, SEL))objc_msgSend)(sp, @selector(identifier)) : nil;
    return [i isKindOfClass:[NSString class]] ? i : nil;
}
__attribute__((unused)) static BOOL MSBDG18IsGroupRow(id sp) {
    SEL ct = NSSelectorFromString(@"cellType");
    return [sp respondsToSelector:ct] && ((long long (*)(id, SEL))objc_msgSend)(sp, ct) == 0;   // (0: PSGroupCell)
}
__attribute__((unused)) static BOOL MSBDG18IsOurs(id sp) {
    SEL p = @selector(propertyForKey:);
    return [sp respondsToSelector:p] && [((id (*)(id, SEL, id))objc_msgSend)(sp, p, MSBD_G18_MARK) boolValue];
}
__attribute__((unused)) static NSArray *MSBDG18Specs(id page) {
    id s = ((id (*)(id, SEL))objc_msgSend)(page, @selector(specifiers));
    return [s isKindOfClass:[NSArray class]] ? s : nil;
}
// Puts rows (of ours: each marked here) into our group, made first right below General's header card when it is not there (else at the end):
// right after the last of the group's rows whose identifier is in `after`, else first in the group. Returns NO when nothing was put in.
__attribute__((unused)) static BOOL MSBDG18Put(id page, NSArray *rows, NSArray<NSString *> *after) {
    NSArray *specs = MSBDG18Specs(page);
    if (!specs || !rows.count || !MSBDG18PageOK(object_getClass(page))) return NO;
    for (id sp in rows) if ([sp respondsToSelector:@selector(setProperty:forKey:)]) ((void (*)(id, SEL, id, id))objc_msgSend)(sp, @selector(setProperty:forKey:), @YES, MSBD_G18_MARK);
    SEL ins = NSSelectorFromString(@"insertContiguousSpecifiers:atIndex:animated:");
    NSInteger start = NSNotFound;
    for (NSUInteger i = 0; i < specs.count; i++) if ([MSBDG18Ident(specs[i]) isEqualToString:MSBD_G18_GROUP_ID]) { start = (NSInteger)i; break; }
    @try {
        if (start == NSNotFound) {
            NSUInteger groups = 0, at = specs.count;
            for (NSUInteger i = 0; i < specs.count; i++) if (MSBDG18IsGroupRow(specs[i]) && ++groups == 2) { at = i; break; }
            id g = ((id (*)(id, SEL, id))objc_msgSend)((id)objc_getClass("PSSpecifier"), @selector(groupSpecifierWithName:), MSBD_G18_GROUP_NAME);
            if (!g) return NO;
            ((void (*)(id, SEL, id))objc_msgSend)(g, @selector(setIdentifier:), MSBD_G18_GROUP_ID);
            NSMutableArray *all = [NSMutableArray arrayWithObject:g];
            [all addObjectsFromArray:rows];
            ((void (*)(id, SEL, id, long long, BOOL))objc_msgSend)(page, ins, all, (long long)at, NO);
            return YES;
        }
        NSUInteger at = (NSUInteger)start + 1;
        for (NSUInteger i = (NSUInteger)start + 1; i < specs.count && !MSBDG18IsGroupRow(specs[i]); i++)
            if ([after containsObject:MSBDG18Ident(specs[i]) ?: @""]) at = i + 1;
        ((void (*)(id, SEL, id, long long, BOOL))objc_msgSend)(page, ins, rows, (long long)at, NO);
        return YES;
    } @catch (NSException *e) { return NO; }
}
// Takes out the entries of a page of ours that are not our own rows: PreferenceLoader's (by its identifier, or as it was listed before it had one:
// its bundle's name), never another tweak's entry. Returns how many went.
__attribute__((unused)) static NSUInteger MSBDG18RemoveListed(id page, NSString *plID, NSString *bundleName) {
    NSArray *specs = [MSBDG18Specs(page) copy];
    SEL rem = NSSelectorFromString(@"removeSpecifier:animated:"), p = @selector(propertyForKey:);
    NSUInteger n = 0;
    for (id sp in specs) {
        if (MSBDG18IsOurs(sp)) continue;
        BOOL listed = [MSBDG18Ident(sp) isEqualToString:plID];
        if (!listed && [sp respondsToSelector:p]) {
            id b = ((id (*)(id, SEL, id))objc_msgSend)(sp, p, @"bundle") ?: ((id (*)(id, SEL, id))objc_msgSend)(sp, p, @"lazy-bundle");
            listed = [b isKindOfClass:[NSString class]] && ([(NSString *)b isEqualToString:bundleName] || [[(NSString *)b lastPathComponent] isEqualToString:[bundleName stringByAppendingString:@".bundle"]]);
        }
        if (!listed) continue;
        @try { ((void (*)(id, SEL, id, BOOL))objc_msgSend)(page, rem, sp, NO); n++; } @catch (NSException *e) {}
    }
    return n;
}
// Our row in place of PreferenceLoader's entry of the same page: the entry goes out first (with both in the list, the list renamed ours "<id>.0"
// and Settings' links would not find it), then ours goes into the group with the entry's identifier; when ours could not go in, the entry is put
// back where it was. NO: ours is not in.
__attribute__((unused)) static BOOL MSBDG18PutInPlaceOf(id page, id row, NSArray<NSString *> *after, NSString *plID, NSString *bundleName) {
    NSArray *specs = [MSBDG18Specs(page) copy];
    if (!specs || !row || !MSBDG18PageOK(object_getClass(page))) return NO;
    SEL rem = NSSelectorFromString(@"removeSpecifier:animated:"), ins = NSSelectorFromString(@"insertContiguousSpecifiers:atIndex:animated:"), p = @selector(propertyForKey:);
    NSMutableArray *gone = [NSMutableArray array]; NSMutableArray<NSNumber *> *at = [NSMutableArray array];
    for (NSUInteger i = 0; i < specs.count; i++) {
        id sp = specs[i];
        if (MSBDG18IsOurs(sp)) continue;
        BOOL listed = [MSBDG18Ident(sp) isEqualToString:plID];
        if (!listed && [sp respondsToSelector:p]) {
            id b = ((id (*)(id, SEL, id))objc_msgSend)(sp, p, @"bundle") ?: ((id (*)(id, SEL, id))objc_msgSend)(sp, p, @"lazy-bundle");
            listed = [b isKindOfClass:[NSString class]] && ([(NSString *)b isEqualToString:bundleName] || [[(NSString *)b lastPathComponent] isEqualToString:[bundleName stringByAppendingString:@".bundle"]]);
        }
        if (listed) { [gone addObject:sp]; [at addObject:@(i)]; }
    }
    @try { for (id sp in gone) ((void (*)(id, SEL, id, BOOL))objc_msgSend)(page, rem, sp, NO); } @catch (NSException *e) {}
    if (MSBDG18Put(page, @[row], after)) return YES;
    @try {   // (back where they were, first one first)
        for (NSUInteger i = 0; i < gone.count; i++) {
            NSUInteger n = MIN((NSUInteger)at[i].unsignedIntegerValue, MSBDG18Specs(page).count);
            ((void (*)(id, SEL, id, long long, BOOL))objc_msgSend)(page, ins, @[gone[i]], (long long)n, NO);
        }
    } @catch (NSException *e) {}
    return NO;
}
// Is a row of ours with this identifier in the page's list?
__attribute__((unused)) static BOOL MSBDG18Has(id page, NSString *ident) {
    for (id sp in MSBDG18Specs(page)) if (MSBDG18IsOurs(sp) && [MSBDG18Ident(sp) isEqualToString:ident]) return YES;
    return NO;
}
