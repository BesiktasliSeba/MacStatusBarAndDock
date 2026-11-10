// ICleanerPanel.h -- iCleaner in Finder (1.8.5 item 1): Finder's side. A sidebar row "iCleaner" under Locations, only while the official iCleaner
// Pro is installed (com.exile90.icleanerpro, its program where its package puts it), opens a panel of ours in a Mac's style: Clean, Clean and
// Respring, Respring, Close; while iCleaner works, a spinner; then the space freed. The clean itself is the root helper's run of iCleaner's own
// command line (common/ICleaner.h): asked, never spawned from SpringBoard. The respring is ours (Respring in the Apple menu, DMRespringChecked).
// Nothing of iCleaner's is drawn or changed here: no artwork of its, no setting of its; what a clean removes is the user's choice in iCleaner.
#import "../common/ICleaner.h"

// The official iCleaner Pro is installed: its package (dpkg's status, read once per change) and its program.
static BOOL DMICleanAvailable(void) {
    struct stat st;
    if (lstat(kMSBDICleanBinary, &st) != 0 || !S_ISREG(st.st_mode)) return NO;
    NSArray<NSString *> *w = [MSBDPackageField(kMSBDICleanPackage, @"Status") componentsSeparatedByString:@" "];
    return w.count == 3 && [@[@"install", @"hold"] containsObject:w[0]] && [w[1] isEqualToString:@"ok"] && [w[2] isEqualToString:@"installed"];
}
// Finder's sidebar for a window: the places (DMFinderSidebar, which the Go menu lists too), and iCleaner's row at the end of Locations. A row of
// "tool" kind has no path: it is no place to go, drop onto or list in Go.
static NSArray<NSDictionary *> *DMFinderSidebarForWindow(void) {
    NSArray<NSDictionary *> *s = DMFinderSidebar();
    if (!DMICleanAvailable() || !s.count) return s;
    NSMutableArray *m = [s mutableCopy];
    NSMutableDictionary *last = [m.lastObject mutableCopy];
    last[@"rows"] = [last[@"rows"] arrayByAddingObject:@{@"t": @"iCleaner", @"i": @"sparkles", @"tool": @"iclean"}];
    m[m.count - 1] = last;
    return m;
}

static BOOL gICleanBusy = NO;
static dispatch_queue_t DMICleanQueue(void) {
    static dispatch_queue_t q; static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("msbd.finder.iclean", DISPATCH_QUEUE_SERIAL); });
    return q;
}
static NSString *DMICleanReadAnswer(NSString *rid) {   // (only root's own file in root's folder, only the answer with our request's id)
    struct stat st;
    if (lstat(kMSBDICleanAnswerFile, &st) != 0 || !S_ISREG(st.st_mode) || st.st_uid != 0 || st.st_size > 4096) return nil;
    return MSBDEjectAnswerLine([NSData dataWithContentsOfFile:@kMSBDICleanAnswerFile], rid);
}
// Asks the root helper for a clean and waits for its answer (a background queue): the answer line, or Finder's own error line.
static NSString *DMICleanAsk(void) {
    if (!MSBDEjectHelperRunning()) return kMSBDICleanNoHelperLine;
    NSString *rid = MSBDEjectNewRequestID();
    __block NSString *answer = nil;
    dispatch_semaphore_t got = dispatch_semaphore_create(0);
    dispatch_queue_t q = dispatch_queue_create("msbd.finder.iclean.answer", DISPATCH_QUEUE_SERIAL);
    int token = 0;
    notify_register_dispatch(kMSBDICleanAnswerName, &token, q, ^(int t) {   // (before the request: its answer can't be missed)
        if (answer) return;
        NSString *line = DMICleanReadAnswer(rid);
        if (line) { answer = line; dispatch_semaphore_signal(got); }
    });
    CFStringRef key = CFSTR(kMSBDICleanRequestKey), dom = CFSTR(kMSBDEjectDomain);
    NSDictionary *req = @{ @"id": rid, @"action": @"clean", @"at": @([[NSDate date] timeIntervalSince1970]) };
    CFPreferencesSetValue(key, (__bridge CFDictionaryRef)req, dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    notify_post(kMSBDICleanRequestName);
    NSString *polled = nil;   // (the answer file is looked at every second too: a lost post costs a second, not the whole wait)
    for (CFAbsoluteTime until = CFAbsoluteTimeGetCurrent() + kMSBDICleanWait; !polled && CFAbsoluteTimeGetCurrent() < until; ) {
        if (dispatch_semaphore_wait(got, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC))) == 0) break;
        polled = DMICleanReadAnswer(rid);
    }
    if (token) notify_cancel(token);
    __block NSString *line = nil;
    dispatch_sync(q, ^{ line = answer; });
    if (line || polled) return line ?: polled;
    // (no answer in time: our request is taken back if the helper never read it)
    CFPreferencesSynchronize(dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPropertyListRef v = CFPreferencesCopyValue(key, dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (v && CFGetTypeID(v) == CFDictionaryGetTypeID() && [((__bridge NSDictionary *)v)[@"id"] isEqual:rid]) {
        CFPreferencesSetValue(key, NULL, dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesSynchronize(dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    }
    if (v) CFRelease(v);
    return kMSBDICleanNoAnswerLine;
}

// ---- the panel --------------------------------------------------------------------------------------------------------------------------------
// One dialog of ours over everything (as Finder's questions outside a window): a symbol of ours, the title, a line on what it does, then the
// buttons stacked as in a Mac's alert. Its states: ready (Clean, Clean and Respring, Respring, Close), working (a spinner, nothing to press: a
// clean isn't stopped halfway), done (the result; Respring when iCleaner says one is needed, and Done) or failed (iCleaner's own words; OK).
static void DMICleanShowPanel(int state, NSString *text, BOOL offerRespring);
static void DMICleanRun(BOOL thenRespring) {
    if (gICleanBusy) return;
    gICleanBusy = YES;
    DM_FEATURE_MARK("finder-icleaner-clean");
    DMLog([NSString stringWithFormat:@"[iclean] clean%@: asking MacStatusBar&Dock's helper", thenRespring ? @" and respring" : @""]);
    DMICleanShowPanel(1, nil, NO);
    dispatch_async(DMICleanQueue(), ^{
        NSString *line = DMICleanAsk();
        dispatch_async(dispatch_get_main_queue(), ^{
            gICleanBusy = NO;
            DMLog([NSString stringWithFormat:@"[iclean] answer: \"%@\"", line]);
            NSString *freed = nil, *err = nil; long long deleted = -1; BOOL respring = NO;
            if (!MSBDICleanParseAnswer(line, &freed, &deleted, &respring, &err)) {
                // (Finder stopped waiting but iCleaner goes on, never stopped halfway: no failure, the plain panel with Done)
                DMICleanShowPanel([line isEqualToString:kMSBDICleanNoAnswerLine] ? 2 : 3, err, NO);
                return;
            }
            if (thenRespring) { DMCloseOverlay(); DMRespringChecked(); return; }
            DMICleanShowPanel(2, MSBDICleanResultText(freed, deleted), respring);
        });
    });
}
static void DMICleanShowPanel(int state, NSString *text, BOOL offerRespring) {
    UIView *host = DMMenuHost();
    if (!host) { DMLog(@"[iclean] no place for the panel"); return; }
    if (gOverlay) DMCloseOverlay();
    UIControl *o = DMMakeOverlay(host, 0.30);
    const CGFloat W = 300.0, pad = 20.0, buttonH = 44.0;
    UIVisualEffectView *box = DMMakeBlur(14.0);
    CGFloat y = 20.0;
    UIImageView *sym = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:state == 3 ? @"exclamationmark.triangle.fill" : @"sparkles" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:30.0 weight:UIImageSymbolWeightRegular]]];
    sym.tintColor = state == 3 ? [UIColor systemOrangeColor] : [UIColor systemBlueColor];
    sym.contentMode = UIViewContentModeCenter;
    sym.frame = CGRectMake((W - 44.0) / 2.0, y, 44.0, 44.0); [box.contentView addSubview:sym]; y += 44.0 + 10.0;
    UILabel *t = [UILabel new];
    t.text = state == 3 ? @"iCleaner Couldn’t Clean" : @"iCleaner"; t.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold]; t.textColor = [UIColor labelColor];
    t.textAlignment = NSTextAlignmentCenter; t.numberOfLines = 0; t.accessibilityTraits = UIAccessibilityTraitHeader;
    CGSize ts = [t sizeThatFits:CGSizeMake(W - 2 * pad, CGFLOAT_MAX)];
    t.frame = CGRectMake(pad, y, W - 2 * pad, ts.height); [box.contentView addSubview:t]; y += ts.height + 6.0;
    NSString *msg = state == 0 ? @"Removes what you chose in iCleaner’s settings, such as caches, temporary files and logs, and packages nothing needs if you turned that on in iCleaner."
                  : state == 1 ? @"Cleaning… This can take a minute."
                  : state == 2 ? (offerRespring ? [text stringByAppendingString:@" A respring is needed for some of the changes."] : text)
                  : (text.length ? text : @"Try again in a moment.");
    UILabel *m = [UILabel new];
    m.text = msg; m.font = [UIFont systemFontOfSize:13.0]; m.textColor = [UIColor secondaryLabelColor]; m.textAlignment = NSTextAlignmentCenter; m.numberOfLines = 0;
    CGSize ms = [m sizeThatFits:CGSizeMake(W - 2 * pad, CGFLOAT_MAX)];
    m.frame = CGRectMake(pad, y, W - 2 * pad, ms.height); [box.contentView addSubview:m]; y += ms.height + 16.0;
    NSMutableArray<NSArray *> *buttons = [NSMutableArray array];   // (title, bold, action)
    void (^close)(void) = ^{ DMCloseOverlay(); };
    if (state == 0) {
        [buttons addObject:@[@"Clean", @YES, ^{ DMICleanRun(NO); }]];
        [buttons addObject:@[@"Clean and Respring", @NO, ^{ DMICleanRun(YES); }]];
        [buttons addObject:@[@"Respring", @NO, ^{ DMCloseOverlay(); DMRespringChecked(); }]];
        [buttons addObject:@[@"Close", @NO, close]];
    } else if (state == 1) {
        UIActivityIndicatorView *spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        spin.center = CGPointMake(W / 2.0, y + 12.0); [spin startAnimating]; [box.contentView addSubview:spin]; y += 24.0 + 16.0;
    } else if (state == 2) {
        if (offerRespring) [buttons addObject:@[@"Respring", @YES, ^{ DMCloseOverlay(); DMRespringChecked(); }]];
        [buttons addObject:@[@"Done", @(!offerRespring), close]];
    } else [buttons addObject:@[@"OK", @YES, close]];
    for (NSArray *b in buttons) {
        UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, y, W, 0.5)]; line.backgroundColor = [UIColor separatorColor]; [box.contentView addSubview:line];
        [box.contentView addSubview:DMDialogButton(b[0], [b[1] boolValue], [UIColor systemBlueColor], CGRectMake(0, y, W, buttonH), b[2])];
        y += buttonH;
    }
    box.frame = CGRectMake(0, 0, W, y);
    box.center = CGPointMake(CGRectGetMidX(o.bounds), CGRectGetMidY(o.bounds));
    box.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    // (the escape gesture and Esc: Close in the ready state, Done / OK after; nothing while it cleans)
    if (state != 1) objc_setAssociatedObject(o, kOverlayEscapeKey, close, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [o addSubview:box];
    box.alpha = 0.0;
    [UIView animateWithDuration:0.12 animations:^{ box.alpha = 1.0; }];
    DMLog([NSString stringWithFormat:@"[iclean] panel: %@", state == 0 ? @"ready" : state == 1 ? @"cleaning" : state == 2 ? [NSString stringWithFormat:@"done (%@%@)", text, offerRespring ? @", respring offered" : @""] : [NSString stringWithFormat:@"failed (%@)", text]]);
}
// The sidebar row's tap: the panel, or (while a clean runs) the spinner again.
static void DMICleanOpenPanel(void) {
    if (!DMICleanAvailable()) return;
    DMICleanShowPanel(gICleanBusy ? 1 : 0, nil, NO);
}
