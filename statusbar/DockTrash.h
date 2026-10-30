// DockTrash.h -- Finder's side of the Dock's Trash (1.7.0), included into StatusBar.x after Finder.h. The bin itself is the Dock's (dock/TrashIcon.m),
// the rules both share are common/DockTrash.h. Finder owns the Trash: it keeps the bin's empty / full state current (how many items Finder's
// Trash and the connected drives' Trashes hold, the state of kMSBDTrashStateName -- watched with the kernel's folder events, no polling), shows the
// Trash in a Finder window for a tap or Open, empties it with its own question for Empty Trash, and ejects the drives a drag drops on the bin.
// Only while Settings > Dock > Show Trash in Dock is on (the Dock's own switch, read here too) and Finder is on: otherwise nothing here runs.
#import "../common/DockTrash.h"
#include <sys/wait.h>

static BOOL gDockTrashOn = NO;   // (the bin is wanted: the Dock's switch, with Finder on)
static BOOL DMDockTrashPrefOn(void) {
    CFStringRef dom = CFSTR("com.besiktasliseba.dockmagnification");
    CFPreferencesAppSynchronize(dom);
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("showTrash"), dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    BOOL on = v && CFGetTypeID(v) == CFBooleanGetTypeID() && CFBooleanGetValue(v);
    if (v) CFRelease(v);
    return on;
}

// ---- the bin's state: how many items the Trash holds ----
// Finder's Trash and every connected drive's Trash (<volume>/.Trashes/501), the folders Finder's Trash window shows and Empty Trash erases -- each
// only when it is a real folder of its own (DMFinderTrashIsSound / DMFinderDriveTrashIsSound), as Finder itself uses them.
static NSArray<NSString *> *DMDockTrashFolders(void) {
    NSMutableArray *a = [NSMutableArray array];
    if (DMFinderTrashIsSound()) [a addObject:kFinderTrash];
    for (NSString *t in DMFinderDriveTrashes()) if (DMFinderDriveTrashIsSound(t)) [a addObject:t];
    return a;
}
static NSUInteger DMDockTrashCountNow(void) {
    NSUInteger n = 0;
    for (NSString *d in DMDockTrashFolders()) n += MSBDTrashCountNames([[NSFileManager defaultManager] contentsOfDirectoryAtPath:d error:nil]);
    return n;
}
static void DMDockTrashPublish(NSUInteger n) {
    static int token = 0; static long long last = -1;
    if (!token && notify_register_check(kMSBDTrashStateName, &token) != NOTIFY_STATUS_OK) { token = 0; return; }
    if ((long long)n == last) return;
    last = (long long)n;
    notify_set_state(token, (uint64_t)n);
    notify_post(kMSBDTrashStateName);
    DMLog([NSString stringWithFormat:@"[trash] Finder's Trash holds %lu item(s): the Dock's bin is %@", (unsigned long)n, n ? @"full" : @"empty"]);
}
// Counted off the main thread (a Trash of thousands of items is still only one listing per folder), at most once every 0.3 s; a change while a count
// runs is counted again right after it (never a stale bin).
static void DMDockTrashRecount(NSString *why) {
    static BOOL pending = NO, again = NO;
    if (pending) { again = YES; return; }
    pending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSUInteger n = DMDockTrashCountNow();
        dispatch_async(dispatch_get_main_queue(), ^{
            pending = NO;
            if (gDockTrashOn) DMDockTrashPublish(n);
            if (again) { again = NO; DMDockTrashRecount(@"changed while counting"); }
        });
    });
}
// The folders are watched (a vnode source each: an item put in or taken out writes the folder), whoever changes them -- Finder, Filza, a shell.
// A Trash not made yet: the folder it will be made in is watched instead (Finder's: /var/mobile; a drive's: its .Trashes, else the volume).
static NSMutableDictionary<NSString *, dispatch_source_t> *gDockTrashWatch;
static void DMDockTrashWatchFolders(void) {
    if (!gDockTrashWatch) gDockTrashWatch = [NSMutableDictionary dictionary];
    NSMutableSet *want = [NSMutableSet set];
    if (gDockTrashOn) {
        NSMutableArray *trashes = [NSMutableArray arrayWithObject:kFinderTrash];
        [trashes addObjectsFromArray:DMFinderDriveTrashes()];
        for (NSString *t in trashes) {
            NSString *w = t;
            for (int up = 0; up < 3 && w.length > 1; up++) {   // (the Trash, or the nearest folder above it that is there)
                struct stat st;
                if (lstat(w.fileSystemRepresentation, &st) == 0 && S_ISDIR(st.st_mode)) break;
                w = w.stringByDeletingLastPathComponent;
            }
            if (w.length > 1) [want addObject:w];
        }
    }
    for (NSString *d in gDockTrashWatch.allKeys) if (![want containsObject:d]) { dispatch_source_cancel(gDockTrashWatch[d]); [gDockTrashWatch removeObjectForKey:d]; }
    for (NSString *d in want) {
        if (gDockTrashWatch[d]) continue;
        int fd = open(d.fileSystemRepresentation, O_EVTONLY);   // (an event-only descriptor: it never keeps a drive from being ejected)
        if (fd < 0) continue;
        dispatch_source_t src = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, (uintptr_t)fd, DISPATCH_VNODE_WRITE | DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME | DISPATCH_VNODE_REVOKE, dispatch_get_main_queue());
        if (!src) { close(fd); continue; }
        NSString *dir = d;
        dispatch_source_set_event_handler(src, ^{
            unsigned long flags = dispatch_source_get_data(src);
            if (flags & (DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME | DISPATCH_VNODE_REVOKE)) {   // (the folder itself went: watched again, or its parent)
                dispatch_source_cancel(src); [gDockTrashWatch removeObjectForKey:dir];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMDockTrashWatchFolders(); });
            } else if (![dir isEqualToString:kFinderTrash] && ![DMFinderDriveTrashes() containsObject:dir]) {
                DMDockTrashWatchFolders();   // (a folder above a Trash changed: the Trash may have just been made)
            }
            DMDockTrashRecount(@"a Trash folder changed");
        });
        dispatch_source_set_cancel_handler(src, ^{ close(fd); });
        dispatch_resume(src);
        gDockTrashWatch[d] = src;
    }
}
// (Finder.h DMFinderDrivesCheck: a drive came or went -- its Trash is watched and counted, or no longer)
static void DMDockTrashDrivesChanged(void) {
    if (!gDockTrashOn) return;
    DMDockTrashWatchFolders();
    DMDockTrashRecount(@"the drives changed");
}
// The Dock's switch (its settings post the Dock's change) or Finder's own: the watch runs only while the bin is wanted.
static void DMDockTrashApplyPref(void) {
    BOOL on = gFinderOn && DMDockTrashPrefOn();
    if (on == gDockTrashOn) { if (on) DMDockTrashRecount(@"settings"); return; }
    gDockTrashOn = on;
    DMLog([NSString stringWithFormat:@"[trash] the Dock's Trash is %@", on ? @"on: Finder watches its Trash for the bin" : @"off"]);
    DMDockTrashWatchFolders();
    if (on) { DM_FEATURE_MARK("finder-dock-trash"); DMDockTrashRecount(@"switched on"); }
}

// ---- the bin's tap, Open, Empty Trash ----
// A tap, or Open in its menu: a Finder window on the Trash -- one that already shows it comes to the front (a minimized one comes back), else a new
// one opens, as a Mac's Dock does. Finder's other windows stay where they are.
static void DMDockTrashOpen(void) {
    if (!gFinderOn || DMGARefuses(@"the Dock's Trash")) return;
    DM_FEATURE_MARK("finder-dock-trash-open");
    DMFinderWindow *open = nil, *mini = nil;
    for (DMNativeWindow *w in [gNativeWindows reverseObjectEnumerator]) {
        if (![w isKindOfClass:[DMFinderWindow class]] || [w isKindOfClass:[DMFinderOpsHost class]]) continue;
        if (![DMFinderNorm(((DMFinderWindow *)w).path) isEqualToString:kFinderTrash]) continue;
        if (w.hidden) { if (!mini) mini = (DMFinderWindow *)w; } else if (!open) open = (DMFinderWindow *)w;
    }
    if (open) { [open.superview bringSubviewToFront:open]; [open activate]; }
    else if (mini) [mini show];
    else DMFinderOpen(kFinderTrash, YES);
    DMLog([NSString stringWithFormat:@"[trash] the Dock's Trash: %@", open ? @"its Finder window came to the front" : mini ? @"its minimized Finder window came back" : @"a new Finder window on the Trash"]);
}
// Empty Trash in the bin's menu: Finder's own question ("Are you sure you want to permanently erase the items in the Trash?") and its own erase --
// the same as Finder's Empty Trash (Finder.h -emptyTrash), run by Finder's operations outside a window, so its question is a dialog over
// everything, as a Mac's Dock asks. Nothing in the Trash: nothing is asked (the row is greyed then anyway). Counted off the main thread, as the
// bin's state is (DMDockTrashRecount): every drive's Trash is listed too, and a slow drive held SpringBoard there; the question comes on it.
static void DMDockTrashEmpty(void) {
    if (!gFinderOn || DMGARefuses(@"Empty Trash (Dock)")) return;
    DM_FEATURE_MARK("finder-dock-trash-empty");
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSUInteger n = DMDockTrashCountNow();
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!gFinderOn) return;
            if (!n) { DMLog(@"[trash] Empty Trash from the Dock: the Trash is empty, nothing to ask"); return; }
            DMLog(@"[trash] Empty Trash from the Dock: Finder's question");
            [DMFinderOps() emptyTrash];
        });
    });
}

// ---- the drives a drag drops on the bin: ejected ----
// The way the Files app ejects a drive: StorageKit's storagekitd, asked to eject the disk the volume is on. That request needs StorageKit's
// state-changing entitlement, which SpringBoard does not have, so a small helper of ours that has it does it (ejecthelper/, /usr/libexec/msbdeject):
// spawned with the volume's folder, it checks for itself that it is a connected drive and not the iPad's own storage, and answers with one line.
// Nothing is forced: a drive in use stays, and Finder says so in a Mac's words.
static NSString *const kDockTrashEjectHelper = @"/var/jb/usr/libexec/msbdeject";
// Whether this iPadOS can eject a drive at all: StorageKit is there for the helper to load (in the shared cache or on disk, the way dlopen finds it;
// nothing is loaded into SpringBoard for the look). 16 on, it is; 15 has neither StorageKit nor storagekitd (15.6.1: the helper's --info finds no
// manager), so there the bin never turns into Eject and a drive dropped on it is refused (common/DockTrash.h canEject; KT, 1.7.0). Decided once.
static BOOL DMDockTrashCanEject(void) {
    static int can = -1;
    if (can < 0) {
        const char *sk = "/System/Library/PrivateFrameworks/StorageKit.framework/StorageKit";
        can = (_dyld_shared_cache_contains_path(sk) || access(sk, F_OK) == 0) ? 1 : 0;
        DMLog([NSString stringWithFormat:@"[trash] drive eject %@", can ? @"available (StorageKit)" : @"not on this iPadOS (no StorageKit): drives are never ejected from the Dock's Trash, no Eject offered"]);
    }
    return can == 1;
}
static void DMDockTrashEjectOne(NSString *root, NSString *name) {
    DM_FEATURE_MARK("finder-dock-trash-eject");
#if DEBUG
    if (DMTestFlag("/tmp/msb-feject-ok")) {   // (tests without a real drive: the eject is taken as done -- nothing spawned)
        DMLog([NSString stringWithFormat:@"[trash] eject (test): %@ would be ejected now", name]);
        return;
    }
#endif
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSData *out = nil; int status = -1;   // (common/DockTrash.h: only the descriptors it uses go with it, Mac-tested)
        char *argv[] = { (char *)"msbdeject", (char *)root.fileSystemRepresentation, NULL };
        int rc = MSBDTrashRunHelper(kDockTrashEjectHelper.fileSystemRepresentation, argv, &out, &status);
        NSString *answer = rc == 0 ? [[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding]
                         : rc < 0 ? @"error: no pipe" : [NSString stringWithFormat:@"error: the eject helper could not be started (%d)", rc];
        NSString *line = [[[answer ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsSeparatedByString:@"\n"] lastObject] ?: @"";
        int code = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
        dispatch_async(dispatch_get_main_queue(), ^{
            DMLog([NSString stringWithFormat:@"[trash] eject of a drive: exit %d, \"%@\"", code, line]);
            // (the helper's own line decides: SpringBoard may reap its children itself, and then no exit status comes back here)
            if ([line hasPrefix:@"ok"]) { DMFinderDrivesForget(); DMFinderDrivesCheck(@"ejected"); return; }   // (the sidebar and the windows follow at once)
            NSString *title = [line hasPrefix:@"busy"] ? [NSString stringWithFormat:@"The disk “%@” wasn’t ejected because one or more programs may be using it.", name]
                                                      : [NSString stringWithFormat:@"The disk “%@” couldn’t be ejected.", name];
            NSRange colon = [line rangeOfString:@": "];
            NSString *why = colon.location != NSNotFound ? [line substringFromIndex:colon.location + 2] : nil;
            if (why.length) why = [[[why substringToIndex:1] uppercaseString] stringByAppendingFormat:@"%@%@", [why substringFromIndex:1], [why hasSuffix:@"."] ? @"" : @"."];   // (a sentence)
            DMFinderLooseSheet(title, [line hasPrefix:@"busy"] ? @"Close the files on it and try again." : why, @"OK", NO, nil, nil);
        });
    });
}
static void DMDockTrashEject(NSArray<NSString *> *roots) {
    if (!gFinderOn || !DMDockTrashCanEject() || DMGARefuses(@"Eject (Dock)")) return;
    for (NSString *root in roots) {
        NSDictionary *d = DMFinderDriveInfo(DMFinderNorm(root));
        if (!d) { DMLog(@"[trash] eject: that drive is not connected any more"); continue; }
        DMLog([NSString stringWithFormat:@"[trash] eject: %@", d[@"t"]]);
        DMDockTrashEjectOne(d[@"p"], d[@"t"]);
    }
}

// ---- Finder's drags and the bin (Finder.h DMFinderDragMove / DMFinderDragEnd / DMFinderDragBegin / DMFDFinish) ----
// The bin under a screen point (the Dock's view, found by its class as the Downloads stack is), when it is shown and takes drops.
static UIView *DMFDTrashIconAt(CGPoint sp) {
    if (!gDockTrashOn) return nil;
    Class c = NSClassFromString(@"DMTrashIconView");
    if (!c || ![c instancesRespondToSelector:NSSelectorFromString(@"dm_trashTarget")]) return nil;
    for (UIWindow *w in DMAllWindows()) {
        if (w.hidden || w.alpha < 0.01 || ![NSStringFromClass([w class]) isEqualToString:@"SBFloatingDockWindow"]) continue;
        NSMutableArray *todo = [NSMutableArray arrayWithObject:w];
        while (todo.count) {
            UIView *v = todo.lastObject; [todo removeLastObject];
            if (v.hidden || v.alpha < 0.01) continue;
            if ([v isKindOfClass:c]) {
                CGRect r = CGRectInset([v convertRect:v.bounds toCoordinateSpace:w.screen.coordinateSpace], -4.0, -4.0);
                if (CGRectContainsPoint(r, sp)) return v;
                continue;
            }
            [todo addObjectsFromArray:v.subviews];
        }
    }
    return nil;
}
// An item is a connected drive itself: its own folder is the volume's (the mount point).
static BOOL DMFDTrashIsDriveRoot(DMFinderItem *x) {
    if (!x.dir) return NO;
    NSString *real = DMFinderReal(x.path);
    return [DMFinderDriveRoot(real) isEqualToString:real];
}
// At a drag's start: is it a drag of drives (the bin shows Eject for it)? One look at the first item decides for any other drag (cheap: a drag of
// thousands of files is not checked item by item here). Never where drives can't be ejected (DMDockTrashCanEject).
static BOOL DMFDTrashDragEjects(DMFDrag *d) {
    if (!gDockTrashOn || !d.items.count || !DMDockTrashCanEject()) return NO;
    for (DMFinderItem *x in d.items) if (!DMFDTrashIsDriveRoot(x)) return NO;
    return YES;
}
// What the drag's items are for the bin: each one a drive itself, in the Trash already, or one Finder may move (common/DockTrash.h). Worked out
// once per drag, the first time it is over the bin (the items do not change while it lasts).
static MSBDTrashDrop DMFDTrashDropFor(DMFDrag *d) {
    if (d.trashKind >= 0) return (MSBDTrashDrop)d.trashKind;
    NSUInteger n = d.items.count;
    if (!n) return MSBDTrashDropNone;
    MSBDTrashItem *it = calloc(n, sizeof *it);
    if (!it) return MSBDTrashDropRefuse;
    NSUInteger i = 0;
    for (DMFinderItem *x in d.items) {
        it[i].driveRoot = DMFDTrashIsDriveRoot(x);
        it[i].inTrash = DMFinderInOwnTrash(x.path);
        it[i].canChange = DMFinderCanChange(x.path);
        i++;
    }
    MSBDTrashDrop r = MSBDTrashDropFor(it, n, DMDockTrashCanEject());
    free(it);
    d.trashKind = r;
    return r;
}
// Every bin of the Dock (the iPad's, an external display's): -dm_setEject: on or off.
static void DMFDTrashSetEject(BOOL on) {
    Class c = NSClassFromString(@"DMTrashIconView");
    SEL s = NSSelectorFromString(@"dm_setEject:");
    if (!c || ![c instancesRespondToSelector:s]) return;
    for (UIWindow *w in DMAllWindows()) {
        if (![NSStringFromClass([w class]) isEqualToString:@"SBFloatingDockWindow"]) continue;
        NSMutableArray *todo = [NSMutableArray arrayWithObject:w];
        while (todo.count) {
            UIView *v = todo.lastObject; [todo removeLastObject];
            if ([v isKindOfClass:c]) { ((void (*)(id, SEL, BOOL))objc_msgSend)(v, s, on); continue; }
            [todo addObjectsFromArray:v.subviews];
        }
    }
}
// The drop on the bin: Move to Trash through Finder's operations (the window the drag came from, else Finder's host for drags from the desktop and
// the Downloads stack -- the policy's sheets, Undo, Put Back, the desktop's places for Put Back), or the drives ejected. Items already in the Trash
// stay where they are; nothing to do or not allowed: the picture just goes back.
static void DMFDTrashTakeDrop(DMFDrag *d) {
    MSBDTrashDrop kind = DMFDTrashDropFor(d);
    NSArray<DMFinderItem *> *items = [d.items copy];
    if (kind == MSBDTrashDropEject) {
        DMLog([NSString stringWithFormat:@"[trash] drop on the bin: %lu drive(s) to eject", (unsigned long)items.count]);
        DMFDFinish(d, YES);
        DMDockTrashEject([items valueForKey:@"path"]);
        return;
    }
    if (kind != MSBDTrashDropTrash) {
        DMLog([NSString stringWithFormat:@"[trash] drop on the bin: %@", kind == MSBDTrashDropNone ? @"nothing to do (already in the Trash)"
              : @"refused (an item Finder may not move, drives and files together, or a drive where this iPadOS can't eject)"]);
        DMFDFinish(d, NO);
        return;
    }
    NSMutableArray *paths = [NSMutableArray array];
    for (DMFinderItem *x in items) if (!DMFinderInOwnTrash(x.path)) [paths addObject:x.path];
    DMFinderWindow *host = DMFDFromFinderWindow(d) ? d.from : DMFinderOps();
    DMLog([NSString stringWithFormat:@"[trash] drop on the bin: %lu item(s) to the Trash (from %@)", (unsigned long)paths.count, DMFDFromFinderWindow(d) ? @"a Finder window" : @"the desktop or the Downloads stack"]);
    DMFDFinish(d, YES);
    [host dm_trashItems:paths];
}
// The badge on the picture over the bin: the "no" sign where the drop is refused, none otherwise (a Move to Trash is no copy: no "+").
static void DMFDTrashHover(DMFDrag *d, UIView *bin) {
    DMFDIconHover(d, bin);
    MSBDTrashDrop kind = DMFDTrashDropFor(d);
    d.checkedDest = nil;   // (the folder checks are for folders: the next folder is checked again)
    DMFDBadge(d, kind == MSBDTrashDropRefuse ? 0 : -1);
}

// From Finder's start (Finder.h DMFinderDockInit, once Finder is on): the bin's requests, and the Dock's switch.
static void DMDockTrashInit(void) {
    static int t1, t2, t3;
    if (t1) return;
    notify_register_dispatch(kMSBDTrashOpenName, &t1, dispatch_get_main_queue(), ^(int t) { DMDockTrashOpen(); });
    notify_register_dispatch(kMSBDTrashEmptyName, &t2, dispatch_get_main_queue(), ^(int t) { DMDockTrashEmpty(); });
    notify_register_dispatch("com.besiktasliseba.dockmagnification/prefsChanged", &t3, dispatch_get_main_queue(), ^(int t) { DMDockTrashApplyPref(); });
    DMDockTrashApplyPref();
}

#if DEBUG
// ---- tests (the trash_ trigger, debug builds only) ----
// trash_state: the switch, the count, the watched folders, the bin on screen
// trash_open / trash_empty: what the bin's tap / Empty Trash do
// trash_button:<title>: press the button of that title in our dialog (the question Empty Trash asks, an eject's answer)
// trash_drag:<from>|<arg>|<steps>|<drop>: a whole Finder drag ending on the bin, by Finder's own code (no injected touches: nothing on the Home
//   Screen is ever dragged by a test): from = desk (arg: a desktop item's name, lifted by the desktop's own code), paths (arg: paths joined by ","
//   -- the Downloads stack's way in), finder (arg: an item's name in the front Finder window); steps = moves on the way (the last ones over the
//   bin); drop = 1 drops it there, 0 lets go, hold leaves it over the bin, away leaves it held above the Dock, not over the bin (trash_release:<0|1>
//   ends it)
static void DMDockTrashTest(NSString *spec) {
    NSRange r = [spec rangeOfString:@":"];
    NSString *act = r.location == NSNotFound ? spec : [spec substringToIndex:r.location], *arg = r.location == NSNotFound ? @"" : [spec substringFromIndex:r.location + 1];
    UIView *bin = nil;
    Class bc = NSClassFromString(@"DMTrashIconView");
    for (UIWindow *w in DMAllWindows()) {
        if (![NSStringFromClass([w class]) isEqualToString:@"SBFloatingDockWindow"] || w.hidden) continue;
        NSMutableArray *todo = [NSMutableArray arrayWithObject:w];
        while (todo.count && !bin) { UIView *v = todo.lastObject; [todo removeLastObject]; if (bc && [v isKindOfClass:bc] && !v.hidden) bin = v; else [todo addObjectsFromArray:v.subviews]; }
        if (bin) break;
    }
    CGRect bf = bin ? [bin convertRect:bin.bounds toCoordinateSpace:bin.window.screen.coordinateSpace] : CGRectNull;
    CGPoint bc0 = CGPointMake(CGRectGetMidX(bf), CGRectGetMidY(bf));
    if ([act isEqualToString:@"state"]) {
        DMLog([NSString stringWithFormat:@"[trash] test state: on %d (Finder %d, switch %d), count now %lu, folders %@, watched %@, bin %@, drive eject %d", gDockTrashOn, gFinderOn, DMDockTrashPrefOn(),
               (unsigned long)DMDockTrashCountNow(), DMDockTrashFolders(), gDockTrashWatch.allKeys, bin ? NSStringFromCGRect(bf) : @"none", DMDockTrashCanEject()]);
        return;
    }
    if ([act isEqualToString:@"open"]) { DMDockTrashOpen(); return; }
    if ([act isEqualToString:@"empty"]) { DMDockTrashEmpty(); return; }
    if ([act isEqualToString:@"at"]) { NSArray *q = [arg componentsSeparatedByString:@","]; CGPoint p = q.count == 2 ? CGPointMake([q[0] doubleValue], [q[1] doubleValue]) : bc0;
        DMLog([NSString stringWithFormat:@"[trash] test at %@: the bin %@", NSStringFromCGPoint(p), DMFDTrashIconAt(p) ? @"is there" : @"is not there"]); return; }
    if ([act isEqualToString:@"button"]) {
        UIView *o = gOverlay; NSMutableArray *todo = o ? [NSMutableArray arrayWithObject:o] : [NSMutableArray array]; UIButton *hit = nil;
        while (todo.count && !hit) { UIView *v = todo.lastObject; [todo removeLastObject]; if ([v isKindOfClass:[UIButton class]] && [[(UIButton *)v titleForState:UIControlStateNormal] isEqualToString:arg]) hit = (UIButton *)v; else [todo addObjectsFromArray:v.subviews]; }
        NSMutableArray *labels = [NSMutableArray array];
        if (o) { NSMutableArray *t2 = [NSMutableArray arrayWithObject:o]; while (t2.count) { UIView *v = t2.lastObject; [t2 removeLastObject]; if ([v isKindOfClass:[UILabel class]] && ((UILabel *)v).text.length) [labels addObject:((UILabel *)v).text]; [t2 addObjectsFromArray:v.subviews]; } }
        DMLog([NSString stringWithFormat:@"[trash] test button \"%@\": %@ (dialog texts: %@)", arg, hit ? @"pressed" : @"not found", [labels componentsJoinedByString:@" / "]]);
        [hit sendActionsForControlEvents:UIControlEventTouchUpInside];
        return;
    }
    if ([act isEqualToString:@"release"]) { DMFinderDragEnd(bc0, [arg isEqualToString:@"1"], NO); return; }
    if (![act isEqualToString:@"drag"]) { DMLog([NSString stringWithFormat:@"[trash] test: unknown %@", spec]); return; }
    NSArray *q = [arg componentsSeparatedByString:@"|"];
    if (q.count < 4 || !bin) { DMLog([NSString stringWithFormat:@"[trash] test drag: %@", bin ? @"want <from>|<arg>|<steps>|<drop>" : @"no bin on screen"]); return; }
    NSString *from = q[0], *what = q[1], *dropMode = q[3]; int steps = MAX(1, [q[2] intValue]);
    CGPoint start = CGPointZero;
    if ([from isEqualToString:@"desk"]) {
        DMDesktopItemView *v = nil;
        NSMutableArray *todo = gDesktop ? [NSMutableArray arrayWithObject:gDesktop] : [NSMutableArray array];
        while (todo.count && !v) { UIView *x = todo.lastObject; [todo removeLastObject]; if ([x isKindOfClass:[DMDesktopItemView class]] && [((DMDesktopItemView *)x).item.name isEqualToString:what]) v = (DMDesktopItemView *)x; else [todo addObjectsFromArray:x.subviews]; }
        if (!v) { DMLog([NSString stringWithFormat:@"[trash] test drag: no desktop item %@", what]); return; }
        start = [v convertPoint:CGPointMake(CGRectGetMidX(v.bounds), CGRectGetMidY(v.bounds)) toCoordinateSpace:v.window.screen.coordinateSpace];
        ((void (*)(id, SEL, id))objc_msgSend)(gDesktop, NSSelectorFromString(@"dm_select:"), @[v.item.path]);   // (the desktop's own selection and lift)
        ((void (*)(id, SEL, CGPoint, id, BOOL))objc_msgSend)(gDesktop, NSSelectorFromString(@"dm_liftAt:held:option:"), start, v, NO);
    } else if ([from isEqualToString:@"paths"]) {
        start = CGPointMake(bc0.x - 300.0, bc0.y - 400.0);
        if (!MSBDFinderDragBeginPaths([what componentsSeparatedByString:@","], start, CGRectZero)) { DMLog(@"[trash] test drag: Finder did not take the paths"); return; }
    } else if ([from isEqualToString:@"finder"]) {
        DMFinderWindow *f = DMFinderFront(); DMFinderItem *it = nil;
        for (DMFinderItem *x in DMFinderList(f.path, NO, NULL)) if ([x.name isEqualToString:what]) it = x;
        if (!f || !it) { DMLog([NSString stringWithFormat:@"[trash] test drag: no front Finder window with %@", what]); return; }
        start = [f convertPoint:CGPointMake(CGRectGetMidX(f.bounds), CGRectGetMidY(f.bounds)) toCoordinateSpace:f.window.screen.coordinateSpace];
        DMFinderDragBegin(f, @[it], start);
    } else if ([from isEqualToString:@"drive"]) {   // (a drive, as the sidebar's drag starts it: the front window's sidebar)
        DMFinderWindow *f = DMFinderFront(); DMFinderItem *it = DMFinderItemFor(what);
        if (!f || !it) { DMLog(@"[trash] test drag: no front Finder window or no such drive folder"); return; }
        start = [f convertPoint:CGPointMake(40.0, CGRectGetMidY(f.bounds)) toCoordinateSpace:f.window.screen.coordinateSpace];
        DMFinderDragBegin(f, @[it], start);
    } else { DMLog([NSString stringWithFormat:@"[trash] test drag: unknown source %@", from]); return; }
    DMLog([NSString stringWithFormat:@"[trash] test drag from %@ (%@): %d moves to the bin at %@, then %@", from, what, steps, NSStringFromCGPoint(bc0), dropMode]);
    __block int k = 0;
    __block void (^step)(void);
    void (^s)(void) = ^{
        k++;
        CGFloat t = MIN(1.0, (CGFloat)k / steps);
        CGPoint end = [dropMode isEqualToString:@"away"] ? CGPointMake(bc0.x - 260.0, bc0.y - 420.0) : bc0;
        CGPoint p = CGPointMake(start.x + (end.x - start.x) * t, start.y + (end.y - start.y) * t);
        DMFinderDragMove(p, NO);
        if (k < steps + 2) { void (^n)(void) = step; dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), n); return; }
        step = nil;
        DMFDrag *d = gFD;
        DMLog([NSString stringWithFormat:@"[trash] test drag over the bin: kind %ld, eject shown %d, badge %@", (long)(d ? DMFDTrashDropFor(d) : -9), d.ejectShown, d.badge.hidden ? @"none" : @"shown"]);
        if ([dropMode isEqualToString:@"hold"] || [dropMode isEqualToString:@"away"]) return;
        if ([from isEqualToString:@"desk"]) { DMFinderDragEnd(bc0, [dropMode isEqualToString:@"1"], NO); ((void (*)(id, SEL))objc_msgSend)(gDesktop, NSSelectorFromString(@"dm_dragEnded")); }
        else DMFinderDragEnd(bc0, [dropMode isEqualToString:@"1"], NO);
    };
    step = s;
    s();
}
#endif
