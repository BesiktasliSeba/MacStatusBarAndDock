// MacSpotlightCheck.h -- the check behind MacSpotlight.x: every private class, selector and type encoding our Spotlight sections use, compared
// with what this iPadOS really has. Included by spotlight/MacSpotlight.x (in Spotlight, before anything is hooked) and by tools/test-spotcheck.m
// (on the Mac, against Apple's methods of 15.6.1 19G82 and 16.7.7 20H330 read from Apple's own IPSWs: tools/spotcheck-fixtures). Foundation and
// the ObjC runtime only: UIKit's base class is looked up by name, so the Mac test can stand in for it.
//
// What is used (read in Apple's binaries of both builds):
//  - SPUIResultsViewController (SpotlightUIInternal, the results list in the Spotlight app) inherits SearchUI's -updateWithResultSections:
//    resetScrollPoint:, the one call through which every list of sections reaches the screen (from -_pushSectionsUpdate, after each answer of
//    the search, and when the text is cleared); -queryString is set from the typed text first thing in -searchUpdatedWithString:...
//  - a section is an SFResultSection, a row an SFSearchResult (SearchFoundation); a result without an inline card becomes SearchUI's detailed row
//    (+[SearchUITableModel rowModelsForResult:]) from its title, descriptions and thumbnail, and is always tappable (-isTappable with no card section);
//  - a tap: 16 asks +[SearchUICommandHandler handlerForRowModel:environment:] and runs -executeWithTriggerEvent: (also its copy and drag paths
//    ask that factory), and lets a row be highlighted -- touched, tapped, reached with the arrow keys -- only when
//    -[SearchUICollectionViewController canHighlightRowAtIndexPath:] says so: Apple's answer is +hasValidHandlerForRowModel:environment: for the
//    row at that place (-collectionModel, -rowModelForIndexPath:), and that factory question is also the long press's: a row it approves gets a
//    preview menu (-[SearchUICollectionPeekDelegate contextMenuInteraction:configurationForMenuAtLocation:]). So our rows are approved where the
//    highlight is asked, and nowhere else: they have no preview and no menu, and a long press on one does nothing (as on 15). 15 asks
//    +[SearchUICommand tapCommandForRowModel:environment:] and runs -performCommandWithCompletion: after asking -presentsViewController. Our rows
//    get our own handler / command (a subclass of Apple's); every other row is Apple's.
#pragma once
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// A type encoding reduced to its shape (as macsettings/SidebarSearchCheck.h): no frame offsets, qualifiers, quoted or struct names; a block ("@?")
// as an object. Apple's "v28@0:8@16B24" and ours from @encode(void), @encode(id), @encode(BOOL) both become "v@:@B".
static NSString *MSPShape(const char *e) {
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
static NSString *MSPExpect(const char *ret, ...) {
    NSMutableString *s = [NSMutableString stringWithString:MSPShape(ret) ?: @""];
    [s appendString:@"@:"];
    va_list ap; va_start(ap, ret);
    for (const char *a = va_arg(ap, const char *); a; a = va_arg(ap, const char *)) [s appendString:MSPShape(a) ?: @""];
    va_end(ap);
    return s;
}
static BOOL MSPHasMethod(Class c, BOOL classMethod, const char *sel, NSString *want, NSMutableArray *why) {
    Method m = !c ? NULL : classMethod ? class_getClassMethod(c, sel_registerName(sel)) : class_getInstanceMethod(c, sel_registerName(sel));
    NSString *have = m ? MSPShape(method_getTypeEncoding(m)) : nil;
    if (have && [have isEqualToString:want]) return YES;
    [why addObject:[NSString stringWithFormat:@"%c[%s %s] %@", classMethod ? '+' : '-', c ? class_getName(c) : "?", sel,
                    have ? [NSString stringWithFormat:@"is %@, called as %@", have, want] : @"missing"]];
    return NO;
}
static BOOL MSPHas(Class c, const char *sel, NSString *want, NSMutableArray *why) { return MSPHasMethod(c, NO, sel, want, why); }
static BOOL MSPHasClassMethod(Class c, const char *sel, NSString *want, NSMutableArray *why) { return MSPHasMethod(c, YES, sel, want, why); }
static BOOL MSPDescendsFrom(Class c, const char *base) {   // (by name: UIKit's classes on the device, the Mac test's stand-ins there)
    for (Class k = c; k; k = class_getSuperclass(k)) if (strcmp(class_getName(k), base) == 0) return YES;
    return NO;
}

// Which tap path this iPadOS has: 16's handler factory, 15's command factory, or none (then nothing is offered).
typedef NS_ENUM(NSInteger, MSPTapKind) { MSPTapNone = 0, MSPTapCommand15 = 15, MSPTapHandler16 = 16 };
static MSPTapKind MSPTapKindFor(Class handler16, Class command15, Class tapCommand15) {
    if (handler16 && class_getClassMethod(handler16, sel_registerName("handlerForRowModel:environment:"))) return MSPTapHandler16;
    if (command15 && tapCommand15 && class_getClassMethod(command15, sel_registerName("tapCommandForRowModel:environment:"))) return MSPTapCommand15;
    return MSPTapNone;
}

// The whole list, for the classes as found by name in this process (nil when missing). Empty why = everything as expected.
//   results = SPUIResultsViewController, rowModel = SearchUIRowModel, result = SFSearchResult, section = SFResultSection, text = SFText,
//   rich = SFRichText, symbol = SFSymbolImage, appIcon = SFAppIconImage, handler16 = SearchUICommandHandler, collection16 =
//   SearchUICollectionViewController, collectionModel16 = SearchUICollectionModel, command15 = SearchUICommand, tapCommand15 = SearchUITapCommand.
static MSPTapKind MSPCheckClasses(Class results, Class rowModel, Class result, Class section, Class text, Class rich, Class symbol, Class appIcon,
                                  Class handler16, Class collection16, Class collectionModel16, Class command15, Class tapCommand15, NSMutableArray *why) {
    if (!MSPDescendsFrom(results, "SearchUIResultsViewController") || !MSPDescendsFrom(results, "UIViewController"))
        [why addObject:@"SPUIResultsViewController missing or not a SearchUIResultsViewController"];
    if (!rowModel) [why addObject:@"SearchUIRowModel missing"];
    if (!result) [why addObject:@"SFSearchResult missing"];
    if (!section) [why addObject:@"SFResultSection missing"];
    if (!text) [why addObject:@"SFText missing"];
    if (!MSPDescendsFrom(rich, "SFText")) [why addObject:@"SFRichText missing or not an SFText"];
    if (!MSPDescendsFrom(symbol, "SFImage")) [why addObject:@"SFSymbolImage missing or not an SFImage"];
    if (!MSPDescendsFrom(appIcon, "SFImage")) [why addObject:@"SFAppIconImage missing or not an SFImage"];
    MSPTapKind tap = MSPTapKindFor(handler16, command15, tapCommand15);
    if (tap == MSPTapNone) [why addObject:@"no tap path (+[SearchUICommandHandler handlerForRowModel:environment:] or +[SearchUICommand tapCommandForRowModel:environment:])"];
    if (tap == MSPTapCommand15 && !MSPDescendsFrom(tapCommand15, "SearchUICommand")) [why addObject:@"SearchUITapCommand not a SearchUICommand"];
    if (tap == MSPTapHandler16 && !collection16) [why addObject:@"SearchUICollectionViewController missing"];
    if (tap == MSPTapHandler16 && !collectionModel16) [why addObject:@"SearchUICollectionModel missing"];
    if (why.count) return MSPTapNone;
    NSString *obj = MSPExpect(@encode(id), NULL), *none = MSPExpect(@encode(void), NULL), *takesObj = MSPExpect(@encode(void), @encode(id), NULL),
             *isBool = MSPExpect(@encode(BOOL), NULL), *objFromTwo = MSPExpect(@encode(id), @encode(id), @encode(id), NULL),
             *objFromObj = MSPExpect(@encode(id), @encode(id), NULL);
    // the results list: the call that shows the sections (hooked), the typed text, and Apple's own push of its sections again
    MSPHas(results, "updateWithResultSections:resetScrollPoint:", MSPExpect(@encode(void), @encode(id), @encode(BOOL), NULL), why);
    MSPHas(results, "queryString", obj, why);
    MSPHas(results, "_pushSectionsUpdate", none, why);
    // a row: the result it shows
    MSPHas(rowModel, "identifyingResult", obj, why);
    // a result: made by us (title, lines under it, picture, our identifier); read for the identifier and the app of Apple's rows
    MSPHas(result, "init", obj, why);
    MSPHas(result, "setIdentifier:", takesObj, why);
    MSPHas(result, "identifier", obj, why);
    MSPHas(result, "setTitle:", takesObj, why);
    MSPHas(result, "setDescriptions:", takesObj, why);
    MSPHas(result, "setThumbnail:", takesObj, why);
    MSPHas(result, "applicationBundleIdentifier", obj, why);
    // a section: made by us; Apple's copied when a row of ours is taken out of it
    MSPHas(section, "init", obj, why);
    MSPHas(section, "results", obj, why);
    MSPHas(section, "setResults:", takesObj, why);
    MSPHas(section, "setTitle:", takesObj, why);
    MSPHas(section, "setBundleIdentifier:", takesObj, why);
    MSPHas(section, "setIdentifier:", takesObj, why);
    MSPHas(section, "copyWithZone:", MSPExpect(@encode(id), @encode(struct _NSZone *), NULL), why);
    // texts and pictures
    MSPHasClassMethod(text, "textWithString:", objFromObj, why);
    MSPHasClassMethod(rich, "textWithString:", objFromObj, why);
    MSPHas(symbol, "setSymbolName:", takesObj, why);
    MSPHas(appIcon, "setBundleIdentifier:", takesObj, why);
    if (tap == MSPTapHandler16) {   // 16: the factory (hooked), Apple's init our handler is made with, the methods it overrides, and the highlight
        MSPHasClassMethod(handler16, "handlerForRowModel:environment:", objFromTwo, why);
        MSPHas(collection16, "canHighlightRowAtIndexPath:", MSPExpect(@encode(BOOL), @encode(id), NULL), why);   // (hooked)
        MSPHas(collection16, "collectionModel", obj, why);
        MSPHas(collectionModel16, "rowModelForIndexPath:", objFromObj, why);
        MSPHas(handler16, "initWithCommand:rowModel:button:environment:", MSPExpect(@encode(id), @encode(id), @encode(id), @encode(id), @encode(id), NULL), why);
        MSPHas(handler16, "rowModel", obj, why);
        MSPHas(handler16, "executeWithTriggerEvent:", MSPExpect(@encode(void), @encode(unsigned long long), NULL), why);
        MSPHas(handler16, "shouldDeselectAfterExecution", isBool, why);
        MSPHas(handler16, "supportsCopy", isBool, why);
        MSPHas(handler16, "supportsShare", isBool, why);
        MSPHas(handler16, "prefersContextMenu", isBool, why);
    } else {   // 15: the factory (hooked), Apple's init our command is made with, and the methods it overrides
        MSPHasClassMethod(command15, "tapCommandForRowModel:environment:", objFromTwo, why);
        MSPHas(command15, "initWithRowModel:command:environment:", MSPExpect(@encode(id), @encode(id), @encode(id), @encode(id), NULL), why);
        MSPHas(command15, "rowModel", obj, why);
        MSPHas(tapCommand15, "performCommandWithCompletion:", takesObj, why);
        MSPHas(tapCommand15, "presentsViewController", isBool, why);
    }
    return why.count ? MSPTapNone : tap;
}
