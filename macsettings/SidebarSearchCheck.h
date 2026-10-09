// SidebarSearchCheck.h -- the check behind SidebarSearch.x: every private class, selector and type encoding the Settings sidebar's search field
// uses, compared with what this iPadOS really has. Included by macsettings/SidebarSearch.x (at load, in Settings) and by tools/test-setsearch.m
// (on the Mac, against Apple's methods of 15.6.1 19G82 and 16.7.7 20H330 read from Apple's own IPSWs). Foundation and the ObjC runtime only:
// UIKit's base classes are looked up by name, so the Mac test can stand in for them.
#pragma once
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// A type encoding reduced to its shape (as statusbar/SMEngineAPI.h): no frame offsets, qualifiers, quoted or struct names; a block ("@?") as an
// object. Apple's "v24@0:8@16" and ours built from @encode(void), @encode(id) both become "v@:@".
static NSString *MSSShape(const char *e) {
    if (!e) return nil;
    NSMutableString *o = [NSMutableString string];
    for (const char *p = e; *p; p++) {
        char ch = *p;
        if (ch >= '0' && ch <= '9') continue;
        if (ch == 'r' || ch == 'n' || ch == 'N' || ch == 'o' || ch == 'O' || ch == 'R' || ch == 'V') continue;
        if (ch == '"') { p++; while (*p && *p != '"') p++; if (!*p) break; continue; }
        if (ch == '{' || ch == '(') {
            [o appendFormat:@"%c", ch];
            const char *q = p + 1;
            while (*q && *q != '=' && *q != '}' && *q != ')' && *q != '{') q++;
            if (*q == '=') p = q;
            continue;
        }
        if (ch == '?' && o.length && [o characterAtIndex:o.length - 1] == '@') continue;
        [o appendFormat:@"%c", ch];
    }
    return o;
}
// The signature we call a method with: return type, then the arguments after self and _cmd (NULL-terminated @encode strings).
static NSString *MSSExpect(const char *ret, ...) {
    NSMutableString *s = [NSMutableString stringWithString:MSSShape(ret) ?: @""];
    [s appendString:@"@:"];
    va_list ap; va_start(ap, ret);
    for (const char *a = va_arg(ap, const char *); a; a = va_arg(ap, const char *)) [s appendString:MSSShape(a) ?: @""];
    va_end(ap);
    return s;
}
static BOOL MSSHas(Class c, const char *sel, NSString *want, NSMutableArray *why) {
    Method m = c ? class_getInstanceMethod(c, sel_registerName(sel)) : NULL;
    NSString *have = m ? MSSShape(method_getTypeEncoding(m)) : nil;
    if (have && [have isEqualToString:want]) return YES;
    [why addObject:[NSString stringWithFormat:@"-[%s %s] %@", c ? class_getName(c) : "?", sel, have ? [NSString stringWithFormat:@"is %@, called as %@", have, want] : @"missing"]];
    return NO;
}
// The class's own method, not one it inherits: the results controller's -init is Apple's own, which builds its list layout (UIKit's inherited
// -init would make a collection view without one).
static BOOL MSSHasOwn(Class c, const char *sel, NSString *want, NSMutableArray *why) {
    BOOL own = NO;
    unsigned n = 0;
    Method *ms = c ? class_copyMethodList(c, &n) : NULL;
    for (unsigned i = 0; i < n; i++) if (method_getName(ms[i]) == sel_registerName(sel)) { own = YES; break; }
    free(ms);
    if (!own) { [why addObject:[NSString stringWithFormat:@"-[%s %s] not its own", c ? class_getName(c) : "?", sel]]; return NO; }
    return MSSHas(c, sel, want, why);
}
static BOOL MSSDescendsFrom(Class c, const char *base) {   // (by name: UIKit's classes on the device, the Mac test's stand-ins there)
    for (Class k = c; k; k = class_getSuperclass(k)) if (strcmp(class_getName(k), base) == 0) return YES;
    return NO;
}
// The whole list. list = PSUIPrefsListController (PreferencesUI), apple = PSKeyboardNavigationSearchController and results =
// SUIKSearchResultsCollectionViewController (Preferences). Empty why = everything as expected.
static void MSSCheckClasses(Class list, Class apple, Class results, NSMutableArray *why) {
    if (!MSSDescendsFrom(list, "UIViewController")) [why addObject:@"PSUIPrefsListController missing"];
    if (!MSSDescendsFrom(apple, "UISearchController")) [why addObject:@"PSKeyboardNavigationSearchController missing or not a UISearchController"];
    if (!MSSDescendsFrom(results, "UICollectionViewController")) [why addObject:@"SUIKSearchResultsCollectionViewController missing or not a UICollectionViewController"];
    if (why.count) return;
    NSString *obj = MSSExpect(@encode(id), NULL), *none = MSSExpect(@encode(void), NULL), *takesObj = MSSExpect(@encode(void), @encode(id), NULL),
             *takesTwo = MSSExpect(@encode(void), @encode(id), @encode(id), NULL), *isBool = MSSExpect(@encode(BOOL), NULL),
             *takesBool = MSSExpect(@encode(void), @encode(BOOL), NULL);
    // the sidebar list: Apple's search parts it owns, and the methods SidebarSearch.x hooks
    MSSHas(list, "spotlightSearchController", obj, why);
    MSSHas(list, "searchResultsController", obj, why);
    MSSHas(list, "setSearchResultsController:", takesObj, why);
    MSSHas(list, "updateSearchResultsForSearchController:", takesObj, why);
    MSSHas(list, "searchResultsCollectionViewController:didSelectURL:", takesTwo, why);
    MSSHas(list, "continueSearchInSettingsWithTerm:", takesObj, why);
    MSSHas(list, "_tabKeyPressed", none, why);
    MSSHas(list, "_upArrowKeyPressed", none, why);
    MSSHas(list, "_downArrowKeyPressed", none, why);
    MSSHas(list, "keyCommands", obj, why);
    MSSHas(list, "viewDidLayoutSubviews", none, why);
    MSSHas(list, "table", obj, why);
    // Apple's search controller (the hidden bar the text goes into)
    MSSHas(apple, "searchBar", obj, why);
    MSSHas(apple, "searchResultsUpdater", obj, why);
    MSSHas(apple, "isActive", isBool, why);
    MSSHas(apple, "setActive:", takesBool, why);
    // Apple's results controller (the second instance shown in the sidebar)
    MSSHasOwn(results, "init", obj, why);
    MSSHas(results, "delegate", obj, why);
    MSSHas(results, "setDelegate:", takesObj, why);
    MSSHas(results, "searchQueryStarted", none, why);
    MSSHas(results, "searchQueryFoundItems:", takesObj, why);
    MSSHas(results, "selectNextSearchResult", none, why);
    MSSHas(results, "selectPreviousSearchResult", none, why);
    MSSHas(results, "showSelectedSearchResult", none, why);
    MSSHas(results, "collectionView:didSelectItemAtIndexPath:", takesTwo, why);
}
