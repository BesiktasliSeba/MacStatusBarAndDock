// DriveEject.h -- Finder's side of a connected drive's eject (1.7.3), included by DockTrash.h (after Finder.h). Every way to eject comes here, to
// DMDriveEject: the Dock's Trash (drives dropped on it, DockTrash.h), the Eject button next to each drive in Finder's sidebar (as on a Mac), File >
// Eject and Command-E (the selected drives, else the drive the front window shows), and the Eject row of a drive's menu (its sidebar row held or
// right-clicked, its folder's item in a list). The eject itself is the root helper's (common/DriveEject.h): asked, never spawned from SpringBoard --
// iPadOS 18 refuses that spawn (EPERM). What comes back is said in a Mac's words; an eject that works just takes the drive out of the sidebar.
#import "../common/DriveEject.h"

// Whether this iPadOS can eject a drive here. 16 on: StorageKit, the Files app's own eject (looked for where dlopen finds it, in the shared cache
// or on disk -- nothing is loaded into SpringBoard for the look). 15 has no StorageKit: the helper's DiskArbitration eject (ejecthelper/DAEject.h)
// is built, but not tried on a real drive yet, so it is offered only once kDMDriveEject15Ready is set after the M1 pass with a test stick (debug
// builds: the test flag /tmp/msb-eject15 offers it now). Where it can't, nothing eject-related is offered: no Eject button, no menu row, no
// Eject bin, and a drive dropped on the bin is refused (1.7.0, KT). Decided once.
static const BOOL kDMDriveEject15Ready = NO;
static BOOL DMDriveCanEject(void) {
    static int can = -1;
    if (can < 0) {
        const char *sk = "/System/Library/PrivateFrameworks/StorageKit.framework/StorageKit", *da = "/System/Library/PrivateFrameworks/DiskArbitration.framework/DiskArbitration";
        BOOL storageKit = _dyld_shared_cache_contains_path(sk) || access(sk, F_OK) == 0;
        BOOL diskArbitration = _dyld_shared_cache_contains_path(da) || access(da, F_OK) == 0, try15 = kDMDriveEject15Ready || DMTestFlag("/tmp/msb-eject15");
        can = storageKit || (diskArbitration && try15) ? 1 : 0;
        DMLog([NSString stringWithFormat:@"[eject] drive eject %@", storageKit ? @"available (StorageKit, through MacStatusBar&Dock's helper)"
               : can ? @"available (no StorageKit: DiskArbitration, through MacStatusBar&Dock's helper -- the 15 path, NOT tried on a real drive yet)"
               : diskArbitration ? @"not offered on this iPadOS yet (no StorageKit; the DiskArbitration eject waits for its test with a real drive)"
               : @"not on this iPadOS (neither StorageKit nor DiskArbitration): drives are never ejected, no Eject offered"]);
    }
    return can == 1;
}

// ---- the drives being ejected (their sidebar row shows a spinner in place of the Eject button, as on a Mac) ----
static NSMutableSet<NSString *> *gDriveEjecting;
static BOOL DMDriveEjecting(NSString *root) { return root && [gDriveEjecting containsObject:DMFinderNorm(root)]; }
static void DMDriveEjectingChanged(void) {
    for (DMNativeWindow *w in [gNativeWindows copy]) if ([w isKindOfClass:[DMFinderWindow class]] && ![w isKindOfClass:[DMFinderOpsHost class]]) [(DMFinderWindow *)w dm_reloadSidebar];
}

// ---- asking the root helper (a queue of its own: one eject at a time, the answer waited for off the main thread) ----
static dispatch_queue_t DMDriveEjectQueue(void) {
    static dispatch_queue_t q; static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("msbd.finder.eject", DISPATCH_QUEUE_SERIAL); });
    return q;
}
// The answer to our request: only root's own file in root's folder (lstat: a regular file of uid 0), and only with our request's id.
static NSString *DMDriveEjectReadAnswer(NSString *rid) {
    struct stat st;
    if (lstat(kMSBDEjectAnswerFile, &st) != 0 || !S_ISREG(st.st_mode) || st.st_uid != 0 || st.st_size > 4096) return nil;
    return MSBDEjectAnswerLine([NSData dataWithContentsOfFile:@kMSBDEjectAnswerFile], rid);
}
static NSString *DMDriveEjectAsk(NSString *root) {
    if (!MSBDEjectHelperRunning()) return kMSBDEjectNoHelperLine;   // (said at once: no request is left behind for a helper that isn't there)
    NSString *rid = MSBDEjectNewRequestID();
    __block NSString *answer = nil;
    dispatch_semaphore_t got = dispatch_semaphore_create(0);
    dispatch_queue_t q = dispatch_queue_create("msbd.finder.eject.answer", DISPATCH_QUEUE_SERIAL);
    int token = 0;
    notify_register_dispatch(kMSBDEjectAnswerName, &token, q, ^(int t) {   // (before the request: its answer can't be missed)
        if (answer) return;
        NSString *line = DMDriveEjectReadAnswer(rid);
        if (line) { answer = line; dispatch_semaphore_signal(got); }
    });
    CFStringRef key = CFSTR(kMSBDEjectRequestKey), dom = CFSTR(kMSBDEjectDomain);
    NSDictionary *req = @{ @"id": rid, @"volume": root, @"at": @([[NSDate date] timeIntervalSince1970]) };
    CFPreferencesSetValue(key, (__bridge CFDictionaryRef)req, dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    notify_post(kMSBDEjectRequestName);
    // (the post says "look"; the file itself is looked at every half second too -- a post that never came, or a registration that failed, costs
    //  half a second, not the whole wait)
    NSString *polled = nil;
    for (CFAbsoluteTime until = CFAbsoluteTimeGetCurrent() + kMSBDEjectWait; !polled && CFAbsoluteTimeGetCurrent() < until; ) {
        if (dispatch_semaphore_wait(got, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC))) == 0) break;
        polled = DMDriveEjectReadAnswer(rid);
    }
    if (token) notify_cancel(token);
    __block NSString *line = nil;
    dispatch_sync(q, ^{ line = answer; });   // (the answer's block has run, or never will now)
    if (line || polled) return line ?: polled;
    // no answer in time: our request is taken back while the helper has not read it (a helper starting later never acts on it; it is too old for
    // it by then anyway, common/DriveEject.h)
    CFPreferencesSynchronize(dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPropertyListRef v = CFPreferencesCopyValue(key, dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (v && CFGetTypeID(v) == CFDictionaryGetTypeID() && [((__bridge NSDictionary *)v)[@"id"] isEqual:rid]) {
        CFPreferencesSetValue(key, NULL, dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesSynchronize(dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    }
    if (v) CFRelease(v);
    return kMSBDEjectNoAnswerLine;
}
static void DMDriveEjectAnswered(NSString *root, NSString *name, NSString *line) {
    [gDriveEjecting removeObject:root];
    DMDriveEjectingChanged();
    DMLog([NSString stringWithFormat:@"[eject] %@: \"%@\"", name, line]);
    if ([line hasPrefix:@"ok"]) { DMFinderDrivesForget(); DMFinderDrivesCheck(@"ejected"); return; }   // (the sidebar and the windows follow at once)
    NSString *title = nil, *message = nil;
    if (MSBDEjectMessage(line, name, &title, &message)) DMFinderLooseSheet(title, message, @"OK", NO, nil, nil);
}
// The eject of one drive: root = its volume folder (Finder's spelling), name = what Finder calls it. Main thread.
static void DMDriveEject(NSString *root, NSString *name) {
    if (!gFinderOn || !DMDriveCanEject() || !root.length || DMGARefuses(@"Eject")) return;
    root = DMFinderNorm(root);
    if (!gDriveEjecting) gDriveEjecting = [NSMutableSet set];
    if ([gDriveEjecting containsObject:root]) return;   // (under way already: a second click does nothing, as on a Mac)
    DM_FEATURE_MARK("finder-drive-eject");
#if DEBUG
    if (DMTestFlag("/tmp/msb-feject-ok")) { DMLog([NSString stringWithFormat:@"[eject] (test) %@ would be ejected now -- the helper not asked", name]); return; }
    NSString *fake = [[NSString stringWithContentsOfFile:@"/tmp/msb-feject-answer" encoding:NSUTF8StringEncoding error:nil] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (fake.length) {   // (tests: the helper's answer as given, after a second -- the spinner and the dialog without a drive or the helper)
        [gDriveEjecting addObject:root]; DMDriveEjectingChanged();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ DMDriveEjectAnswered(root, name, fake); });
        return;
    }
#endif
    [gDriveEjecting addObject:root];
    DMDriveEjectingChanged();
    DMLog([NSString stringWithFormat:@"[eject] %@ (%@): asking MacStatusBar&Dock's helper", name, root]);
    dispatch_async(DMDriveEjectQueue(), ^{
        NSString *line = DMDriveEjectAsk(root);
        dispatch_async(dispatch_get_main_queue(), ^{ DMDriveEjectAnswered(root, name, line); });
    });
}

// ---- File > Eject and Command-E ----
// What they eject: the selected items that are connected drives themselves (their volume folders), else the drive the window's folder is on.
static NSArray<NSDictionary *> *DMDriveEjectTargets(DMFinderWindow *f) {
    if (!f || !DMDriveCanEject()) return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (DMFinderItem *x in [f dm_selectedItems]) {
        NSDictionary *d = x.dir ? DMFinderDriveInfo(DMFinderReal(x.path)) : nil;
        if (d && ![out containsObject:d]) [out addObject:d];
    }
    if (out.count) return out;
    NSString *root = f.path.length ? DMFinderDriveRoot(DMFinderReal(f.path)) : nil;
    NSDictionary *d = root ? DMFinderDriveInfo(root) : nil;
    return d ? @[d] : @[];
}
static NSString *DMDriveEjectTitle(NSArray<NSDictionary *> *targets) { return targets.count == 1 ? [NSString stringWithFormat:@"Eject “%@”", targets[0][@"t"]] : @"Eject"; }
static void DMDriveEjectFromWindow(DMFinderWindow *f) {
    NSArray<NSDictionary *> *targets = DMDriveEjectTargets(f);
    if (!targets.count) { DMLog(@"[eject] File > Eject: no drive selected or shown"); return; }
    for (NSDictionary *d in targets) if (!DMDriveEjecting(d[@"p"])) DMDriveEject(d[@"p"], d[@"t"]);
}
// File > Eject (Command-E), after Move to Trash as on a Mac (StatusBar.x's File menu: before its last separator): "Eject “NAME”" for one drive,
// greyed when there is none to eject; not there at all where this iPadOS can't eject (15 until its eject is tried: nothing eject-related shown).
static NSArray *DMDriveEjectMenuWith(NSArray *items, DMFinderWindow *f) {
    if (!DMDriveCanEject()) return items;
    NSArray<NSDictionary *> *targets = DMDriveEjectTargets(f);
    DMRow *r = [[DMRow alloc] initWithTitle:DMDriveEjectTitle(targets) enabled:targets.count > 0 handler:DMCloseThen(^{ DMFinderWindow *w = DMFinderFront(); if (w) DMDriveEjectFromWindow(w); })];
    r.hint = @"⌘E";
    NSUInteger sep = [items indexOfObjectWithOptions:NSEnumerationReverse passingTest:^BOOL(id x, NSUInteger i, BOOL *stop) { return x == [NSNull null]; }];
    NSMutableArray *m = [items mutableCopy];
    [m insertObject:r atIndex:sep == NSNotFound ? m.count : sep];
    return m;
}
