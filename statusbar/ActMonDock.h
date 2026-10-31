// ActMonDock.h -- Activity Monitor in the Dock (1.7.3 item 5, KT 31 Oct: added to the Dock by the user like a normal app, not a permanent slot).
// Included at the end of AppLibraryApps.h (StatusBar.x). The App Library's Activity Monitor icon (DMALIcon: one of SpringBoard's own leaf icons)
// goes into SpringBoard's own Dock list, so the Dock treats it as an app: SpringBoard's drag in from the App Library, its reordering, layout and
// magnification, the tap (the icon's launch: the window comes or comes forward), the Dock's running dot (RunningIndicator.m, MSBDOwnAppsRunning).
// Its identifier is never saved in SpringBoard's layout:
//  - SpringBoard's store gets the layout without it (-saveCurrentIconState:error: / -saveDesiredIconState:error:, common/ActMonDock.h
//    MSBDLayoutWithout): IconState.plist never names it, so with the tweak removed, switched off, in Safe Mode or on an untested iPadOS no dead
//    icon can stay -- nothing for postrm to clean. It only goes into the Dock where that hook is in;
//  - its place is our own record (activityMonitorDock: its index among the Dock's icons; absent = not in the Dock), kept at each save of
//    SpringBoard's layout while it is in the Dock, cleared when it is taken out (its menu, a drag out of the Dock, the Dock's Trash), read at start:
//    once SpringBoard has laid out its Dock list, the icon goes back in at that place (again if SpringBoard makes the list anew);
//  - only the Dock: the root folder refuses it in any other list (-iconListModel:isAllowedToContainIcon:): it can't be dropped on a page or in a
//    folder; dragged out of the Dock and let go anywhere else (no taker: the drop is cancelled) it leaves the Dock, as on a Mac.
// It follows Settings > Status Bar > Activity Monitor > Show in App Library (DMALApplyPref): off, it leaves the Dock and the record stays; on, it
// comes back. Its menus (DMAMMenu): Open, Add to Dock ("Dock full" greyed) / Remove from Dock.
#include "../common/ActMonDock.h"

#define kDMAMDockKey CFSTR("activityMonitorDock")
static BOOL gDMAMReady = NO;            // the store's hook is in: only then does the icon ever go into the Dock
static BOOL gDMAMStarted = NO;          // the start's look for SpringBoard's Dock list is done (before it, a save never changes the record)
static __weak id gDMAMListPutIn;        // the Dock list the icon was last put into by us (a new list from SpringBoard: put in again, once)
static NSInteger gDMAMRecord = -2;      // the record as last read or written (-2: not read yet)

static id DMAMModel(void) { return DMCall(DMCall(DMCall(objc_getClass("SBIconController"), @"sharedInstance"), @"iconManager"), @"iconModel"); }
static id DMAMDockList(void) { return DMCall(DMCall(DMAMModel(), @"rootFolder"), @"dock"); }
static NSArray *DMAMIconsOf(id list) { id a = DMCall(list, @"icons"); return [a isKindOfClass:[NSArray class]] ? a : nil; }
static NSInteger DMAMDockIndex(void) {   // its place in the Dock list now, -1 when not there
    id icon = gDMALIcon; NSArray *a = icon ? DMAMIconsOf(DMAMDockList()) : nil;
    NSUInteger i = a ? [a indexOfObjectIdenticalTo:icon] : NSNotFound;
    return i == NSNotFound ? -1 : (NSInteger)i;
}
// The Dock's own icons -- not its recent apps (SBIconLocationFloatingDockSuggestions), not the App Library opened from its button.
static BOOL DMAMLocationIsDock(id loc) {
    return [loc isKindOfClass:[NSString class]] && [loc containsString:@"Dock"] && ![loc containsString:@"Library"] && ![loc containsString:@"Suggestions"] && ![loc containsString:@"Recent"];
}

// ---- the record: our own preference, never SpringBoard's layout ----
static NSInteger DMAMRecordRead(void) {
    if (gDMAMRecord != -2) return gDMAMRecord;
    CFPropertyListRef v = CFPreferencesCopyValue(kDMAMDockKey, MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    gDMAMRecord = MSBDActMonDockRecord((__bridge id)v);
    if (v) CFRelease(v);
    return gDMAMRecord;
}
static void DMAMRecordWrite(NSInteger place, NSString *why) {
    if (place < 0) place = -1;
    if (place == DMAMRecordRead()) return;
    CFPreferencesSetValue(kDMAMDockKey, place >= 0 ? (__bridge CFPropertyListRef)@(place) : NULL, MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    gDMAMRecord = place;
    DMLog([NSString stringWithFormat:@"[amdock] record: %@ (%@)", place >= 0 ? [NSString stringWithFormat:@"place %ld in the Dock", (long)place] : @"not in the Dock", why]);
}

// ---- in and out of SpringBoard's Dock list ----
static void DMAMSaveLayout(void) {   // (as after any change of the Home Screen: SpringBoard's own save -- which comes back through the store's hook)
    id model = DMAMModel();
    if ([model respondsToSelector:NSSelectorFromString(@"markIconStateDirty")]) ((void (*)(id, SEL))objc_msgSend)(model, NSSelectorFromString(@"markIconStateDirty"));
    if ([model respondsToSelector:NSSelectorFromString(@"saveIconStateIfNeeded")]) ((BOOL (*)(id, SEL))objc_msgSend)(model, NSSelectorFromString(@"saveIconStateIfNeeded"));
}
static BOOL DMAMDockHasRoom(id dock, id icon) {   // (the list's own rule: its room, and what it may hold -- the root folder's, with our hook below)
    SEL allows = NSSelectorFromString(@"allowsAddingIcon:");
    if (dock && icon && [dock respondsToSelector:allows]) return ((BOOL (*)(id, SEL, id))objc_msgSend)(dock, allows, icon);
    SEL full = NSSelectorFromString(@"isFull");
    return dock && !([dock respondsToSelector:full] && ((BOOL (*)(id, SEL))objc_msgSend)(dock, full));
}
static BOOL DMAMDockPutIn(NSInteger at, NSString *why) {
    id dock = DMAMDockList(), icon = DMALIcon();
    NSArray *icons = DMAMIconsOf(dock);
    if (!gDMAMReady || !gDMALOn || !dock || !icon || !icons) return NO;
    if ([icons indexOfObjectIdenticalTo:icon] != NSNotFound) { gDMAMListPutIn = dock; return YES; }
    SEL ins = NSSelectorFromString(@"insertIcons:atIndex:options:");
    if (![dock respondsToSelector:ins]) { DMLog(@"[amdock] the Dock list takes no -insertIcons:atIndex:options: here: not put in"); return NO; }
    if (!DMAMDockHasRoom(dock, icon)) { DMLog([NSString stringWithFormat:@"[amdock] no room in the Dock (%lu icons): not put in (%@)", (unsigned long)icons.count, why]); return NO; }
    NSUInteger i = (NSUInteger)MAX((NSInteger)0, MIN(at, (NSInteger)icons.count));
    @try { ((void (*)(id, SEL, id, NSUInteger, unsigned long long))objc_msgSend)(dock, ins, @[icon], i, 0); } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[amdock] the Dock list refused it: %@", e.reason]); return NO; }
    gDMAMListPutIn = dock;
    NSInteger now = DMAMDockIndex();
    DM_FEATURE_MARK("actmon-dock-in");
    DMLog([NSString stringWithFormat:@"[amdock] Activity Monitor put in the Dock at %ld of %lu (%@)%@", (long)now, (unsigned long)DMAMIconsOf(dock).count, why, now < 0 ? @": NOT there after it" : @""]);
    return now >= 0;
}
static BOOL DMAMDockTakeOut(NSString *why, BOOL forget) {
    id dock = DMAMDockList(), icon = gDMALIcon;
    if (forget) DMAMRecordWrite(-1, why);
    if (!dock || !icon || DMAMDockIndex() < 0) return NO;
    SEL rm = NSSelectorFromString(@"removeIcons:");   // (as the Dock's Remove from Dock does, Dock.x)
    if (![dock respondsToSelector:rm]) return NO;
    ((void (*)(id, SEL, id))objc_msgSend)(dock, rm, @[icon]);
    DM_FEATURE_MARK("actmon-dock-out");
    DMLog([NSString stringWithFormat:@"[amdock] Activity Monitor taken out of the Dock (%@)%@", why, DMAMDockIndex() >= 0 ? @": STILL there" : @""]);
    DMAMSaveLayout();
    return YES;
}
// Removal from outside (the Dock's Trash, dock/TrashIcon.m through Dock.x; found with dlsym): out of the Dock, the record cleared.
__attribute__((visibility("default"))) BOOL MSBDActMonDockRemove(void) {
    if (![NSThread isMainThread] || DMAMDockIndex() < 0) return NO;
    return DMAMDockTakeOut(@"dropped on the Dock's Trash", YES);
}
// For the Dock's running dots (RunningIndicator.m, dlsym): Activity Monitor runs while its window exists (open or minimized), as an app on a Mac.
__attribute__((visibility("default"))) NSSet<NSString *> *MSBDOwnAppsRunning(void) {
    if (![NSThread isMainThread]) return nil;
    for (DMNativeWindow *w in gNativeWindows) if ([w isKindOfClass:[DMActivityMonitorWindow class]]) return [NSSet setWithObject:kDMALActMonIdentifier];
    return nil;
}

// Anywhere but the Dock (a page, a folder, the App Library's own list): SpringBoard's drop never puts it there (the root folder refuses it), but
// should any path of SpringBoard's ever do it -- its own simulated drop (a test call) put it on a new page of the iPad 2, 16.7.7 --, it leaves that
// list at once: it lives in the App Library, and the Dock when added.
static void DMAMTakeOutElsewhere(void) {
    id root = DMCall(DMAMModel(), @"rootFolder"), dock = DMAMDockList(), icon = gDMALIcon;
    if (!root || !icon) return;
    NSMutableArray *lists = [NSMutableArray arrayWithArray:DMALItems(DMCall(root, @"lists"))];
    id ignored = DMCall(root, @"ignoredList"); if (ignored) [lists addObject:ignored];
    SEL isFolder = NSSelectorFromString(@"isFolderIcon");
    for (id list in [lists arrayByAddingObject:dock ?: [NSNull null]]) for (id i in DMAMIconsOf(list) ?: @[])   // (folders on the pages and in the Dock: their lists)
        if ([i respondsToSelector:isFolder] && ((BOOL (*)(id, SEL))objc_msgSend)(i, isFolder)) [lists addObjectsFromArray:DMALItems(DMCall(DMCall(i, @"folder"), @"lists"))];
    SEL has = NSSelectorFromString(@"directlyContainsIcon:"), rm = NSSelectorFromString(@"removeIcons:");
    for (id list in lists) {
        if (list == dock || ![list respondsToSelector:has] || ![list respondsToSelector:rm] || !((BOOL (*)(id, SEL, id))objc_msgSend)(list, has, icon)) continue;
        ((void (*)(id, SEL, id))objc_msgSend)(list, rm, @[icon]);
        DMLog([NSString stringWithFormat:@"[amdock] Activity Monitor was in a list other than the Dock (%@): taken out of it", NSStringFromClass([list class])]);
    }
}
// ---- the start, and a Dock list made anew: it goes back in at its recorded place ----
static void DMAMDockCheck(NSString *why) {
    if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(), ^{ DMAMDockCheck(why); }); return; }
    id dock = DMAMDockList();
    NSArray *icons = DMAMIconsOf(dock);
    if (!gDMAMReady || !icons) return;
    DMAMTakeOutElsewhere();
    NSInteger here = DMAMDockIndex();
    if (here >= 0) {   // (in the Dock: its place, after a move SpringBoard saved -- also a drop from the App Library, SpringBoard's own)
        gDMAMListPutIn = dock;
        if (gDMAMStarted && gDMALOn) DMAMRecordWrite(here, why);
        return;
    }
    gDMAMStarted = YES;
    NSInteger rec = DMAMRecordRead();
    if (!gDMALOn || rec < 0 || gDMAMListPutIn == dock) return;   // (switched off, not wanted, or SpringBoard took it out of the list we put it in: left out)
    SEL maxSel = NSSelectorFromString(@"maxNumberOfIcons");
    NSUInteger room = [dock respondsToSelector:maxSel] ? ((NSUInteger (*)(id, SEL))objc_msgSend)(dock, maxSel) : NSUIntegerMax;
    NSInteger at = MSBDActMonDockPlace(rec, icons.count, room ?: NSUIntegerMax);
    gDMAMListPutIn = dock;   // (once per list: SpringBoard's own reasons to take it out are not fought)
    if (at >= 0) DMAMDockPutIn(at, why);
    else DMLog([NSString stringWithFormat:@"[amdock] its place %ld: the Dock is full (%lu icons): not put back (%@)", (long)rec, (unsigned long)icons.count, why]);
}
static void DMAMStartLook(int tries) {   // (SpringBoard lays out its Home Screen during its start: until its Dock list is there, every 0.5 s, up to 60 s)
    if (DMAMIconsOf(DMAMDockList()) || tries >= 120) { DMAMDockCheck(@"SpringBoard's start"); gDMAMStarted = YES; return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMAMStartLook(tries + 1); });
}

// ---- the hooks ----
// SpringBoard's store: the layout without our icon, whatever list it is in; then the record follows (main thread: the icon model's).
// (each store class that has the method itself -- 15.6.1's SBDefaultIconModelStore has its own -saveCurrentIconState:error:, 16-18 inherit
//  SBIconModelPropertyListFileStore's -- gets its own trampoline with its own original: a subclass's call to super runs the base's, never its
//  own again. Taking our identifier out twice changes nothing.)
typedef BOOL (*DMAMSaveIMP)(id, SEL, id, NSError **);
static BOOL DMAMSaveVia(DMAMSaveIMP orig, id self, SEL _cmd, id state, NSError **err, BOOL current) {
    NSUInteger n = 0;
    id clean = MSBDLayoutWithout(state, kDMALActMonIdentifier, &n);
    if (n) DMLog([NSString stringWithFormat:@"[amdock] SpringBoard's %@ saved without Activity Monitor (%lu taken out)", current ? @"layout" : @"desired layout", (unsigned long)n]);
    BOOL ok = orig ? orig(self, _cmd, clean, err) : NO;
    if (current) dispatch_async(dispatch_get_main_queue(), ^{ DMAMDockCheck(@"SpringBoard saved its layout"); });   // (after SpringBoard's save has run its course)
    return ok;
}
#define DMAM_STORE_TRAMPOLINES(N) \
    static DMAMSaveIMP o_DMAMSave##N, o_DMAMDesired##N; \
    static BOOL DMAMSave##N(id self, SEL _cmd, id state, NSError **err) { return DMAMSaveVia(o_DMAMSave##N, self, _cmd, state, err, YES); } \
    static BOOL DMAMDesired##N(id self, SEL _cmd, id state, NSError **err) { return DMAMSaveVia(o_DMAMDesired##N, self, _cmd, state, err, NO); }
DMAM_STORE_TRAMPOLINES(0)
DMAM_STORE_TRAMPOLINES(1)
DMAM_STORE_TRAMPOLINES(2)
static BOOL DMAMOwnMethod(Class c, NSString *sel) {
    unsigned n = 0; Method *ms = c ? class_copyMethodList(c, &n) : NULL; BOOL own = NO;
    for (unsigned i = 0; i < n; i++) if (sel_isEqual(method_getName(ms[i]), NSSelectorFromString(sel)) && [DMMSWBareTypes(method_getTypeEncoding(ms[i])) isEqualToString:@"B@:@^@"]) own = YES;
    free(ms);
    return own;
}
// The store classes' saves hooked where each has its own; *names lists them. YES when every class with a current-layout save of its own is hooked
// and at least one is.
static BOOL DMAMHookStores(BOOL *desiredOut, NSMutableArray *names) {
    NSArray *classes = @[@"SBIconModelPropertyListFileStore", @"SBDefaultIconModelStore", @"SBDefaultAutomaticIconModelStore"];
    IMP saves[3] = { (IMP)DMAMSave0, (IMP)DMAMSave1, (IMP)DMAMSave2 }, desires[3] = { (IMP)DMAMDesired0, (IMP)DMAMDesired1, (IMP)DMAMDesired2 };
    DMAMSaveIMP *saveOrig[3] = { &o_DMAMSave0, &o_DMAMSave1, &o_DMAMSave2 }, *desiredOrig[3] = { &o_DMAMDesired0, &o_DMAMDesired1, &o_DMAMDesired2 };
    BOOL any = NO, all = YES, desired = YES, anyDesired = NO;
    for (NSUInteger i = 0; i < classes.count; i++) {
        Class c = objc_getClass([classes[i] UTF8String]);
        if (DMAMOwnMethod(c, @"saveCurrentIconState:error:")) {
            MSHookMessageEx(c, NSSelectorFromString(@"saveCurrentIconState:error:"), saves[i], (IMP *)saveOrig[i]);
            if (*saveOrig[i]) { any = YES; [names addObject:classes[i]]; } else all = NO;
        }
        if (DMAMOwnMethod(c, @"saveDesiredIconState:error:")) {
            MSHookMessageEx(c, NSSelectorFromString(@"saveDesiredIconState:error:"), desires[i], (IMP *)desiredOrig[i]);
            if (*desiredOrig[i]) anyDesired = YES; else desired = NO;
        }
    }
    if (desiredOut) *desiredOut = desired && anyDesired;
    return any && all;
}
// The root folder decides what its lists may hold: ours only the Dock list.
static BOOL (*o_DMAMAllowed)(id, SEL, id, id);
static BOOL DMAMAllowed(id self, SEL _cmd, id list, id icon) {
    if (!DMALIsOurs(icon)) return o_DMAMAllowed(self, _cmd, list, icon);
    id dock = DMAMDockList();
    if (!gDMAMReady || !gDMALOn || !dock || !list) return NO;
    // (the Dock list itself, or SpringBoard's copy of it -- a drop's room is worked out on a copy of the list: same unique identifier)
    id did = DMCall(dock, @"uniqueIdentifier"), lid = DMCall(list, @"uniqueIdentifier");
    BOOL isDock = list == dock || ([did isKindOfClass:[NSString class]] && [did isEqual:lid] && DMCall(list, @"folder") == DMCall(dock, @"folder"));
    return isDock && o_DMAMAllowed(self, _cmd, list, icon);
}
// SpringBoard's drop: a list view takes a drag of ours only when its list is the Dock's (the folder's rule above, asked earlier: no room made for it,
// no drop, on a page or anywhere else).
static BOOL (*o_DMAMCanAccept)(id, SEL, id, id);
static BOOL DMAMCanAccept(id self, SEL _cmd, id session, id listView) {
    BOOL ok = o_DMAMCanAccept(self, _cmd, session, listView);
    if (!ok || !gDMALIconClass) return ok;
    BOOL ours = NO;
    @try {
        SEL ctxSel = NSSelectorFromString(@"iconDragContextForDropSession:");
        id ctx = [self respondsToSelector:ctxSel] ? ((id (*)(id, SEL, id))objc_msgSend)(self, ctxSel, session) : nil;
        for (id icon in DMALItems(DMCall(ctx, @"draggedIcons"))) if (DMALIsOurs(icon)) ours = YES;
        if (DMALIsOurs(DMCall(DMCall(ctx, @"primaryIconView"), @"icon"))) ours = YES;
    } @catch (id e) { ours = NO; }
    if (!ours) return ok;
    id list = DMCall(listView, @"model"), dock = DMAMDockList();
    id did = DMCall(dock, @"uniqueIdentifier");
    return list && dock && (list == dock || ([did isKindOfClass:[NSString class]] && [did isEqual:DMCall(list, @"uniqueIdentifier")]));
}
// A drag of it out of the Dock, let go where nothing took it (the drop cancelled, outside the Dock): it leaves the Dock, as a Mac's Dock does.
static UIView *DMAMDockPlatter(void) {
    Class platter = objc_getClass("SBFloatingDockPlatterView");
    for (UIWindow *w in DMAllWindows()) {
        if (w.hidden || ![NSStringFromClass([w class]) isEqualToString:@"SBFloatingDockWindow"]) continue;
        NSMutableArray *todo = [NSMutableArray arrayWithObject:w];
        while (todo.count) { UIView *v = todo.lastObject; [todo removeLastObject]; if (platter && [v isKindOfClass:platter]) return v; [todo addObjectsFromArray:v.subviews]; }
    }
    return nil;
}
// (UIKit's own end of a drag that began on an icon view: -[SBIconView dragInteraction:session:didEndWithOperation:], 15-18)
static void (*o_DMAMDragEnded)(id, SEL, id, id, unsigned long long);
static void DMAMDragEnded(id self, SEL _cmd, id interaction, id session, unsigned long long op) {
    id iconView = self;
    BOOL ours = NO, fromDock = NO, outside = NO;
    @try {
        ours = DMALIsOurs(DMCall(iconView, @"icon"));
        fromDock = ours && DMAMLocationIsDock(DMCall(iconView, @"location"));
        UIView *platter = fromDock ? DMAMDockPlatter() : nil;
        if (platter && [session respondsToSelector:@selector(locationInView:)]) {
            CGPoint p = [(id<UIDragSession>)session locationInView:platter];
            outside = !CGRectContainsPoint(CGRectInset(platter.bounds, -6.0, -6.0), p);
        }
    } @catch (id e) { ours = NO; }
    o_DMAMDragEnded(self, _cmd, interaction, session, op);
    if (!ours) return;
    DMLog([NSString stringWithFormat:@"[amdock] a drag of Activity Monitor ended: from the Dock %d, let go outside it %d, operation %llu", fromDock, outside, op]);
    if (fromDock && outside && op <= 1)   // (UIDropOperationCancel / Forbidden: nothing took it; after SpringBoard has put it back in its place)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMAMDockTakeOut(@"dragged out of the Dock", YES); });
}

#if DEBUG
static void (*o_DMAMDebugDragBegins)(id, SEL, id, id);
static void DMAMDebugDragBegins(id self, SEL _cmd, id interaction, id session) {
    if (DMALIsOurs(DMCall(self, @"icon"))) DMLog([NSString stringWithFormat:@"[amdock] a drag of Activity Monitor begins (from %@)", DMCall(self, @"location")]);
    o_DMAMDebugDragBegins(self, _cmd, interaction, session);
}
#endif

// ---- its menu (App Library and Dock): Open, Add to Dock / Remove from Dock ----
static void DMAMAfterMenu(void (^block)(void)) {   // (once the menu has closed -- its preview animates the icon back into its place first)
    __block BOOL ran = NO;
    void (^once)(void) = ^{ if (ran) return; ran = YES; block(); };
    id mgr = DMCall(DMCall(objc_getClass("SBIconController"), @"sharedInstance"), @"iconManager");
    if (DMMSWHasMethod(object_getClass(mgr), @"performAfterIconContextMenuDismissesUsingBlock:", @"v@:@?"))
        ((void (*)(id, SEL, id))objc_msgSend)(mgr, NSSelectorFromString(@"performAfterIconContextMenuDismissesUsingBlock:"), ^{ dispatch_async(dispatch_get_main_queue(), once); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), once);
}
static UIMenu *DMAMMenu(id location) {
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:[UIAction actionWithTitle:@"Open" image:[UIImage systemImageNamed:@"macwindow"] identifier:nil handler:^(UIAction *a) {
        DMAMAfterMenu(^{ DMALOpen(location); });
    }]];
    if (gDMAMReady && gDMALOn) {
        if (DMAMDockIndex() >= 0) {
            [rows addObject:[UIAction actionWithTitle:@"Remove from Dock" image:[UIImage systemImageNamed:@"minus.circle"] identifier:nil handler:^(UIAction *a) {
                DMAMAfterMenu(^{ DMAMDockTakeOut(@"Remove from Dock in its menu", YES); });
            }]];
        } else {
            BOOL room = DMAMDockHasRoom(DMAMDockList(), DMALIcon());
            UIAction *add = [UIAction actionWithTitle:@"Add to Dock" image:[UIImage systemImageNamed:@"plus.circle"] identifier:nil handler:^(UIAction *a) {
                DMAMAfterMenu(^{
                    NSArray *icons = DMAMIconsOf(DMAMDockList());
                    if (DMAMDockPutIn((NSInteger)icons.count, @"Add to Dock in its menu")) { DMAMRecordWrite(DMAMDockIndex(), @"Add to Dock"); DMAMSaveLayout(); }
                });
            }];
            if (!room) { add.attributes = UIMenuElementAttributesDisabled; if (@available(iOS 15.0, *)) add.subtitle = @"Dock full"; }
            [rows addObject:add];
        }
    }
    return [UIMenu menuWithTitle:@"" children:@[[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:rows]]];
}

// ---- switched on / off (DMALApplyPref): the hooks go in the first time; off takes it out of the Dock (the record stays) ----
static void DMAMApply(BOOL on) {
    static BOOL hooked = NO;
    if (on && !hooked && DMALIconClass()) {
        hooked = YES;
        NSMutableArray *stores = [NSMutableArray array]; BOOL desired = NO;
        BOOL save = DMAMHookStores(&desired, stores);
        BOOL allowed = save && DMALHook(@"SBFolder", @"iconListModel:isAllowedToContainIcon:", @"B@:@@", (IMP)DMAMAllowed, (IMP *)&o_DMAMAllowed);
        BOOL drop = allowed && DMALHook(@"SBIconDragManager", @"canAcceptDropInSession:inIconListView:", @"B@:@@", (IMP)DMAMCanAccept, (IMP *)&o_DMAMCanAccept);
        BOOL drag = allowed && DMALHook(@"SBIconView", @"dragInteraction:session:didEndWithOperation:", @"v@:@@Q", (IMP)DMAMDragEnded, (IMP *)&o_DMAMDragEnded);
#if DEBUG
        DMALHook(@"SBIconView", @"dragInteraction:sessionWillBegin:", @"v@:@@", (IMP)DMAMDebugDragBegins, (IMP *)&o_DMAMDebugDragBegins);
#endif
        gDMAMReady = save && desired && allowed;   // (never in the Dock without its layout kept clean and the Dock-only rule)
        DMLog([NSString stringWithFormat:@"[amdock] Activity Monitor in the Dock: %@ (store's save %@ [%@], desired %@, Dock only %@, drops %@, drag out %@)", gDMAMReady ? @"ready" : @"NOT possible here",
               save ? @"hooked" : @"NOT hooked", [stores componentsJoinedByString:@", "], desired ? @"hooked" : @"NOT hooked", allowed ? @"hooked" : @"NOT hooked",
               drop ? @"hooked" : @"NOT hooked (the folder's rule only)", drag ? @"hooked" : @"NOT hooked (Remove from Dock only)"]);
        // (SpringBoard lays out its Home Screen during its start, on the main thread: the look begins once the main queue runs, 3 s on)
        if (gDMAMReady) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMAMStartLook(0); });
    }
    if (!gDMAMReady) return;
    if (!on) DMAMDockTakeOut(@"Show in App Library switched off", NO);
    else if (gDMAMStarted) { gDMAMListPutIn = nil; DMAMDockCheck(@"Show in App Library switched on"); }
}

#if DEBUG
// ---- debug triggers (amdbg_..., from DMRunTrigger): the Dock's state, its menu's actions, typing in the App Library's search, the app-folder scan ----
static UITextField *DMAMLibrarySearchField(void) {   // (the App Library's search field: a text field under a view of the App Library's)
    for (UIWindow *w in DMAllWindows()) {
        if (w.hidden) continue;
        NSMutableArray *todo = [NSMutableArray arrayWithObject:w];
        while (todo.count) {
            UIView *v = todo.lastObject; [todo removeLastObject]; [todo addObjectsFromArray:v.subviews];
            if (![v isKindOfClass:[UITextField class]] || !v.window || v.hidden) continue;
            if ([NSStringFromClass([v class]) isEqualToString:@"SBHSearchTextField"]) return (UITextField *)v;   // (18.5: the App Library's own field class)
            for (UIView *a = v.superview; a; a = a.superview) if ([NSStringFromClass([a class]) containsString:@"Library"]) return (UITextField *)v;
        }
    }
    return nil;
}
static void DMAMDebugScan(void);
static void DMAMDebugTrigger(NSString *cmd) {
    if ([cmd isEqualToString:@"amdbg_dock"]) {
        id model = DMAMModel(), dock = DMAMDockList(), icon = gDMALIcon;
        SEL track = NSSelectorFromString(@"isTrackingIcon:"), leaf = NSSelectorFromString(@"leafIconForIdentifier:");
        BOOL tracked = icon && [model respondsToSelector:track] && ((BOOL (*)(id, SEL, id))objc_msgSend)(model, track, icon);
        id byId = [model respondsToSelector:leaf] ? ((id (*)(id, SEL, id))objc_msgSend)(model, leaf, kDMALActMonIdentifier) : nil;
        id ignored = DMCall(DMCall(model, @"rootFolder"), @"ignoredList");
        BOOL inIgnored = icon && [DMAMIconsOf(ignored) indexOfObjectIdenticalTo:icon] != NSNotFound;
        SEL maxSel = NSSelectorFromString(@"maxNumberOfIcons");
        DMLog([NSString stringWithFormat:@"[amdbg] ready %d started %d on %d; record %ld; in the Dock at %ld of %lu (max %@, list %@ %@); model tracks it %d, leafIconForIdentifier %@, in the ignored list %d; room %d",
               gDMAMReady, gDMAMStarted, gDMALOn, (long)DMAMRecordRead(), (long)DMAMDockIndex(), (unsigned long)DMAMIconsOf(dock).count,
               [dock respondsToSelector:maxSel] ? @(((NSUInteger (*)(id, SEL))objc_msgSend)(dock, maxSel)) : @"?", NSStringFromClass([dock class]), DMCall(dock, @"uniqueIdentifier"),
               tracked, byId ? (byId == icon ? @"ours" : NSStringFromClass([byId class])) : @"nil", inIgnored, DMAMDockHasRoom(dock, DMALIcon())]);
    }
    else if ([cmd isEqualToString:@"amdbg_add"]) { NSArray *icons = DMAMIconsOf(DMAMDockList()); if (DMAMDockPutIn((NSInteger)icons.count, @"debug")) { DMAMRecordWrite(DMAMDockIndex(), @"debug"); DMAMSaveLayout(); } }
    else if ([cmd hasPrefix:@"amdbg_addat_"]) { if (DMAMDockPutIn([[cmd substringFromIndex:12] integerValue], @"debug")) { DMAMRecordWrite(DMAMDockIndex(), @"debug"); DMAMSaveLayout(); } }
    else if ([cmd isEqualToString:@"amdbg_remove"]) DMAMDockTakeOut(@"debug", YES);
    else if ([cmd isEqualToString:@"amdbg_menu"]) {
        for (NSString *loc in @[@"SBIconLocationAppLibrary", @"SBIconLocationFloatingDock"]) {
            NSMutableArray *t = [NSMutableArray array];
            for (UIMenu *sec in DMAMMenu(loc).children) for (UIMenuElement *e in ([sec isKindOfClass:[UIMenu class]] ? sec.children : @[sec])) {
                UIAction *a = [e isKindOfClass:[UIAction class]] ? (UIAction *)e : nil;
                NSString *sub = nil; if (@available(iOS 15.0, *)) sub = a.subtitle;
                [t addObject:[NSString stringWithFormat:@"%@%@%@", e.title, a && (a.attributes & UIMenuElementAttributesDisabled) ? @" (greyed)" : @"", sub.length ? [NSString stringWithFormat:@" \"%@\"", sub] : @""]];
            }
            DMLog([NSString stringWithFormat:@"[amdbg] menu at %@: %@", loc, [t componentsJoinedByString:@" | "]]);
        }
    }
    else if ([cmd hasPrefix:@"amdbg_type_"]) {   // amdbg_type_<text>_<ms>: the App Library's search field gets the text one letter every <ms> ms (as typed)
        NSArray *q = [[cmd substringFromIndex:11] componentsSeparatedByString:@"_"];
        NSString *text = q.firstObject ?: @""; double ms = q.count > 1 ? [q[1] doubleValue] : 100.0;
        UITextField *f = DMAMLibrarySearchField();
        if (!f) { DMLog(@"[amdbg] no App Library search field on screen"); return; }
        if (!f.isFirstResponder) [f becomeFirstResponder];
        DMLog([NSString stringWithFormat:@"[amdbg] typing \"%@\" into the App Library's search, a letter every %.0f ms", text, ms]);
        for (NSUInteger i = 0; i < text.length; i++) {
            NSString *ch = [text substringWithRange:NSMakeRange(i, 1)];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((0.15 + ms / 1000.0 * i) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [f insertText:ch]; });
        }
    }
    else if ([cmd hasPrefix:@"amdbg_back_"]) {   // amdbg_back_<n>_<ms>: <n> backspaces, one every <ms> ms
        NSArray *q = [[cmd substringFromIndex:11] componentsSeparatedByString:@"_"];
        NSInteger n = [q.firstObject integerValue]; double ms = q.count > 1 ? [q[1] doubleValue] : 100.0;
        UITextField *f = DMAMLibrarySearchField();
        if (!f) { DMLog(@"[amdbg] no App Library search field on screen"); return; }
        for (NSInteger i = 0; i < n; i++) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((0.15 + ms / 1000.0 * i) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [f deleteBackward]; });
    }
    else if ([cmd isEqualToString:@"amdbg_search"]) {   // what the search list shows now: its text, and whether Activity Monitor is in its list
        UITextField *f = DMAMLibrarySearchField();
        DMLog([NSString stringWithFormat:@"[amdbg] search field \"%@\" (first responder %d); the list's last result had Activity Monitor: %d", f.text, f.isFirstResponder, gDMALShown]);
    }
    else if ([cmd isEqualToString:@"amdbg_scan"]) DMAMDebugScan();
    else if ([cmd hasPrefix:@"amdbg_simdrop_"]) {   // amdbg_simdrop_<dock|page>: SpringBoard's own simulated icon drag (its test calls) of our icon view on
                                                   // screen, dropped into the Dock's list or the Home Screen page's -- what SpringBoard's drop does with it
        BOOL toDock = [cmd hasSuffix:@"dock"];
        id drags = DMCall(DMCall(DMCall(objc_getClass("SBIconController"), @"sharedInstance"), @"iconManager"), @"iconDragManager");
        Class ivc = objc_getClass("SBIconView"), lvc = objc_getClass("SBIconListView");
        UIView *source = nil, *target = nil;
        id dock = DMAMDockList(), firstPage = [DMCall(DMCall(DMAMModel(), @"rootFolder"), @"lists") firstObject];
        for (UIWindow *w in DMAllWindows()) {
            if (w.hidden) continue;
            NSMutableArray *todo = [NSMutableArray arrayWithObject:w];
            while (todo.count) {
                UIView *v = todo.lastObject; [todo removeLastObject]; [todo addObjectsFromArray:v.subviews];
                if (!source && ivc && [v isKindOfClass:ivc] && DMALIsOurs(DMCall(v, @"icon")) && v.window) source = v;
                if (!target && lvc && [v isKindOfClass:lvc] && v.window && DMCall(v, @"model") == (toDock ? dock : firstPage)) target = v;
            }
        }
        SEL start = NSSelectorFromString(@"simulateDragStartedFromIconView:"), pause = NSSelectorFromString(@"simulateIconDragWithIdentifier:didPauseAtLocation:inIconListView:");
        SEL drop = NSSelectorFromString(@"simulatePerformIconDropWithIdentifier:inIconListView:"), end = NSSelectorFromString(@"simulateIconDraggingEndedWithIdentifier:");
        if (!source || !target || ![drags respondsToSelector:start] || ![drags respondsToSelector:pause] || ![drags respondsToSelector:drop] || ![drags respondsToSelector:end]) {
            DMLog([NSString stringWithFormat:@"[amdbg] simulated drop: source %@, target %@ (%@), calls %d", source ? DMCall(source, @"location") : @"none", target ? NSStringFromClass([target class]) : @"none", toDock ? @"Dock" : @"page", [drags respondsToSelector:start]]);
            return;
        }
        id ident = ((id (*)(id, SEL, id))objc_msgSend)(drags, start, source);
        DMLog([NSString stringWithFormat:@"[amdbg] simulated drag from %@: %@", DMCall(source, @"location"), ident]);
        if (!ident) return;
        CGPoint at = CGPointMake(CGRectGetMaxX(target.bounds) - 10.0, CGRectGetMidY(target.bounds));
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            ((void (*)(id, SEL, id, CGPoint, id))objc_msgSend)(drags, pause, ident, at, target);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                ((void (*)(id, SEL, id, id))objc_msgSend)(drags, drop, ident, target);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    ((void (*)(id, SEL, id))objc_msgSend)(drags, end, ident);
                    DMLog([NSString stringWithFormat:@"[amdbg] simulated drop into the %@ done: in the Dock at %ld", toDock ? @"Dock" : @"page", (long)DMAMDockIndex()]);
                });
            });
        });
    }
    else if ([cmd isEqualToString:@"amdbg_views"]) {   // its icon views on screen: where, and what SpringBoard says about dragging them
        Class ivc = objc_getClass("SBIconView");
        id drags = DMCall(DMCall(DMCall(objc_getClass("SBIconController"), @"sharedInstance"), @"iconManager"), @"iconDragManager");
        for (UIWindow *w in DMAllWindows()) {
            NSMutableArray *todo = [NSMutableArray arrayWithObject:w];
            while (todo.count) {
                UIView *v = todo.lastObject; [todo removeLastObject]; [todo addObjectsFromArray:v.subviews];
                if (!ivc || ![v isKindOfClass:ivc] || !DMALIsOurs(DMCall(v, @"icon"))) continue;
                SEL can = NSSelectorFromString(@"canBeginDrags"), mgrCan = NSSelectorFromString(@"iconViewCanBeginDrags:");
                BOOL c1 = [v respondsToSelector:can] && ((BOOL (*)(id, SEL))objc_msgSend)(v, can);
                BOOL c2 = [drags respondsToSelector:mgrCan] && ((BOOL (*)(id, SEL, id))objc_msgSend)(drags, mgrCan, v);
                UIDragInteraction *di = DMCall(v, @"dragInteraction");
                id del = DMCall(v, @"delegate"), dragDel = DMCall(v, @"dragDelegate");
                DMLog([NSString stringWithFormat:@"[amdbg] icon view in %@ (%@) at %@: canBeginDrags %d, drag manager says %d, drag interaction %@ enabled %d, delegate %@, drag delegate %@, editing %d",
                       NSStringFromClass([w class]), DMCall(v, @"location"), NSStringFromCGRect([v convertRect:v.bounds toView:nil]), c1, c2, di ? @"yes" : @"no", di.enabled,
                       NSStringFromClass([del class]), NSStringFromClass([dragDel class]),
                       [v respondsToSelector:NSSelectorFromString(@"isEditing")] && ((BOOL (*)(id, SEL))objc_msgSend)(v, NSSelectorFromString(@"isEditing"))]);
            }
        }
    }
    else if ([cmd isEqualToString:@"amdbg_windows"]) {
        NSMutableArray *t = [NSMutableArray array];
        for (DMNativeWindow *w in gNativeWindows) [t addObject:[NSString stringWithFormat:@"%@%@%@", w.title, w.hidden ? @" (hidden)" : @"", w == gNativeActive ? @" (active)" : @""]];
        DMLog([NSString stringWithFormat:@"[amdbg] native windows, back to front: %@; active app %@", [t componentsJoinedByString:@", "], DMNativeActiveApp().title]);
    }
}
// Finder's On My iPad app-folder scan (Finder.h DMFinderAppFoldersScan), step by step with the time each takes, in SpringBoard, off the main thread
// (item 12: 5.2 s on the M1 from Finder, 57 ms for the same calls from a command-line tool as mobile).
static double DMAMms(void) { return CACurrentMediaTime() * 1000.0; }
static void DMAMDebugScan(void) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableString *out = [NSMutableString string];
        double t0 = DMAMms(), a = DMAMms();
        NSSet *hidden = DMFinderHiddenApps();
        [out appendFormat:@"hidden apps %.1f ms; ", DMAMms() - a];
        a = DMAMms();
        NSArray *proxies = DMCall(DMCall(objc_getClass("LSApplicationWorkspace"), @"defaultWorkspace"), @"allInstalledApplications");
        [out appendFormat:@"allInstalledApplications %lu in %.1f ms; ", (unsigned long)proxies.count, DMAMms() - a];
        SEL infoKey = NSSelectorFromString(@"objectForInfoDictionaryKey:ofClass:"), sharing = NSSelectorFromString(@"fileSharingEnabled"), inPlace = NSSelectorFromString(@"supportsOpenInPlace");
        Class meta = objc_getClass("FPAppMetadata"); SEL custom = NSSelectorFromString(@"_localizedCustomDisplayNameForAppProxy:");
        BOOL askCustom = meta && [meta respondsToSelector:custom];
        double tShare = 0, tPlace = 0, tInfo = 0, tData = 0, tCustom = 0, tName = 0, tNorm = 0, tDir = 0, worst = 0; int cand = 0; NSString *worstWhat = @"";
        for (id proxy in proxies) {
            a = DMAMms(); BOOL share = [proxy respondsToSelector:sharing] && ((BOOL (*)(id, SEL))objc_msgSend)(proxy, sharing); tShare += DMAMms() - a;
            BOOL ok = NO;
            if (share) {
                a = DMAMms();
                if ([proxy respondsToSelector:inPlace]) ok = ((BOOL (*)(id, SEL))objc_msgSend)(proxy, inPlace);
                else { id rec = DMCall(proxy, @"correspondingApplicationRecord"); if (rec && [rec respondsToSelector:inPlace]) ok = ((BOOL (*)(id, SEL))objc_msgSend)(rec, inPlace); }
                tPlace += DMAMms() - a;
            }
            if (!ok) {
                a = DMAMms();
                id v = [proxy respondsToSelector:infoKey] ? ((id (*)(id, SEL, id, Class))objc_msgSend)(proxy, infoKey, @"UISupportsDocumentBrowser", [NSNumber class]) : nil;
                double d = DMAMms() - a; tInfo += d; if (d > worst) { worst = d; worstWhat = @"Info.plist key"; }
                ok = [v isKindOfClass:[NSNumber class]] && [v boolValue];
            }
            if (!ok) continue;
            cand++;
            a = DMAMms(); NSURL *data = DMCall(proxy, @"dataContainerURL"); double d = DMAMms() - a; tData += d; if (d > worst) { worst = d; worstWhat = @"dataContainerURL"; }
            if (![data isKindOfClass:[NSURL class]]) continue;
            a = DMAMms(); NSString *docs = DMFinderNorm([data.path stringByAppendingPathComponent:@"Documents"]); d = DMAMms() - a; tNorm += d; if (d > worst) { worst = d; worstWhat = @"DMFinderNorm"; }
            struct stat st; if (lstat(docs.fileSystemRepresentation, &st) != 0 || !S_ISDIR(st.st_mode)) continue;
            if (askCustom) { a = DMAMms(); ((id (*)(id, SEL, id))objc_msgSend)((id)meta, custom, proxy); d = DMAMms() - a; tCustom += d; if (d > worst) { worst = d; worstWhat = @"FPAppMetadata name"; } }
            a = DMAMms(); DMCall(proxy, @"localizedName"); tName += DMAMms() - a;
            a = DMAMms(); DIR *dd = opendir(docs.fileSystemRepresentation); if (dd) { readdir(dd); closedir(dd); } tDir += DMAMms() - a;
        }
        [out appendFormat:@"fileSharingEnabled %.1f, supportsOpenInPlace %.1f, Info.plist key %.1f, dataContainerURL %.1f, DMFinderNorm %.1f, FPAppMetadata name %.1f (asked %d), localizedName %.1f, opendir %.1f ms; %d candidates (%lu hidden apps); slowest single call %.1f ms (%@); total %.1f ms",
            tShare, tPlace, tInfo, tData, tNorm, tCustom, askCustom, tName, tDir, cand, (unsigned long)hidden.count, worst, worstWhat, DMAMms() - t0];
        a = DMAMms(); NSArray *real = DMFinderAppFoldersScan(); double tReal = DMAMms() - a;
        DMLog([NSString stringWithFormat:@"[amdbg] app-folder scan, step by step: %@; then DMFinderAppFoldersScan itself: %lu folders in %.1f ms", out, (unsigned long)real.count, tReal]);
    });
}
#endif
