// MacSwitcherSM.h -- Mac Switcher desktops with the Stage Manager engine (iPadOS 16), included into StatusBar.x after the engine's code (it uses
// its stages, title bars and checked requests). MacSwitcher.h keeps the view, the strip, the slide and the records; with Stage Manager as the
// engine its desktop functions hand over to the ones here (each such place is one line there, "DMSMEngine()").
// A desktop = one Stage Manager stage (Apple's own group of windows, research section 2): its windows are records, window -> desktop id
// (gMSWWinDesk, shared with MacSwitcher.h). Each window by its KEY (SMWindowKey.h: "<bundle>|<scene identifier>" -- two windows of one app are two
// windows, on one desktop or on two; M-2, 1.3.9); a record by app (the bundle alone: an older build's, or where windows can't be told apart, the
// engine's DMSMPerWindow off) stands for the app's windows (DMMSWSMRecordOf) until the tick records each window by its own key. The window
// lists below are @[stage, item, attributes, key] (the bundle: DMSMKeyBundle). Stage Manager swaps stages itself and keeps the left stage's apps alive as long as memory allows; an
// app iPadOS closes meanwhile stays in its stage (Apple keeps the window and its snapshot) and is launched again when the stage is asked for --
// a normal relaunch, never an empty frame.
//  - switch: the windows of the desktop are asked for together in one workspace transition (the engine's checked plan, DMSMRequestOn); an empty
//    desktop is the Home Screen (the left stage stays hidden, as Stage Manager hides it for Home);
//  - a launch (DMSMJoinDesktop) joins the CURRENT desktop's windows -- the engine used to join the most recent stage, which may be another
//    desktop's -- and an app whose window is on another desktop brings that desktop, with the slide (DMMSWSMJoin);
//  - a desktop holds as many windows as a Stage Manager stage can: one per window role SpringBoard has (DMSMWindowCap(), SMRoles.h -- 7 on 16.7.7
//    since 1.3.6, 4 before). What happens when one more window comes to a FULL desktop is decided in one place, DMMSWSMAtCap below (decided on
//    6 Oct 2026): an app opened there opens on a new desktop by itself with a short notice (DMMSWSMNotice), nothing on the full desktop changes;
//    where no new desktop can be made (the most desktops), or windows are merged by a remove, the oldest are minimized (open again from the
//    Dock); a window dragged onto a full desktop is refused;
//  - the full-screen app is one of its stage's windows (the engine's full screen lives inside the stage): it travels with its desktop;
//  - remove (x): the windows go to the left neighbour; still in their own stage until that desktop is shown, then asked for together (at most a
//    full desktop's worth, the oldest minimized);
//  - Fit to Window per desktop (its arrangement and its free windows); saved across a respring (the records in MacSwitcher.h's desktops file,
//    the stages by Stage Manager itself); Settings off = one desktop again (the windows stay where they are: the engine's own join from then on).
// Every private call goes through the engine's checked wrappers (SMEngineAPI.h) and the calls above; nothing new of Apple's is called here.

static CFTimeInterval gMSWSMQuietUntil = 0;   // (just switched: the tick does not take the stage in front for "a desktop came up by itself" yet)
static UIWindow *gMSWSMNoteWindow;            // (the notice: a window that takes no touches)
static UIView *gMSWSMNoteRoot;
// iPadOS 17+ (untested there, Enable Anyway): what the desktops did, a line of the StageManager diagnostics record for Report a Problem
// (StatusBar.x DMSM17DiagWrite; numbers only). 0 switches, 1 desktops whose windows could not be asked for (the Home Screen instead), 2 windows
// opened on a new desktop because theirs was full, 3 windows minimized at a full desktop, 4 the last switch's length in ms. (Which Home button
// handlers were hooked: the StatusBar record's msw home line, MacSwitcherButton.h gMSWDiagButton.)
static unsigned gMSWSMDiag[5];
static NSString *DMMSWSMDiagLine(void) {
    return [NSString stringWithFormat:@"desktops %lu (on %lu, up to %lu windows each): switches %u (last %u ms), refused %u, opened on a new desktop (full) %u, minimized (full) %u",
        (unsigned long)gMSWDesks.count, (unsigned long)gMSWCur + 1, (unsigned long)DMSMWindowCap(), gMSWSMDiag[0], gMSWSMDiag[4], gMSWSMDiag[1], gMSWSMDiag[2], gMSWSMDiag[3]];
}

// The window cards shown on the iPad's screen now, one per window (DMSMCardKey: two windows of one app are two cards): every card the engine has
// seen (gSMCards, DMSMChrome -- with or without our title bar: a card that is full screen from its first layout never gets one, and the view left
// the full-screen app out), shown as far as UIKit knows.
static BOOL DMMSWSMShown(UIView *v) {
    for (UIView *x = v; x; x = x.superview) if (x.hidden || x.alpha < 0.05) return NO;
    return v.window != nil;
}
static NSArray<UIView *> *DMMSWSMVisibleCards(void) {
    NSMutableArray<UIView *> *out = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (UIView *card in gSMCards.allObjects) {
        NSString *k = DMSMCardKey(card);
        if (!k.length || [seen containsObject:k] || card.window.screen != [UIScreen mainScreen] || !DMMSWSMShown(card)) continue;
        [seen addObject:k];
        [out addObject:card];
    }
    return out;
}
// The desktop a window is recorded on: its own key's record, else its app's (a record by app stands for the app's windows -- an older build's,
// or made while windows were told apart by app). nil: recorded nowhere.
static NSNumber *DMMSWSMRecordOf(NSString *k) {
    if (!k.length) return nil;
    NSNumber *d = gMSWWinDesk[k];
    if (!d && !DMSMKeyIsApp(k)) d = gMSWWinDesk[DMSMKeyBundle(k)];
    return d;
}
// (a window list entry and a key name the same window: that very window, or by app when one of the two is an app key)
static BOOL DMMSWSMSameWindow(NSString *a, NSString *b) { return DMSMKeyCovers(a, b) || DMSMKeyCovers(b, a); }
// The window cards as they are DRAWN right now (presentation layers, the whole way up): place and opacity of each. Unchanged for a few frames =
// Stage Manager has finished bringing a stage in (or taking it away for the Home Screen: then no card is left).
static NSString *DMMSWSMCardsDrawn(void) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (UIView *card in gSMCards.allObjects) {
        NSString *b = DMSMCardKey(card);
        if (!b.length || !card.window || card.window.hidden || card.window.screen != [UIScreen mainScreen]) continue;
        CALayer *pl = card.layer.presentationLayer ?: card.layer;
        BOOL hidden = NO; float a = 1.0f;
        for (UIView *x = card; x; x = x.superview) { if (x.hidden) hidden = YES; CALayer *xl = x.layer.presentationLayer ?: x.layer; a *= xl.opacity; }
        if (hidden || a < 0.01f) continue;
        CGRect f = [pl convertRect:pl.bounds toLayer:nil];
        if (!CGRectIntersectsRect(CGRectInset(f, 1.0, 1.0), card.window.layer.bounds)) continue;   // (off the screen: a leaving stage's card on its way out can't be seen)
        [parts addObject:[NSString stringWithFormat:@"%@ %.0f %.0f %.0f %.0f %.2f", b, f.origin.x, f.origin.y, f.size.width, f.size.height, a]];
    }
    [parts sortUsingSelector:@selector(compare:)];
    return [parts componentsJoinedByString:@" | "];
}

// A desktop's windows now: every window (not minimized) of a stage on the iPad's own screen that is recorded on that desktop (DMMSWSMRecordOf),
// newest first, each @[stage, item, attributes, key]. Usually all in one stage; after a remove the ones from the removed desktop are in a stage of
// their own until the desktop is shown.
static NSArray<NSArray *> *DMMSWSMDeskWindows(NSInteger did) {
    NSMutableArray<NSArray *> *out = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id al in DMSMRecentStages()) {
        if (!DMSMIsMainIdentity(DMSMStageDisplayIdentity(al))) continue;
        NSDictionary *m = DMSMStageItemsMap(al);
        for (id it in m) {
            NSString *k = DMSMItemKey(it);
            if (!k.length || [seen containsObject:k] || DMSMIsMinimized(k) || DMMSWSMRecordOf(k).integerValue != did) continue;
            [seen addObject:k];
            [out addObject:@[al, it, m[it], k]];
        }
    }
    [out sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
        long long ta = DMSMAttrTimeOr(a[2], 0), tb = DMSMAttrTimeOr(b[2], 0);
        return ta > tb ? NSOrderedAscending : (ta < tb ? NSOrderedDescending : NSOrderedSame);
    }];
    return out;
}

// The plan that shows windows together as one stage (DMSMRequestOn / DMSMWritePlan): at most a full desktop (DMSMWindowCap(), one window per
// window role). wins: newest first (DMMSWSMDeskWindows); extra: @[entity, attributes, key] of a window that joins them in front (a launch), or
// nil. Each window by its own scene (DMSMEntityForStageItem: two windows of one app named as one scene twice is the plan DMSMPlanValid refuses). The windows beyond the cap, oldest, go to *leftOut. Roles: a window keeps its own when it is one a window may take (1 primary, 2 side, 5-9
// additional sides on 16.7.7, SMRoles.h) and still free; the others get the first free one; role 1 is never left empty. nil when a part is missing
// (then nothing is asked). (Careful with windows of the stage ON SCREEN: one moved to another role here must not have its old role emptied by the
// same whole-stage request -- Stage Manager drops the window with the emptied role, 4 Oct; a window that leaves the stage on screen goes by Stage
// Manager's own Minimize instead, DMMSWSMMoveFinish.)
static NSArray<NSArray *> *DMMSWSMPlan(NSArray<NSArray *> *wins, NSArray *extra, NSMutableArray<NSString *> *leftOut) {
    NSUInteger cap = (NSUInteger)DMSMWindowCap(), room = extra ? cap - 1 : cap;
    NSArray *kept = wins.count > room ? [wins subarrayWithRange:NSMakeRange(0, room)] : wins;
    for (NSUInteger i = room; i < wins.count; i++) [leftOut addObject:wins[i][3]];
    NSSet<NSNumber *> *allowed = DMSMNewWindowRoles();
    NSMutableSet<NSNumber *> *used = [NSMutableSet set];
    NSMutableArray<NSMutableArray *> *rows = [NSMutableArray array];
    for (NSArray *w in kept) {
        long long r = 0;
        if (!DMSMStageRoleOfItem(w[0], w[1], &r) || ![allowed containsObject:@(r)] || [used containsObject:@(r)]) r = 0;
        if (r) [used addObject:@(r)];
        id e = DMSMEntityForStageItem(w[0], w[1]);   // (that window's own scene, in its own stage)
        if (!e) return nil;
        [rows addObject:[@[e, @(r), w[2]] mutableCopy]];
    }
    if (extra) [rows addObject:[@[extra[0], @0, extra[1]] mutableCopy]];
    BOOL anyFree = NO;
    for (NSMutableArray *row in rows) if ([row[1] longLongValue] == 0) anyFree = YES;
    if (!anyFree && rows.count && ![used containsObject:@1]) { [used removeObject:rows[0][1]]; rows[0][1] = @1; [used addObject:@1]; }   // (a stage needs its primary)
    for (NSMutableArray *row in rows) {
        if ([row[1] longLongValue] != 0) continue;
        long f = (long)DMSMFirstFreeRole(used);   // (the first free window role of SpringBoard's own role table, SMRoles.h -- added to used)
        if (!f) return nil;
        row[1] = @(f);
    }
    NSMutableArray *out = [NSMutableArray array];
    for (NSMutableArray *row in rows) [out addObject:[row copy]];
    return out;
}

// ---- a FULL desktop: as many windows as a stage holds (DMSMWindowCap(): one per window role SpringBoard has -- 7 on 16.7.7) ----
// What happens when one more window comes to a desktop that is already full (decided on 6 Oct 2026: it opens on a new desktop, with a short
// notice). Every path that can meet the cap asks here, so the answer lives in this one function. (1.3.6 moved the cap from four to SpringBoard's
// own seven; SpringBoard's own transitions get the launches' answer -- before, they left the oldest window out silently, and of the wrong desktop
// when the most recent stage was another desktop's):
//  - DMMSWSMCapOpen: an app or window opened onto the full desktop -- a launch (Home Screen, Dock, Spotlight, a link, our menus: DMMSWSMJoin) or
//    SpringBoard's own transition (the App Switcher's card, Cmd-Tab, Stage Manager's drag from the Dock: DMMSWSMAskedFull). Answers NewDesktop
//    (it opens on a new desktop by itself, which comes; a short notice says why; nothing on the full desktop changes) or MinimizeOldest (it
//    joins; the desktop's oldest window is minimized -- it opens again from the Dock -- and a notice says so). Today: a new desktop, the oldest
//    minimized only at the most desktops (kMSWMaxDesks) -- and, with one desktop, for a window that was minimized from it (it comes back there).
//  - DMMSWSMCapMerge: a removed desktop's windows shown with its neighbour's, more than one desktop holds: MinimizeOldest only (today).
//  - DMMSWSMCapDrop: a window dragged onto a full desktop in the view: Refuse (today: the thumbnail shakes and goes back) or MinimizeOldest (it
//    goes there; that desktop's oldest window is minimized, said by a notice).
// minimizedOne: the window was minimized and there is one desktop (DMMSWSMCapOpen only).
typedef NS_ENUM(int, DMMSWSMCapCase) { DMMSWSMCapOpen, DMMSWSMCapMerge, DMMSWSMCapDrop };
typedef NS_ENUM(int, DMMSWSMCapWay) { DMMSWSMCapNewDesktop, DMMSWSMCapMinimizeOldest, DMMSWSMCapRefuse };
static DMMSWSMCapWay DMMSWSMAtCap(DMMSWSMCapCase what, BOOL minimizedOne) {
    switch (what) {
        case DMMSWSMCapOpen:
            if (minimizedOne) return DMMSWSMCapMinimizeOldest;
            return gMSWDesks.count < kMSWMaxDesks ? DMMSWSMCapNewDesktop : DMMSWSMCapMinimizeOldest;
        case DMMSWSMCapMerge: return DMMSWSMCapMinimizeOldest;
        case DMMSWSMCapDrop: return DMMSWSMCapRefuse;
    }
    return DMMSWSMCapMinimizeOldest;
}
// (the desktop's name and the cap, for the notices: "Desktop 1 holds up to 7 windows")
static NSString *DMMSWSMHoldsUpTo(NSString *desk) {
    return [NSString stringWithFormat:@"%@ holds up to %lu windows", desk ?: @"A desktop", (unsigned long)DMSMWindowCap()];
}

// ---- the notice (a window opened on a new desktop because its desktop was full, or the oldest minimized) ----
// A small dark label under the menu bar for three seconds, in a window of its own that takes no touches (the same window class and verified
// initializer as the view's layer, DMMSWLayer), just under our menu window.
static void DMMSWSMNotice(NSString *text) {
    if (!text.length || !DMMSWSelfCheck()) return;
    @try {
        if (!gMSWSMNoteWindow) {
            UIWindow *w = ((id (*)(id, SEL, id, id))objc_msgSend)([objc_getClass("SBMainScreenActiveInterfaceOrientationWindow") alloc], NSSelectorFromString(@"initWithRole:debugName:"), @"SBFTraitsParticipantRoleRecordingIndicator", @"MacStatusBarMacSwitcherNotice");
            w.windowLevel = kMenuWindowLevel - 0.4;   // (over the Mac Switcher's view, under our menus)
            w.userInteractionEnabled = NO;            // (touches go on to what is under it)
            w.backgroundColor = [UIColor clearColor];
            gMSWSMNoteWindow = w;
            DMSnapInvalidate();
        }
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[macswitcher] notice window failed: %@", e]); return; }
    UIWindow *w = gMSWSMNoteWindow;
    [gMSWSMNoteRoot removeFromSuperview];
    w.hidden = NO;
    UIView *root = [UIView new];
    root.userInteractionEnabled = NO;
    [w addSubview:root];
    DMMSWTurnIn(w, root);
    gMSWSMNoteRoot = root;
    UILabel *l = DMMSWLabel(text, 13.0, UIFontWeightMedium);
    l.numberOfLines = 2;
    l.layer.shadowOpacity = 0;
    CGFloat maxW = MIN(520.0, root.bounds.size.width - 40.0);
    CGSize s = [l sizeThatFits:CGSizeMake(maxW - 28.0, 60.0)];
    UIVisualEffectView *pill = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterialDark]];
    pill.frame = CGRectIntegral(CGRectMake((root.bounds.size.width - MIN(maxW, s.width + 28.0)) / 2.0, 24.0 + 14.0, MIN(maxW, s.width + 28.0), s.height + 16.0));
    pill.layer.cornerRadius = 10.0; pill.layer.cornerCurve = kCACornerCurveContinuous; pill.clipsToBounds = YES;
    l.frame = CGRectInset(pill.bounds, 14.0, 8.0);
    [pill.contentView addSubview:l];
    [root addSubview:pill];
    pill.alpha = 0;
    MSBAnimate(0.2, 0, 1.0, 0, ^{ pill.alpha = 1; }, nil);
    DMLog([NSString stringWithFormat:@"[macswitcher] notice: %@", text]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (gMSWSMNoteRoot != root) return;
        MSBAnimate(0.3, 0, 1.0, 0, ^{ pill.alpha = 0; }, ^(BOOL f) {
            if (gMSWSMNoteRoot != root) return;
            [root removeFromSuperview]; gMSWSMNoteRoot = nil;
            gMSWSMNoteWindow.hidden = YES;
        });
    });
}
// Windows left out of a full desktop (DMMSWSMAtCap's MinimizeOldest): minimized (so no launch counts them as a desktop of their own) and said.
// desk: the desktop's name, or nil with one desktop. Only with the Mac Switcher on (off: the engine's own behaviour, unchanged).
static void DMMSWSMLeftOut(NSArray<NSString *> *keys, NSString *desk) {   // (keys: each window's own -- SMWindowKey.h)
    if (!gMSWOn || !keys.count) return;
    gMSWSMDiag[3] += (unsigned)keys.count;   // (iPadOS 17 diagnostics)
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *k in keys) { DMSMSetMinimized(k, YES); [names addObject:DMMSWAppName(DMSMKeyBundle(k))]; }
    NSString *who = [names componentsJoinedByString:@", "];
    DMLog([NSString stringWithFormat:@"[macswitcher] %lu windows at most on %@: %@ minimized", (unsigned long)DMSMWindowCap(), desk ?: @"the desktop", who]);
    DMMSWSMNotice([NSString stringWithFormat:@"%@: %@ %@ minimized.", DMMSWSMHoldsUpTo(desk), who, names.count == 1 ? @"was" : @"were"]);
}

// ---- the records follow what is on screen (MacSwitcher.h DMMSWApply, every tick; cheap: twice a second at most) ----
//  - a window that appears in the stage in front and is in no record joins that stage's desktop (the current one, normally);
//  - the stage in front belonging to another desktop (it came up by another way: Stage Manager's own, a respring) makes that desktop current;
//  - several desktops' windows in the stage in front (should not happen: launches are joined here) are the current desktop's from then on;
//  - a record whose window is in no stage any more (closed, quit) is forgotten.
static CFTimeInterval gMSWSMFirstTick = 0;
static void DMMSWSMArrive(NSInteger toId);
static void DMMSWSMApply(void) {
    if (!DMMSWMulti()) return;
    CFTimeInterval now = CACurrentMediaTime();
    static CFTimeInterval last = 0;
    if (!gMSWSMFirstTick) gMSWSMFirstTick = now;
    if (now - last < 0.5 || gMSWSwitching || now < gMSWSMQuietUntil) return;
    last = now;
    NSInteger cur = DMMSWCurId();
    BOOL dirty = NO;
    static NSNumber *pending; static int pendingSeen = 0;
    if (DMFrontApp() && !DMSwitcherVisible() && !DMCoverSheetShown() && !gMSWOpen) {
        NSDictionary *m = DMSMStageItemsMap(DMSMFrontStage());
        NSMutableSet<NSNumber *> *desks = [NSMutableSet set];
        NSMutableArray<NSString *> *unrecorded = [NSMutableArray array];
        for (id it in m) {
            NSString *k = DMSMItemKey(it);
            if (!k.length || DMSMIsMinimized(k)) continue;
            NSNumber *d = DMMSWSMRecordOf(k);
            if (d && [gMSWDesks containsObject:d]) [desks addObject:d]; else [unrecorded addObject:k];
        }
        NSNumber *other = desks.count == 1 && [desks.anyObject integerValue] != cur ? desks.anyObject : nil;
        if (other) {   // (seen twice in a row: not a stage passing by in a transition)
            if (![pending isEqual:other]) { pending = other; pendingSeen = 1; return; }
            if (++pendingSeen < 2) return;
            NSUInteger i = [gMSWDesks indexOfObject:other];
            DMLog([NSString stringWithFormat:@"[macswitcher] %@'s stage came up by itself: it is the current desktop", DMMSWDeskName(i)]);
            if (!gMSWFit) gMSWFit = [NSMutableDictionary dictionary];
            gMSWFit[[@(cur) stringValue]] = @{@"smslots": [gSMFitSlots copy] ?: @{}, @"smfree": [gSMFreeWindows allObjects] ?: @[]};
            gMSWCur = i; cur = other.integerValue; dirty = YES;
            DMMSWSMArrive(cur);
            [gMSWShots removeObjectForKey:other];
        }
        pending = nil;
        if (desks.count > 1) {
            for (id it in m) { NSString *k = DMSMItemKey(it); if (k.length && !DMSMIsMinimized(k) && DMMSWSMRecordOf(k).integerValue != cur) { gMSWWinDesk[k] = @(cur); dirty = YES; } }
            DMLog([NSString stringWithFormat:@"[macswitcher] windows of several desktops in the stage in front: all on %@ now", DMMSWDeskName(gMSWCur)]);
        }
        NSNumber *to = desks.count == 1 ? desks.anyObject : @(cur);
        for (NSString *k in unrecorded) {
            gMSWWinDesk[k] = to; dirty = YES;
            DMLog([NSString stringWithFormat:@"[macswitcher] %@'s window joins %@", DMSMKeyText(k), DMMSWDeskName([gMSWDesks indexOfObject:to])]);
        }
    } else pending = nil;
    // closed windows are forgotten (not in the first seconds after a respring: the stages may not be read back yet); a record by app (an older
    // build's) goes to each of the app's windows by its own key, then the app's record goes (two windows of the app can then be on two desktops)
    NSArray *recent = DMSMRecentStages();
    if (recent.count && now - gMSWSMFirstTick > 20.0) {
        NSMutableSet<NSString *> *alive = [NSMutableSet set], *aliveApps = [NSMutableSet set];
        NSMutableArray<NSString *> *windows = [NSMutableArray array];
        for (id al in recent) {
            if (!DMSMIsMainIdentity(DMSMStageDisplayIdentity(al))) continue;
            for (id it in DMSMStageItemsMap(al)) {
                NSString *k = DMSMItemKey(it);
                if (!k.length || [alive containsObject:k]) continue;
                [alive addObject:k]; [aliveApps addObject:DMSMKeyBundle(k)]; [windows addObject:k];
            }
        }
        for (NSString *k in windows) {
            if (DMSMKeyIsApp(k) || gMSWWinDesk[k] || !gMSWWinDesk[DMSMKeyBundle(k)]) continue;
            gMSWWinDesk[k] = gMSWWinDesk[DMSMKeyBundle(k)]; dirty = YES;
            DMLog([NSString stringWithFormat:@"[macswitcher] %@: recorded by its own window now (its app's record of %@)", DMSMKeyText(k), gMSWWinDesk[k]]);
        }
        for (NSString *k in gMSWWinDesk.allKeys) {
            if ([alive containsObject:k]) continue;   // (that window -- or, told apart by app, that app's window -- is there)
            BOOL app = DMSMKeyIsApp(k);
            BOOL taken = app && [aliveApps containsObject:k];   // (an app's record: its windows have their own records now)
            // (a window's record while windows are told apart by app this time -- DMSMPerWindow off: the window keys are their apps' -- goes to its
            //  app's record when the app is there, instead of being forgotten with its desktop)
            BOOL folded = !app && !DMSMPerWindow() && [aliveApps containsObject:DMSMKeyBundle(k)];
            if (folded && !gMSWWinDesk[DMSMKeyBundle(k)]) { gMSWWinDesk[DMSMKeyBundle(k)] = gMSWWinDesk[k]; if (gMSWWinFrame[k]) gMSWWinFrame[DMSMKeyBundle(k)] = gMSWWinFrame[k]; }
            if (!taken && !folded) DMLog([NSString stringWithFormat:@"[macswitcher] %@'s window is in no stage any more (closed): its record is forgotten", DMSMKeyText(k)]);
            [gMSWWinDesk removeObjectForKey:k]; [gMSWWinFrame removeObjectForKey:k]; [gMSWWinShots removeObjectForKey:k];
            dirty = YES;
        }
    }
    if (dirty) DMMSWSave();
}

// The first "+": the windows of the desktop the engine had (the most recent stage on the iPad with a window that is not minimized) and the
// minimized ones become Desktop 1's. Older stages are apps without a window (they join the desktop they are opened on).
static void DMMSWSMRecordFirst(void) {
    if (!gMSWWinDesk) gMSWWinDesk = [NSMutableDictionary dictionary];
    for (id al in DMSMRecentStages()) {
        if (!DMSMIsMainIdentity(DMSMStageDisplayIdentity(al))) continue;
        NSMutableArray *ks = [NSMutableArray array];
        for (id it in DMSMStageItemsMap(al)) { NSString *k = DMSMItemKey(it); if (k.length && !DMSMIsMinimized(k)) [ks addObject:k]; }
        if (!ks.count) continue;
        for (NSString *k in ks) gMSWWinDesk[k] = @1;
        break;
    }
    for (NSString *k in DMSMMinimizedSet()) gMSWWinDesk[k] = @1;   // (each by its key; an older entry by app stands for the app's windows)
    NSMutableArray *names = [NSMutableArray array]; for (NSString *k in gMSWWinDesk) [names addObject:DMSMKeyText(k)];
    DMLog([NSString stringWithFormat:@"[macswitcher] Desktop 1's windows: %@", names.count ? [names componentsJoinedByString:@", "] : @"none"]);
}

// Asks for a desktop's windows together (its stage, in front; its newest window in front of the others). Returns the window expected in front
// (its key), nil when the desktop has no window (the Home Screen is asked for instead, if an app is in front).
static NSString *DMMSWSMShowDesk(NSInteger did, NSString *why) {
    NSArray *wins = DMMSWSMDeskWindows(did);
    NSUInteger i = [gMSWDesks indexOfObject:@(did)];
    if (!wins.count) {
        // (a real Home: since 1.3.8 a plain Home keeps the desktop's windows on screen (SMHome.h's rule) -- the left desktop's windows would stay on
        //  the empty one; ours is labelled as our own and goes Home with them, SMHome.h DMSMGoHomeForReal)
        if (DMFrontApp()) { DMLog([NSString stringWithFormat:@"[macswitcher] %@ has no window: the Home Screen", DMMSWDeskName(i)]); DMSMGoHomeForReal(@"an empty Mac Switcher desktop"); }
        return nil;
    }
    NSMutableArray *left = [NSMutableArray array];
    NSArray *plan = DMMSWSMPlan(wins, nil, left);
    id identity = DMSMIdentityOfScreen([UIScreen mainScreen]);
    if (!plan || !DMSMRequestOnWhole(identity, @"MSBDDesktop", plan, DMSMNewWindowRoles(), plan.firstObject[0])) {
        // (never the left desktop's windows under the new desktop's name: the Home Screen; its windows stay in their stage, recorded on it, and
        //  come back with the next app opened there -- DMMSWSMJoin writes them into that launch)
        DMLog([NSString stringWithFormat:@"[macswitcher] %@'s windows could not be asked for (%@): the Home Screen instead", DMMSWDeskName(i), why]);
        gMSWSMDiag[1]++; DMSM17DiagSoon();   // (iPadOS 17 diagnostics)
        if (DMFrontApp()) DMSMGoHomeForReal(@"a Mac Switcher desktop whose windows could not be asked for");
        return nil;
    }
    NSMutableArray *names = [NSMutableArray array]; for (NSArray *w in wins) if (![left containsObject:w[3]]) [names addObject:DMSMKeyText(w[3])];
    DMLog([NSString stringWithFormat:@"[macswitcher] %@'s windows asked for (%@): %@", DMMSWDeskName(i), why, [names componentsJoinedByString:@", "]]);
    // (more windows than a desktop holds -- a remove's merge: DMMSWSMAtCap(DMMSWSMCapMerge) answers MinimizeOldest, the one way this path has)
    DMMSWSMLeftOut(left, DMMSWDeskName(i));
    return wins.firstObject[3];
}

// A window card's still picture with our title bar above it, and where the two are on the screen (UIScreen's coordinate space).
static UIView *DMMSWSMCardPicture(UIView *card, CGRect *onScreen) {
    id<UICoordinateSpace> scr = [UIScreen mainScreen].coordinateSpace;
    CGRect r = [card convertRect:card.bounds toCoordinateSpace:scr];
    UIView *pic = [card snapshotViewAfterScreenUpdates:NO];
    UIView *bar = DMSMCardHasBar(card) ? objc_getAssociatedObject(card, kSMBarKey) : nil;
    if (bar) {   // (the window with its title bar: the card's picture alone was stretched over both in a drawn-again thumbnail)
        CGRect br = [card convertRect:CGRectMake(0, -kSMBarH, card.bounds.size.width, kSMBarH) toCoordinateSpace:scr], u = CGRectUnion(r, br);
        UIView *both = [[UIView alloc] initWithFrame:CGRectMake(0, 0, u.size.width, u.size.height)];
        UIView *barPic = [bar snapshotViewAfterScreenUpdates:NO];
        if (barPic) { barPic.frame = CGRectOffset(br, -u.origin.x, -u.origin.y); [both addSubview:barPic]; }
        if (pic) { pic.frame = CGRectOffset(r, -u.origin.x, -u.origin.y); [both addSubview:pic]; }
        pic = both.subviews.count ? both : nil; r = u;
    }
    if (onScreen) *onScreen = r;
    return pic;
}
// Leaving a desktop: each of its windows' pictures and places (its thumbnail is drawn from them when its windows change while away) and its Fit to
// Window arrangement; arriving: that desktop's arrangement back.
static void DMMSWSMLeave(NSInteger fromId) {
    if (!gMSWWinShots) gMSWWinShots = [NSMutableDictionary dictionary];
    for (UIView *card in DMMSWSMVisibleCards()) {
        NSString *k = DMSMCardKey(card);   // (each window by its key: two windows of one app have two pictures and places)
        CGRect r = CGRectNull;
        UIView *pic = DMMSWSMCardPicture(card, &r);
        if (pic) gMSWWinShots[k] = pic;
        gMSWWinFrame[k] = NSStringFromCGRect(r);
    }
    if (!gMSWFit) gMSWFit = [NSMutableDictionary dictionary];
    gMSWFit[[@(fromId) stringValue]] = @{@"smslots": [gSMFitSlots copy] ?: @{}, @"smfree": [gSMFreeWindows allObjects] ?: @[]};
    gMSWDesksDirty = YES;
}
static void DMMSWSMArrive(NSInteger toId) {
    NSDictionary *fit = gMSWFit[[@(toId) stringValue]];
    [gMSWFit removeObjectForKey:[@(toId) stringValue]];
    gSMFitSlots = nil; [gSMFreeWindows removeAllObjects];
    NSDictionary *slots = fit[@"smslots"];
    if ([slots isKindOfClass:[NSDictionary class]] && slots.count) {
        gSMFitSlots = [NSMutableDictionary dictionary];
        for (id b in slots) if ([b isKindOfClass:[NSString class]] && [slots[b] isKindOfClass:[NSString class]]) gSMFitSlots[b] = slots[b];
    }
    NSArray *free = fit[@"smfree"];
    if ([free isKindOfClass:[NSArray class]]) for (id b in free) if ([b isKindOfClass:[NSString class]]) { if (!gSMFreeWindows) gSMFreeWindows = [NSMutableSet set]; [gSMFreeWindows addObject:b]; }
}

// Pictures cost the render server's memory (backboardd: a whole-screen picture is ~12.6 MB on the iPad 2; 8 desktops took it from 28 to 151 MB, and
// iPadOS then began closing processes for memory). So full pictures -- the screen and each of its windows -- are kept only for the desktop(s)
// left last (the ones a switch most likely goes back to: one on an iPad with less than 4 GB, two with more); an older desktop is drawn in the strip from its windows' places (wallpaper + each
// window's app icon, DMMSWSMComposedDesktop) and slides in live. The desktop on screen keeps none (they are taken again when it is left).
static NSMutableDictionary<NSNumber *, NSNumber *> *gMSWSMLeftAt;   // desktop id -> when it was left
static void DMMSWSMTrimPictures(NSInteger currentId) {
    for (NSString *k in [gMSWWinShots allKeys]) if (DMMSWSMRecordOf(k).integerValue == currentId) [gMSWWinShots removeObjectForKey:k];
    NSArray<NSNumber *> *byAge = [[gMSWShots allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        double ta = gMSWSMLeftAt[a].doubleValue, tb = gMSWSMLeftAt[b].doubleValue;
        return ta > tb ? NSOrderedAscending : (ta < tb ? NSOrderedDescending : NSOrderedSame);
    }];
    // (one picture on an iPad with less than 4 GB -- the one to go back to --, two with more: measured on the iPad 2 (2 GB), the two pictures, a
    //  window's and the Home Screen's were ~37 MB of the render server's memory, given back when they were let go)
    NSUInteger keep = [NSProcessInfo processInfo].physicalMemory >= 3.5e9 ? 2 : 1;
    NSMutableArray *dropped = [NSMutableArray array];
    for (NSUInteger i = keep; i < byAge.count; i++) {
        NSNumber *did = byAge[i];
        [gMSWShots removeObjectForKey:did]; [gMSWShotSet removeObjectForKey:did];
        for (NSString *k in [gMSWWinShots allKeys]) if ([DMMSWSMRecordOf(k) isEqual:did]) [gMSWWinShots removeObjectForKey:k];
        [dropped addObject:did];
    }
    if (dropped.count) DMLog([NSString stringWithFormat:@"[macswitcher] pictures kept for the %lu desktop(s) left last; let go: desktop %@", (unsigned long)keep, [dropped componentsJoinedByString:@", "]]);
}

// The arriving desktop's picture, for the slide: as it was left while its windows are still the same, else drawn from its windows' pictures; an
// empty desktop is the Home Screen, which every desktop shares (the last picture of it, from whichever desktop showed it). nil = none yet (a
// desktop not seen since the respring): the slide then waits for the live desktop.
static UIView *gMSWSMHomeShot;   // (the Home Screen as last left: the picture of any empty desktop, and what is behind a drawn desktop's windows)
static UIView *DMMSWSMHomeBackdrop(CGRect b);
static BOOL DMMSWSMHomeBackdropOK(CGRect b);
static void DMMSWSMFreePictures(void) { gMSWSMHomeShot = nil; }   // (memory pressure, MacSwitcher.h DMMSWFreePictures: an empty desktop slides in live until it is left again)
// A picture view is in one place at a time: one that is on the slide's strip already -- the left desktop's own, or another slot's: the same desktop
// asked for again by a re-aim or the fingers' take, two empty desktops sharing the Home Screen's -- is given as a picture of it; moving it left its
// first slot black (1.4.1 logic test H-1: a far switch's own picture taken for the fingers' slot beside it).
static UIView *DMMSWSMNotOnStrip(UIView *pic) {
    if (pic && gMSWSlStrip && [pic isDescendantOfView:gMSWSlStrip]) return [pic snapshotViewAfterScreenUpdates:NO];
    return pic;
}
static UIView *DMMSWSMDeskPicture(NSInteger did, CGRect b) {
    UIView *shot = gMSWShots[@(did)];
    NSArray *set = DMMSWWindowSet(did);
    if (shot && [gMSWShotSet[@(did)] isEqualToArray:set]) {
        // (a kept picture drawn from its windows without the Home Screen's picture -- a window landed on that desktop, MacSwitcher.h
        //  DMMSWDeskTakesWindow --: the shared windows again at this slide, as when it was drawn)
        if ([objc_getAssociatedObject(shot, kMSWDrawnKey) boolValue] && !DMTestFlag("/tmp/msw-sm-noshared")) objc_setAssociatedObject(shot, kMSWSharedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return DMMSWSMNotOnStrip(shot);
    }
    // (a desktop with windows and no picture as it was left -- one desktop keeps its pictures on an iPad under 4 GB (DMMSWSMTrimPictures), none
    //  after a respring --: drawn from its windows, each one's picture where it is kept, else its place as a card with its app's icon, over the
    //  Home Screen as last left or the wallpaper (DMMSWSMComposedDesktop), as the other engines draw such a desktop from its parts
    //  (MacSwitcher.h DMMSWDeskPicture). It slid in live before, and a live slide can be neither re-aimed nor taken by the fingers -- 1.4.1
    //  logic test H-2. Debug /tmp/msw-sm-nodrawn = before.)
    NSArray *wins = DMMSWSMDeskWindows(did);
    if (wins.count) {
        if (DMTestFlag("/tmp/msw-sm-nodrawn")) {
            NSUInteger have = 0; for (NSArray *w in wins) if (gMSWWinShots[w[3]]) have++;
            return have && (gMSWWallContents || DMMSWSMHomeBackdropOK(b)) ? DMMSWSMComposedDesktop(did, b) : nil;
        }
        return DMMSWSMComposedDesktop(did, b);
    }
    // (an empty desktop: the Home Screen as last left; none yet -- a respring, or let go under memory pressure --: nil, and the shared picture
    //  draws it, the wallpaper with the Home Screen, the Dock and the menu bar live, MacSwitcher.h DMMSWDeskPicture)
    return DMMSWSMNotOnStrip(gMSWSMHomeShot);
}
// The switch, with a Mac's slide. Measured on the iPad 2 (3 Oct): asking Stage Manager for a desktop's stage blocks SpringBoard's main thread
// for ~0.4 s (it sets up the whole transition at once) and the cards then settle within a few frames -- a slide started after that left the
// screen frozen for ~0.7 s first. So the slide is started FIRST, with the arriving desktop's picture: a committed animation is played by the
// render server while the main thread is busy. A frame later, under it, the stage is asked for (or the Home Screen); once the window cards are
// drawn still (and the slide is over) the cover fades to the live screen. No picture of the arriving desktop yet: the left desktop's picture
// covers the screen until the live desktop is drawn, then slides away over it.
// launching: the window whose launch brings this desktop (its key; the launch's own transition asks for the stage, DMMSWSMJoin), or nil.
// v: the fingers' speed when a side swipe brings the desktop (0 from rest). The slide is the shared one (MacSwitcher.h, DMMSWSlBegin / Finish /
// Reveal): begun by the fingers already (the tracker), or here with the arriving desktop's picture.
// A side swipe or a Control-arrow while the slide runs gives it another aim (DMMSWSMRedirect), as with the other engines (MacSwitcher.h
// DMMSWSwRedirect): the slide goes on from where it is, at the speed it has, to the next desktop that way -- or back --, and under the cover
// Stage Manager is asked for that desktop's stage instead; a desktop only passed is never revealed (its Fit arrangement is kept, no pictures are
// taken of it). An aim's change, wait and reveal belong to it (gMSWSMAimGen): an older aim's wait ends doing nothing. Not for a launch's switch
// (its transition asks for the stage), a switch with its own follow-up (a remove), a live slide (no picture to go on with), Reduce Motion's
// cross-fade, or once the reveal began: the desktop then comes right after, as before (gMSWPendingSide).
static NSInteger gMSWSMQueued = 0;           // (Reduce Motion: side requests made during the cross-fade, taken one by one at each switch's end, H-4)
static NSUInteger gMSWSMAimGen = 0;          // (the aim)
static NSUInteger gMSWSMAimTo = 0;           // the desktop place it goes to now
static NSInteger gMSWSMAimSlot = 0;          // that desktop's picture's slot on the strip (screens from the left desktop's)
static BOOL gMSWSMAimRedirectable = NO, gMSWSMAimSlid = NO, gMSWSMAimHasPic = NO;
static BOOL gMSWSMSwChanged = NO;            // (a stage was asked for in this switch already: a redirect leaves that desktop again first)
static NSUInteger gMSWSMSwRedirects = 0;
// what the whole switch keeps from its start
static NSUInteger gMSWSMSwFrom = 0;
static NSInteger gMSWSMSwFromId = 0;
static UIView *gMSWSMSwOld;
static BOOL gMSWSMSwLeftHome = NO;
static CFTimeInterval gMSWSMSwT0 = 0, gMSWSMSwT1 = 0;
static CGFloat gMSWSMSwV = 0;
static NSString *gMSWSMSwWhy, *gMSWSMSwLaunching;
static void (^gMSWSMSwDone)(void);
static void DMMSWSMAimChange(NSUInteger gen);
static void DMMSWSMSwitch(NSUInteger to, NSString *why, NSString *launching, CGFloat v, void (^done)(void)) {
    BOOL fromGesture = gMSWTrackCommit && gMSWSlRoot != nil;
    if (to >= gMSWDesks.count || to == gMSWCur || gMSWSwitching || gMSWTrack == 2 || (gMSWTrack == 3 && !fromGesture)) { if (done) done(); return; }
    gMSWSwitching = YES;
    gMSWSMQuietUntil = CACurrentMediaTime() + 5.0;   // (DMMSWSMApply stays out of it until the slide is over)
    CFTimeInterval t0 = CACurrentMediaTime();
    DMMSWRecBegin([NSString stringWithFormat:@"switch (%@, Stage Manager)", why]);   // (debug measurement, /tmp/msw-rec: a followed gesture's recording is named)
    DMMSWMark(@"switch");
    NSUInteger from = gMSWCur;
    NSInteger fromId = DMMSWCurId(), toId = gMSWDesks[to].integerValue;
    BOOL wasOpen = gMSWOpen, leftHome = DMFrontApp() == nil;
    UIView *old = gMSWSlOld, *pic = gMSWSlSide[to > from ? 1 : 0];
    if (!fromGesture) {
        old = DMMSWLeftPicture(wasOpen);
        // (the arriving desktop's picture: Stage Manager's own -- as it was left, or drawn from its windows -- else the shared one, the wallpaper with
        //  the Home Screen live for an empty desktop not seen since a respring (MacSwitcher.h DMMSWDeskPicture): every switch is a picture slide that
        //  a side request can re-aim and the fingers can take; 1.4.1 logic test H-2. Debug /tmp/msw-sm-nodrawn = before: Stage Manager's own only.)
        pic = old ? (DMTestFlag("/tmp/msw-sm-nodrawn") ? DMMSWSMDeskPicture(toId, [UIScreen mainScreen].bounds) : DMMSWDeskPicture(to, [UIScreen mainScreen].bounds)) : nil;
        if (wasOpen) DMMSWCloseUnderSlide();
        DMMSWSlBegin(old, to < from ? pic : nil, to > from ? pic : nil);
    }
    gMSWSMSwFrom = from; gMSWSMSwFromId = fromId; gMSWSMSwOld = old; gMSWSMSwLeftHome = leftHome; gMSWSMSwT0 = t0; gMSWSMSwV = v;
    gMSWSwFrom = from;   // (the shared strip's left desktop: the fingers' take of the running slide reads it, MacSwitcher.h DMMSWGrabOffset / Decide / Pictures)
    gMSWSMSwWhy = why; gMSWSMSwLaunching = launching; gMSWSMSwDone = done; gMSWSMSwChanged = NO; gMSWSMSwRedirects = 0;
    NSUInteger gen = ++gMSWSMAimGen;
    gMSWSMAimTo = to; gMSWSMAimSlot = to > from ? 1 : -1; gMSWSMAimSlid = NO; gMSWSMAimHasPic = pic != nil;
    gMSWSMAimRedirectable = pic && gMSWSlRoot && !launching && !done;
    if (gMSWSlRoot) {   // (which desktop each slot shows: a redirect goes on only where the next slot is free or shows that desktop)
        DMMSWSlSetPlace(0, from);
        if (fromGesture || DMTestFlag("/tmp/msw-sm-oldplaces")) {   // (the tracker's own slide: the desktops on either side)
            if (gMSWSlSide[0] && from > 0) DMMSWSlSetPlace(-1, from - 1);
            if (gMSWSlSide[1] && from + 1 < gMSWDesks.count) DMMSWSlSetPlace(1, from + 1);
        } else if (pic) DMMSWSlSetPlace(to > from ? 1 : -1, to);
        // (any other switch has the ARRIVING desktop's picture beside the left one, also for a far switch -- as MacSwitcher.h DMMSWSwitchGo marks it. It
        //  was marked as the neighbour's: a far switch (the strip, D3 -> D1) then looked like a slide in desktop order, the fingers took it and the
        //  slot for D1 two screens away took D1's picture from the slot beside -- black there --, and the lift landed on the wrong desktop; 1.4.1
        //  logic test H-1. Now a far switch is taken by no fingers (DMMSWSMCanTake: not in order), its side swipe comes at the lift, as with the other
        //  engines. Debug /tmp/msw-sm-oldplaces = before.)
    }
    if (pic) DMMSWSlFinish(to > from ? 1 : -1, v, ^{ if (gen == gMSWSMAimGen) gMSWSMAimSlid = YES; });   // (committed with this turn of the run loop, before the stage is asked for)
    gMSWSMSwT1 = CACurrentMediaTime();
    if (launching) DMMSWSMAimChange(gen);   // (inside the launch's transition: the stage is the launch's own)
    else dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((wasOpen ? kMSWViewFade : 1.0 / 60.0) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMMSWSMAimChange(gen); });   // (a frame later, under the slide -- after the Mac Switcher's view has faded over it, when it was open)
}
// The switch is over (the reveal is done): the left desktop's picture is its thumbnail; the new one is drawn live.
static void DMMSWSMSwitchEnd(NSInteger toId) {
    UIView *old = gMSWSMSwOld;
    NSInteger fromId = gMSWSMSwFromId;
    void (^done)(void) = gMSWSMSwDone;
    CFTimeInterval t0 = gMSWSMSwT0;
    gMSWSMSwOld = nil; gMSWSMSwDone = nil; gMSWSMSwLaunching = nil; gMSWSMAimRedirectable = NO;
    if (old && fromId != toId) {
        if (!gMSWShots) gMSWShots = [NSMutableDictionary dictionary];
        if (!gMSWShotSet) gMSWShotSet = [NSMutableDictionary dictionary];
        if (!gMSWSMLeftAt) gMSWSMLeftAt = [NSMutableDictionary dictionary];
        gMSWShots[@(fromId)] = old; gMSWShotSet[@(fromId)] = DMMSWWindowSet(fromId); gMSWSMLeftAt[@(fromId)] = @(CACurrentMediaTime());
    }
    [gMSWShots removeObjectForKey:@(toId)];
    DMMSWSMTrimPictures(toId);
    gMSWSwitching = NO;
    if (gMSWTrack == 3) gMSWTrack = 0;
    gMSWSMQuietUntil = CACurrentMediaTime() + 1.0;
    DMMSWRecEndAfter(0.5);
    gMSWSMDiag[0]++; gMSWSMDiag[4] = (unsigned)MIN(99999.0, (CACurrentMediaTime() - t0) * 1000.0); DMSM17DiagSoon();   // (iPadOS 17 diagnostics)
    if (done) done();
    // (a side swipe or a Control-arrow made while this switch ran that could not re-aim it: its desktop comes now; it was kept in
    //  gMSWPendingSide and only an Aerial switch's end took it, so here it was lost, or came at a later switch)
    NSInteger pend = gMSWPendingSide; gMSWPendingSide = 0;
    // (the side requests made while this switch ran: under Reduce Motion every one counted (gMSWSMQueued, H-4), else the one kept for right after
    //  (pend); one desktop at a time -- the rest waits for the next switch's end. A request towards no desktop is dropped.)
    NSInteger q = gMSWSMQueued + pend; gMSWSMQueued = 0;
    if (q) {
        NSInteger step = q > 0 ? 1 : -1, to = (NSInteger)gMSWCur + step;
        if (to >= 0 && to < (NSInteger)gMSWDesks.count) {
            gMSWSMQueued = q - step;
            DMLog(gMSWSMQueued ? [NSString stringWithFormat:@"[macswitcher] the side swipe made on the way: its desktop comes now (Stage Manager; %ld more after it)", (long)labs(gMSWSMQueued)]
                               : @"[macswitcher] the side swipe made on the way: its desktop comes now (Stage Manager)");
            DMMSWSMSwitch((NSUInteger)to, @"side swipe made on the way", nil, 0, nil);
            if (!gMSWSwitching) gMSWSMQueued = 0;   // (it could not start: nothing waits on it)
        }
    }
}
// The aim's change: the stage of the desktop it goes to is asked for under the slide (the left desktop is left first: its windows' pictures, still
// the ones under the cover, and its arrangement; a desktop a redirect only passed keeps its arrangement, no pictures), then the wait for its window
// cards to be drawn still, then the reveal.
static void DMMSWSMAimChange(NSUInteger gen) {
    if (gen != gMSWSMAimGen || !gMSWSwitching) return;   // (re-aimed before this ran: the newer aim's change runs instead)
    CFTimeInterval t2 = CACurrentMediaTime();
    NSUInteger to = gMSWSMAimTo, from = gMSWSMSwFrom;
    NSInteger toId = gMSWDesks[to].integerValue;
    if (!gMSWSMSwChanged) {
        DMMSWSMLeave(gMSWSMSwFromId);   // (its windows' pictures: still the ones under the cover)
        if (gMSWSMSwLeftHome && gMSWSMSwOld) gMSWSMHomeShot = gMSWSMSwOld;
    } else {
        if (!gMSWFit) gMSWFit = [NSMutableDictionary dictionary];   // (only passed: its arrangement as it came, nothing of it was drawn for it)
        gMSWFit[[@(DMMSWCurId()) stringValue]] = @{@"smslots": [gSMFitSlots copy] ?: @{}, @"smfree": [gSMFreeWindows allObjects] ?: @[]};
        gMSWDesksDirty = YES;
    }
    gMSWSMSwChanged = YES;
    gMSWCur = to;
    DMMSWSMArrive(toId);
    if (gNativeActive) DMNativeSetActive(nil);
    gMSWSwitching = NO; DMMSWApply(); gMSWSwitching = YES;   // (Finder's windows: the left desktop's away, the new one's back)
    NSString *want = gMSWSMSwLaunching ?: DMMSWSMShowDesk(toId, gMSWSMSwRedirects ? @"redirect" : gMSWSMSwWhy);
    DMMSWSave();
    DM_FEATURE_MARK("mac-switcher-desktops-sm");
    CFTimeInterval t3 = CACurrentMediaTime();
    DMMSWMark([NSString stringWithFormat:@"stage asked (%.1f ms)", (t3 - t2) * 1000]);
    // (Stage Manager has drawn the new desktop: its stage in front holding that window (or the Home Screen), and the window cards standing
    //  still for 3 frames -- the model names the stage before its cards are in place. At most 1.2 s.)
    __block int frames = 0, settled = 0;
    __block BOOL fitDone = NO;
    __block NSString *drawnBefore = nil;
    __block void (^wait)(void);
    BOOL hasPic = gMSWSMAimHasPic;
    void (^w)(void) = ^{
        if (gen != gMSWSMAimGen) { wait = nil; return; }   // (re-aimed: the newer aim waits for its own desktop)
        frames++;
        BOOL there;
        if (want) {
            there = NO;
            if (DMFrontApp()) for (id it in DMSMStageItemsMap(DMSMFrontStage())) if (DMMSWSMSameWindow(DMSMItemKey(it), want)) there = YES;
        } else there = DMFrontApp() == nil;
        NSString *drawn = DMMSWSMCardsDrawn();
        if (there && [drawn isEqualToString:drawnBefore]) settled++; else settled = 0;
        drawnBefore = drawn;
        BOOL slideOver = !hasPic || gMSWSMAimSlid || !gMSWSlRoot;
#if DEBUG
        if (DMTestFlag("/tmp/msw-sm-drawlog")) DMLog([NSString stringWithFormat:@"[mswdraw] +%.0f ms frame %d there %d settled %d slide over %d: %@", (CACurrentMediaTime() - t3) * 1000, frames, there, settled, slideOver, drawn.length ? drawn : @"-"]);
#endif
        // (Fit to Window: the arriving desktop is tiled under the cover once its stage is drawn -- the tick did it after the reveal, and a desktop
        //  that was not tiled yet jumped into its tiles in front of the user; then the cards settle again)
        if (settled >= 3 && !fitDone && frames < 60 && DMFitEnabled()) {
            fitDone = YES; settled = 0; drawnBefore = nil;
            gMSWSwitching = NO; DMSMFitTick(NO); gMSWSwitching = YES;
        }
        if ((settled < 3 || !slideOver) && frames < 72) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NSEC_PER_SEC / 60)), dispatch_get_main_queue(), wait); return; }
        wait = nil;
        gMSWSMAimRedirectable = NO;   // (the reveal begins: a side swipe from now on brings the next desktop right after)
        CFTimeInterval t4 = CACurrentMediaTime();
        DMMSWMark([NSString stringWithFormat:@"cards drawn (%d frames)", frames]);
        if (hasPic) DMMSWSlReveal(kMSWRevealFade, ^{ DMMSWSMSwitchEnd(toId); });   // (the picture has slid in: the live screen shows through)
        else DMMSWSlLive(to > from ? 1 : -1, gMSWSMSwV, ^{ DMMSWSMSwitchEnd(toId); });   // (no picture of it: the live desktop, drawn now, slides in)
        DMLog([NSString stringWithFormat:@"[macswitcher] %@ -> %@ (%@, Stage Manager, %@%@): cover%@ %.1f ms, stage asked %.1f ms (%.0f ms after the start), drawn after %d frames (%.0f ms%@); drawn: %@",
            DMMSWDeskName(from), DMMSWDeskName(to), gMSWSMSwWhy, hasPic ? @"picture slide" : @"live slide", gMSWSMSwRedirects ? [NSString stringWithFormat:@", %lu redirect(s)", (unsigned long)gMSWSMSwRedirects] : @"",
            hasPic ? @" + slide" : @"", (gMSWSMSwT1 - gMSWSMSwT0) * 1000, (t3 - t2) * 1000, (t3 - gMSWSMSwT0) * 1000, frames, (t4 - t3) * 1000,
            settled >= 3 ? @"" : @", not settled: went on anyway", drawnBefore.length ? drawnBefore : @"no window"]);
    };
    wait = w;
    dispatch_async(dispatch_get_main_queue(), wait);
}
// The fingers take the running slide (MacSwitcher.h DMMSWTrackGrabEngage: a side swipe made while it runs, Reduce Motion off), as with the other
// engines: it stops under them and follows them over the desktops on either side; at the lift it goes on to the desktop they chose -- the switch's
// new aim, that desktop's stage asked for under the cover (a desktop only passed keeps its arrangement). Only where a re-aim may happen.
static BOOL DMMSWSMCanTake(void) {
    if (!gMSWSMAimRedirectable) return NO;
    for (NSNumber *k in gMSWSlPlaces) if (gMSWSlPlaces[k].integerValue != (NSInteger)gMSWSMSwFrom + k.integerValue) return NO;   // (the strip in desktop order)
    return gMSWSlPlaces.count > 0;
}
static NSUInteger DMMSWSMAimPlace(void) { return gMSWSMAimTo; }
static void DMMSWSMTaken(void) {   // (the aim it had is given up: its landing and wait do nothing; the stage its change asked for stays until the lift)
    gMSWSMAimGen++; gMSWSMAimSlid = NO;
    gMSWSMQuietUntil = CACurrentMediaTime() + 20.0;   // (the fingers may hold it a while: the tick stays out until the lift's aim is in)
    DM_FEATURE_MARK("mac-switcher-take-slide-sm");
}
static void DMMSWSMTakenLift(NSInteger k, CGFloat v) {
    NSUInteger place = (NSUInteger)((NSInteger)gMSWSMSwFrom + k);
    if (place >= gMSWDesks.count || !DMMSWSlEnsurePic(k, place)) { k = 0; place = gMSWSMSwFrom; }
    NSUInteger gen = ++gMSWSMAimGen;
    gMSWSMAimTo = place; gMSWSMAimSlot = k; gMSWSMAimSlid = NO; gMSWSMAimHasPic = YES; gMSWSMSwRedirects++;
    gMSWSMQuietUntil = CACurrentMediaTime() + 5.0;
    DMMSWMark([NSString stringWithFormat:@"lifted (a taken slide): to %@ (slot %+ld, %.0f pt/s)", DMMSWDeskName(place), (long)k, v]);
    gMSWSlMaxAway = 3000.0;
    DMMSWSlFinishTo(k, v, ^{ if (gen == gMSWSMAimGen) gMSWSMAimSlid = YES; });
    gMSWSlMaxAway = 900.0;
    // (the chosen desktop's stage under the cover -- the one asked for already when the fingers took it, again -- a frame later, as every stage
    //  this switch asks for: the lift runs inside SpringBoard's own end of the gesture, and a stage asked for in there made SpringBoard's switcher
    //  fail its own assertion at that end -- -[SBFluidSwitcherViewController handleFluidSwitcherGestureManager:didEndGesture:], iPad 2 crash
    //  21:32:57 on the first build of this)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NSEC_PER_SEC / 60)), dispatch_get_main_queue(), ^{ DMMSWSMAimChange(gen); });
}
// A side swipe or a Control-arrow while the switch runs (MacSwitcher.h DMMSWSideRequest via DMMSWSwRedirect): the slide's new aim. NO = it
// cannot be re-aimed now (the desktop comes right after, gMSWPendingSide).
static BOOL DMMSWSMRedirect(NSInteger side, CGFloat v, NSString *why) {
    if (!side || !gMSWSwitching || !gMSWSlRoot || !gMSWSMAimRedirectable || gMSWTrack == 1 || gMSWTrack == 2) return NO;
    if (MSBReduceMotion() && !DMTestFlag("/tmp/msw-sm-noqueue")) {
        // (a cross-fade: one desktop after the other, as the other engines' cross-fades -- and every request counts: each is taken in turn when the
        //  running switch ends (DMMSWSMSwitchEnd), as MacSwitcher.h queues them during its cross-fade (gMSWSwQueued). Only the last one was kept
        //  (gMSWPendingSide), so three quick presses moved one desktop; 1.4.1 logic test H-4. Debug /tmp/msw-sm-noqueue = before.)
        NSInteger to = (NSInteger)gMSWSMAimTo + gMSWSMQueued + side;
        if (to < 0 || to >= (NSInteger)gMSWDesks.count) {
            DMLog([NSString stringWithFormat:@"[macswitcher] %@ during the cross-fade: no desktop on that side (Stage Manager)", why]);
            return YES;
        }
        gMSWSMQueued += side;
        DMLog([NSString stringWithFormat:@"[macswitcher] %@ during the cross-fade: the next one starts when it ends (Stage Manager, %+ld waiting)", why, (long)gMSWSMQueued]);
        return YES;
    }
    if (MSBReduceMotion()) return NO;
    NSInteger to = (NSInteger)gMSWSMAimTo + side, k = gMSWSMAimSlot + side;
    if (to < 0 || to >= (NSInteger)gMSWDesks.count) {
        DMLog([NSString stringWithFormat:@"[macswitcher] %@ while sliding to %@: no desktop on that side, it slides on", why, DMMSWDeskName(gMSWSMAimTo)]);
        return YES;
    }
    NSNumber *there = gMSWSlPlaces[@(k)];
    if (there && there.integerValue != to) return NO;   // (that slot shows another desktop)
    // (its picture beside the slide: Stage Manager's own or the shared one -- there always is one now, H-2; a picture already on the strip is given
    //  as a picture of it, H-1)
    if (!DMMSWSlPicAt(k) && !DMMSWSlEnsurePic(k, (NSUInteger)to)) return NO;
    // (the speed: the slide's own where it is -- no jump in its motion; moving the other way it turns back on the spring --, or the fingers' when
    //  they flicked that way faster)
    CGFloat now = DMMSWSlSpeedNow(), dir = side > 0 ? -1.0 : 1.0, vv = (v * dir > 0 && v * dir > now * dir) ? v : now;
    NSUInteger gen = ++gMSWSMAimGen;
    BOOL changed = gMSWSMSwChanged;
    gMSWSMAimTo = (NSUInteger)to; gMSWSMAimSlot = k; gMSWSMAimSlid = NO; gMSWSMAimHasPic = YES; gMSWSMSwRedirects++;
    gMSWSMQuietUntil = CACurrentMediaTime() + 5.0;
    DMMSWRecBegin([NSString stringWithFormat:@"redirect (%@)", why]);
    DMMSWMark([NSString stringWithFormat:@"redirect to %@ (slot %+ld, slide at %.0f pt, %.0f pt/s)", DMMSWDeskName((NSUInteger)to), (long)k, DMMSWSlOffsetNow(), vv]);
    DMLog([NSString stringWithFormat:@"[macswitcher] %@ while the slide runs: on to %@ (Stage Manager; %@, the slide at %.0f pt, %.0f pt/s)", why, DMMSWDeskName((NSUInteger)to),
        changed ? [NSString stringWithFormat:@"%@'s stage was asked for, it is left again", DMMSWDeskName(gMSWCur)] : @"no stage asked for yet", DMMSWSlOffsetNow(), vv]);
    DM_FEATURE_MARK("mac-switcher-redirect-sm");
    gMSWSlMaxAway = 3000.0;   // (a slide sent back the other way turns on its spring, ~80 pt further at most, as a Mac's does -- no stop and jump)
    DMMSWSlFinishTo(k, vv, ^{ if (gen == gMSWSMAimGen) gMSWSMAimSlid = YES; });
    gMSWSlMaxAway = 900.0;
    // (the stage the slide was going to is asked for already: the new one's a frame later -- never from inside the call that asked, which can be
    //  SpringBoard's own end of a swipe (DMMSWSideRequest at the lift): a stage asked for in there fails SpringBoard's assertion at that end, see
    //  DMMSWSMTakenLift; else the first aim's change, waiting its frame (or the Mac Switcher's view fading away), finds itself re-aimed and does
    //  nothing -- this aim's runs after that same wait)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((changed ? 1.0 / 60.0 : kMSWViewFade) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMMSWSMAimChange(gen); });
    return YES;
}
static void DMMSWSMSwitchRun(NSUInteger to, NSString *why, CGFloat v, void (^done)(void)) { DMMSWSMSwitch(to, why, nil, v, done); }

// A desktop removed (MacSwitcher.h DMMSWRemoveDesktop): its windows are recorded on the neighbour now; shown together at once when that is the
// desktop on screen with a window in front, else when it is shown next. The desktop that was on screen itself: its windows are shown on the
// neighbour it slid to even when that one had none (the Home Screen) -- they went with the slide and stayed away until something opened there
// (iPad 2, 4 Oct: App Store's desktop removed next to an empty one; on a Mac, and with our other engines, the windows stay in sight).
static void DMMSWSMMerged(NSUInteger into) {
    if (into != gMSWCur || (!DMFrontApp() && !gMSWRemovingCurrent) || DMSwitcherVisible()) return;
    DMMSWSMShowDesk(DMMSWCurId(), @"a desktop was removed");
}

// A window on another desktop (not minimized): its launch brings that desktop (DMSMAddToStage leaves it to the launch; SMDesktop.h's
// DMSMDeskOnOtherDesktop: SpringBoard's stage request for it is that desktop's switch). k: the window's key; an app key (an icon tap, which knows
// only the app) -- the app's windows: elsewhere only when none of them is on the current desktop (then the app's newest window brings its desktop;
// a window of the app here comes forward as before).
static BOOL DMMSWSMElsewhere(NSString *k) {
    if (!DMMSWMulti() || !DMSMEngine() || !k.length) return NO;
    NSInteger cur = DMMSWCurId();
    BOOL away = NO;
    for (NSNumber *d in gMSWDesks)
        for (NSArray *w in DMMSWSMDeskWindows(d.integerValue)) {
            if (!DMMSWSMSameWindow(w[3], k)) continue;
            if (d.integerValue == cur) return NO;
            away = YES;
        }
    return away;
}

// ---- a window dragged onto another desktop in the Mac Switcher (MacSwitcher.h: DMMSWMoveRecords when the finger lifts, DMMSWMoveFinish when the
// thumbnail has landed) ----
// A desktop holds as many windows as a stage can (DMSMWindowCap()); a window dragged onto a FULL one does what DMMSWSMAtCap(DMMSWSMCapDrop)
// says -- today the drop is refused (MacSwitcher.h shakes it; macOS has no such limit, so the closest Mac-like answer is "no room there": nothing
// changes). Otherwise, when the finger lifts, the window is recorded on that desktop (the tick stays out of it); when its thumbnail has landed, its
// picture and place are kept for that desktop's picture and it leaves this desktop's stage the way Stage Manager takes a window out of a stage
// itself (none left: the Home Screen). The window then waits in a stage of its own, as every window of a desktop that is not shown does, until its
// desktop comes (DMMSWSMShowDesk asks for them all together then, the window among them). Fit to Window: it leaves this desktop's arrangement (the
// engine's Fit tick tiles the rest again) and is placed in the other desktop's when that desktop comes (DMMSWSMSwitch's Fit pass).
static BOOL DMMSWSMDeskFull(NSInteger did) { return DMMSWSMDeskWindows(did).count >= DMSMWindowCap(); }
static BOOL DMMSWSMDropRefused(NSInteger did) { return DMMSWSMDeskFull(did) && DMMSWSMAtCap(DMMSWSMCapDrop, NO) == DMMSWSMCapRefuse; }
// Fit to Window per desktop: the window joins the other desktop's arrangement in front, default slots for the new count, tiled when that desktop
// comes (its arrangement then covers exactly its windows: the engine's Fit tick keeps it) -- as the other engines do (DMMSWFitMove). Without this
// the arriving desktop asked "Where should ... go?" for it as for a third window opened there (iPad 2, 4 Oct, sm27); a window put on a desktop by
// hand is not one. A window left out of Fit (No Fit) stays out of it there. The order of the windows already tiled there: their slots' order.
// Four tiles there already (Fit's own four: a desktop may hold more windows than that since 1.3.6): it is a regular window over them, the four
// keep their places -- the other engines' rule (DMMSWFitMove; SMFitPlan.h's DMSMFitFourKept when that desktop comes).
static void DMMSWSMFitJoin(NSString *b, NSInteger toId) {   // (b: the window's key -- Fit's slots are kept by window key, M-2)
    if (!DMFitEnabled() || !b.length) return;
    NSString *k = [@(toId) stringValue];
    NSDictionary *st = [gMSWFit[k] isKindOfClass:[NSDictionary class]] ? gMSWFit[k] : nil;
    NSDictionary *was = [st[@"smslots"] isKindOfClass:[NSDictionary class]] ? st[@"smslots"] : @{};
    NSMutableArray *free = [st[@"smfree"] isKindOfClass:[NSArray class]] ? [st[@"smfree"] mutableCopy] : [NSMutableArray array];
    NSMutableArray<NSString *> *group = [NSMutableArray array];
    if (was.count) {   // (its arrangement as left: in its slots' order)
        NSArray *names = DMDefaultSlotNames(MIN((NSUInteger)4, was.count));
        NSArray *keys = [[was allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *x, NSString *y) {
            NSUInteger ix = [names indexOfObject:was[x]], iy = [names indexOfObject:was[y]];
            return ix < iy ? NSOrderedAscending : (ix > iy ? NSOrderedDescending : [x compare:y]);
        }];
        for (NSString *o in keys) if ([o isKindOfClass:[NSString class]] && ![o isEqualToString:b] && ![free containsObject:o]) [group addObject:o];
    } else for (NSArray *w in DMMSWSMDeskWindows(toId)) if (![w[3] isEqualToString:b] && ![free containsObject:w[3]]) [group addObject:w[3]];   // (newest first)
    NSMutableDictionary *slots = [NSMutableDictionary dictionary];
    if (DMSMKeySetHas(gSMFreeWindows, b)) { if (![free containsObject:b]) [free addObject:b]; for (NSString *o in group) if (was[o]) slots[o] = was[o]; }
    else if (group.count < 4) {
        [group insertObject:b atIndex:0];
        // (its only tiled window: it fills that desktop when it comes -- Fit's own rule, as with the other engines (MacSwitcher.h DMMSWChangeDesktop:
        //  "one window fills the space"); it kept the tile it had on its old desktop, 1.4 logic test, iPad 2 7 Oct)
        [slots addEntriesFromDictionary:DMFitPlanAfterLeave(group)];
    } else {   // (Fit's four tiles taken there: its arrangement stays as it is)
        DMLog([NSString stringWithFormat:@"[macswitcher] Fit to Window on %@: four windows are tiled there already, %@ is a regular window over them", DMMSWDeskName([gMSWDesks indexOfObject:@(toId)]), DMSMKeyText(b)]);
        return;
    }
    if (!gMSWFit) gMSWFit = [NSMutableDictionary dictionary];
    gMSWFit[k] = @{@"smslots": slots, @"smfree": free};
    NSString *what = [free containsObject:b] ? @"stays free (No Fit)" : [slots[b] isEqualToString:@"fill"] ? @"is its only tiled window: it fills the space there" : slots[b] ? [NSString stringWithFormat:@"joins in front (%lu tiles)", (unsigned long)slots.count] : @"is its only window (no tiles)";
    DMLog([NSString stringWithFormat:@"[macswitcher] Fit to Window on %@: %@ %@", DMMSWDeskName([gMSWDesks indexOfObject:@(toId)]), DMSMKeyText(b), what]);
}
static void DMMSWSMMoveRecord(NSString *b, NSInteger toId) {   // (b: the dragged window's key -- the view's tile for a card, DMMSWSMCollect)
    if (!b.length || ![gMSWDesks containsObject:@(toId)]) return;
    // (a full desktop took the drop: what DMMSWSMAtCap says -- refused before it gets here today; MinimizeOldest: that desktop's oldest window)
    NSArray<NSArray *> *there = DMMSWSMDeskWindows(toId);
    if (there.count >= DMSMWindowCap() && DMMSWSMAtCap(DMMSWSMCapDrop, NO) == DMMSWSMCapMinimizeOldest) {
        NSMutableArray<NSString *> *out = [NSMutableArray array];
        for (NSUInteger i = DMSMWindowCap() - 1; i < there.count; i++) [out addObject:there[i][3]];   // (newest first: the oldest from the cap on)
        DMMSWSMLeftOut(out, DMMSWDeskName([gMSWDesks indexOfObject:@(toId)]));
    }
    gMSWWinDesk[b] = @(toId);
    DMMSWSMFitJoin(b, toId);
    gMSWSMQuietUntil = CACurrentMediaTime() + 3.0;   // (the tick leaves the records alone while this desktop's stage changes)
}
static void DMMSWSMMoveFinish(NSString *b, NSInteger toId) {
    if (!DMSMEngine() || !b.length || ![gMSWDesks containsObject:@(toId)] || toId == DMMSWCurId()) return;
    NSUInteger ti = [gMSWDesks indexOfObject:@(toId)];
    for (UIView *card in DMMSWSMVisibleCards()) {
        if (![DMSMCardKey(card) isEqualToString:b]) continue;
        CGRect r = CGRectNull;
        UIView *pic = DMMSWSMCardPicture(card, &r);
        if (!gMSWWinShots) gMSWWinShots = [NSMutableDictionary dictionary];
        if (pic) gMSWWinShots[b] = pic;
        if (!CGRectIsNull(r)) gMSWWinFrame[b] = NSStringFromCGRect(r);
        break;
    }
    // Fit to Window: a tiled window leaving closes up the tiles left here as a tiled window closing does -- two or more take the default tiles, one
    // fills the space (DMFitPlanAfterLeave, the plan DMMSWFitMove takes with the other engines). The engine's Fit tick lays them out once the window
    // has left the stage: their arrangement covers exactly the windows left, so it is kept and applied (one window: SMFitTick's "fills" rule).
    // Before, only the window's own slot went: the others kept their old tiles -- one of two tiled windows dragged away left the other at its half,
    // three left two quarters with the half empty (1.4 logic test, iPad 2 7 Oct; Aerial / Zetsu / MilkyWay4 re-tiled).
    BOOL wasTiled = gSMFitSlots[b] != nil;
    [gSMFitSlots removeObjectForKey:b]; DMSMKeySetRemove(gSMFreeWindows, b);
    if (wasTiled && DMFitEnabled()) {
        NSDictionary *map = DMSMStageItemsMap(DMSMFrontStage());
        NSDictionary<NSString *, NSString *> *was = [gSMFitSlots copy];
        NSMutableArray *items = [NSMutableArray array];
        NSMutableSet<NSString *> *full = [NSMutableSet set];
        // (a window of this stage that is full screen now keeps its place in the arrangement: it comes back to a tile -- 1.4 logic test L-2: the plan
        //  left it out and it lost the tile it kept for its return)
        for (id it in map) {
            NSString *k = DMSMItemKey(it);
            if (!k.length || [k isEqualToString:b] || !gSMFitSlots[k] || DMSMKeySetHas(gSMFreeWindows, k)) continue;
            [items addObject:it];
            if (DMSMPolicyOf(map[it]) == 2) [full addObject:k];
        }
        [items sortUsingComparator:^NSComparisonResult(id x, id y) {   // (newest first, as the Fit tick orders a desktop's windows)
            long long tx = DMSMAttrTimeOr(map[x], 0), ty = DMSMAttrTimeOr(map[y], 0);
            return tx > ty ? NSOrderedAscending : (tx < ty ? NSOrderedDescending : NSOrderedSame);
        }];
        NSMutableArray<NSString *> *left = [NSMutableArray array];
        for (id it in items) [left addObject:DMSMItemKey(it)];
        NSMutableDictionary<NSString *, NSString *> *plan = left.count ? [DMFitPlanAfterLeave(left) mutableCopy] : nil;
        for (NSString *k in full) {   // (its own tile when the new arrangement has it -- a quarter it had counts as its half in two halves --, by a swap)
            NSString *want = was[k], *now = plan[k];
            if (!want.length || !now.length || [want isEqualToString:now]) continue;
            if (plan.count == 2 && ![plan.allValues containsObject:want]) want = [want hasSuffix:@"left"] ? @"left" : ([want hasSuffix:@"right"] ? @"right" : want);
            NSString *other = nil;
            for (NSString *o in plan) if (![o isEqualToString:k] && [plan[o] isEqualToString:want]) other = o;
            if (other && ![full containsObject:other]) { plan[other] = now; plan[k] = want; }
        }
        gSMFitSlots = plan;
        if (left.count) DMLog([NSString stringWithFormat:@"[fit] %@ went to another desktop: %lu window(s) left here, tiled again to fill the space (Stage Manager)", DMSMKeyText(b), (unsigned long)left.count]);
    }
    gMSWSMQuietUntil = CACurrentMediaTime() + 3.0;
    NSInteger cur = DMMSWCurId();
    NSString *why = [NSString stringWithFormat:@"%@ went to %@", DMSMKeyText(b), DMMSWDeskName(ti)];
    DMLog([NSString stringWithFormat:@"[macswitcher] %@ dragged to %@ (Stage Manager): it leaves this desktop's stage", DMSMKeyText(b), DMMSWDeskName(ti)]);
    // (a frame later: changing a stage holds SpringBoard's main thread ~0.4 s on the iPad 2; the thumbnail's fade, committed in this turn of the
    //  run loop, plays on in the render server meanwhile)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NSEC_PER_SEC / 60)), dispatch_get_main_queue(), ^{
        if (DMMSWCurId() != cur || gMSWSwitching) return;   // (a switch came first: it asks for the stages itself)
        // Other windows stay: the window is taken out of the stage by Stage Manager's own Minimize (removeFromSet) -- without our minimize's
        // bookkeeping, it is no minimized window -- and the stage on screen keeps the others, re-roled by Stage Manager itself. Not a whole-stage
        // request for the others: when the window that left was the stage's primary (role 1), that plan had to move another window into role 1
        // and empty its old role in the same request, and Stage Manager dropped that window from the new stage along with the emptied role
        // (iPad 2, 4 Oct: Clock dragged off {Clock 1, Tips 2, Settings 5} left Settings alone; Tips stayed behind in Clock's stage). No window
        // left: the Home Screen under the open view, which stays (a desktop's last window minimized would bring up an older hidden stage).
        if (DMMSWSMDeskWindows(cur).count) {
            id vc = DMSMTopAffordanceFor(b);
            id act = vc ? DMCall(vc, @"removeFromSetAction") : nil;
            if ([act isKindOfClass:[UIAction class]]) {
                DMLog([NSString stringWithFormat:@"[macswitcher] %@ taken out of %@'s stage (Stage Manager's own Minimize, not a minimized window): the others stay", DMSMKeyText(b), DMMSWDeskName([gMSWDesks indexOfObject:@(cur)])]);
                // (which window leaves, in which role: Apple's Minimize keeps the window of the highest role where it was -- on a desktop of seven
                //  the role repair takes it out, and keeps every other window, only when it knows; SMLimit.h DMSMRepairRoles, as DMSMWindowAction)
                DMSMNoteRemoving(b, DMSMStageOf(b));
                DMSMRunAction(act, vc);
                DMMSWSave();
                return;
            }
            DMLog([NSString stringWithFormat:@"[macswitcher] %@: no Minimize of its own found -- this desktop's other windows are asked for without it", DMSMKeyText(b)]);
        }
        gMSWOwnHomeAt = CACurrentMediaTime();   // (no window left: the Home Screen comes under the open view, which stays)
        DMMSWSMShowDesk(cur, why);
        gMSWOwnHomeAt = CACurrentMediaTime();
        DMMSWSave();
    });
}

// A launch (DMSMJoinDesktop: the transition context of an app opened without layout roles) with the Mac Switcher on. Written here:
//  - the app's window is on another desktop: that desktop's windows, the app in front -- its stage comes, and the strip slides to it;
//  - the current desktop is full (DMSMWindowCap() windows: as many as a stage holds) and the app is not one of them: what DMMSWSMAtCap says --
//    today the app opens on a NEW desktop, which comes with the slide (nothing on the full desktop changes; a short notice says why); at the most
//    desktops the oldest window is minimized instead (DMMSWSMLeftOut);
//  - otherwise the app joins the CURRENT desktop's windows (an empty desktop: a stage of its own, as the engine opens a first window).
// With one desktop only the full case is ours (the rest is the engine's own join). YES: handled (written, or left to Stage Manager on purpose);
// NO: the engine's own join. Every part is checked before anything is written (DMSMPlanValid), as in the engine's own join.
static BOOL DMMSWSMJoin(id ctx, id act, NSString *key) {   // (key: the window opened -- StatusBar.x DMSMJoinDesktop: DMSMEntityKey(act), else its app)
    NSString *bundle = DMSMKeyBundle(key);
    if (!gMSWOn || !DMSMEngine() || !DMMSWDesktopsHere() || !bundle.length) return NO;
    if (!DMMSWMulti()) {   // (one desktop: the engine's desktop is the most recent stage on the iPad with a window that is not minimized)
        NSUInteger n = 0; BOOL inIt = NO;
        for (id al in DMSMRecentStages()) {
            if (!DMSMIsMainIdentity(DMSMStageDisplayIdentity(al))) continue;
            for (id it in DMSMStageItemsMap(al)) { NSString *k = DMSMItemKey(it); if (k.length && !DMSMIsMinimized(k)) { n++; if (DMMSWSMSameWindow(k, key)) inIt = YES; } }
            if (n) break;
        }
        if (n < DMSMWindowCap() || inIt || !gMSWDesks.count) return NO;   // (room on the desktop, or the window is on it: the engine's own join)
        // (full: a new desktop only when DMMSWSMAtCap says so -- else the engine's own join leaves the oldest out, minimized and said: DMSMJoinDesktop
        //  hands its left-out windows to DMMSWSMLeftOut)
        if (DMMSWSMAtCap(DMMSWSMCapOpen, DMSMIsMinimized(key)) != DMMSWSMCapNewDesktop) return NO;
        DMMSWSMRecordFirst();   // (Desktop 1 = these windows, as at the first "+")
    }
    BOOL wasMinimized = DMSMIsMinimized(key);
    DMSMSetMinimized(key, NO);   // (opened again: no longer a minimized window; it comes onto the current desktop, as the engine's restore does)
    NSInteger cur = DMMSWCurId(), target = cur;
    NSArray<NSArray *> *wins = nil;
    // (the window's own desktop: the one it is recorded on, among the windows there -- a window key names that very window; an app key the app's
    //  newest window, as the Dock's click activates the app on a Mac: one of its windows on the current desktop keeps it here, DMMSWSMElsewhere)
    if (!wasMinimized && !gMSWSwitching && DMMSWSMElsewhere(key)) {
        long long best = LLONG_MIN;
        for (NSNumber *d in gMSWDesks) {
            if (d.integerValue == cur) continue;
            NSArray *there = DMMSWSMDeskWindows(d.integerValue);
            for (NSArray *w in there) if (DMMSWSMSameWindow(w[3], key) && DMSMAttrTimeOr(w[2], 0) > best) { best = DMSMAttrTimeOr(w[2], 0); target = d.integerValue; wins = there; }
        }
    }
    if (!wins) wins = DMMSWSMDeskWindows(cur);
    NSArray *mine = nil;   // (the window itself among them: that very window, or the app's newest -- wins are newest first)
    for (NSArray *w in wins) if ([w[3] isEqualToString:key]) { mine = w; break; }
    if (!mine) for (NSArray *w in wins) if (DMMSWSMSameWindow(w[3], key)) { mine = w; break; }
    NSString *fullNote = nil;
    // (the desktop is full and the window not on it: DMMSWSMAtCap -- a new desktop for it; otherwise (MinimizeOldest) the plan below leaves the
    //  oldest out, minimized and said)
    if (!mine && wins.count >= DMSMWindowCap() && !gMSWSwitching && DMMSWSMAtCap(DMMSWSMCapOpen, NO) == DMMSWSMCapNewDesktop) {
        NSInteger nid = 2;
        while ([gMSWDesks containsObject:@(nid)]) nid++;
        [gMSWDesks addObject:@(nid)];
        fullNote = [NSString stringWithFormat:@"%@: %@ opened on %@.", DMMSWSMHoldsUpTo(DMMSWDeskName(gMSWCur)), DMMSWAppName(bundle), DMMSWDeskName(gMSWDesks.count - 1)];
        gMSWSMDiag[2]++;   // (iPadOS 17 diagnostics)
        DM_FEATURE_MARK("mac-switcher-sm-full-new-desktop");
        DMLog([NSString stringWithFormat:@"[macswitcher] %@ is full (%lu windows): %@ opens on a new desktop, %@", DMMSWDeskName(gMSWCur), (unsigned long)wins.count, DMSMKeyText(key), DMMSWDeskName(gMSWDesks.count - 1)]);
        target = nid; wins = @[];
    }
    NSUInteger ti = [gMSWDesks indexOfObject:@(target)];
    BOOL windowed = DMWindowedLaunchOn();
    long long newest = 0;
    for (NSArray *w in wins) newest = MAX(newest, DMSMAttrTimeOr(w[2], 0));
    NSMutableArray *others = [wins mutableCopy];
    if (mine) [others removeObjectIdenticalTo:mine];
    // (the window as SpringBoard opens it: the launch names the window it opens (act); where that is the app's newest window recorded here under
    //  its own key, the record follows the window -- a launch by app (no scene of its own yet) names the app)
    NSString *rec = mine && !DMSMKeyIsApp(mine[3]) ? mine[3] : key;
    id attrs = nil;
    BOOL written = NO;
    NSMutableArray<NSString *> *left = [NSMutableArray array];
    NSUInteger with = 0;
    if (mine) attrs = DMSMAttrWithLastInteractionTime(mine[2], newest + 1) ?: mine[2];   // (its own place, in front)
    // (an empty desktop -- a new one, or a full desktop's app opening on a new one: as Open Apps as Windows says, a window or full screen, never at
    //  whatever Stage Manager remembered -- the same as the engine's own join, DMSMJoinDesktop: a window remembered from the other orientation came
    //  back 379 x 921 pt in the 649 pt landscape desktop, past the screen's bottom edge, 1.3.2 logic test)
    else if (!others.count) attrs = DMSMJoinAttributes(key, nil, windowed, 0, nil);
    else attrs = DMSMJoinAttributes(key, others.firstObject[2], windowed, (long)newest, others.firstObject[0]);
    if (attrs) {
        NSArray *plan = DMSMPlanFitted(nil, DMMSWSMPlan(others, @[act, attrs, key], left));   // (every window inside the desktop as it is now, SMFit.h)
        NSString *why = nil;
        if (!plan || !DMSMPlanValid(plan, DMSMNewWindowRoles(), &why)) DMSMAPIFail(@"Mac Switcher desktop launch", [NSString stringWithFormat:@"%@: plan refused, context left as it was (%@)", DMSMKeyText(key), why ?: @"a part missing"]);
        else if (!DMSMWritePlan(ctx, plan, act)) DMLog([NSString stringWithFormat:@"[macswitcher] %@: writing the plan failed (a stage of its own)", DMSMKeyText(key)]);
        else { written = YES; with = plan.count - 1; DMSMCtxClearOtherRoles(ctx, plan); }   // (the plan is the desktop's whole stage: a launch from another stage on screen kept its extra windows)
    } else DMLog([NSString stringWithFormat:@"[macswitcher] %@ opens on %@ as Stage Manager opens it (a stage of its own)", DMSMKeyText(key), DMMSWDeskName(ti)]);
    if (written && !windowed && !mine && others.count) DMSMDismissOtherFullScreen(others.firstObject[0], key);
    if (!written && others.count) return YES;   // (refused: Stage Manager's own launch; the tick records where its window lands)
    gMSWWinDesk[rec] = @(target);
    DMLog([NSString stringWithFormat:@"[macswitcher] %@ %@ %@ (%lu window(s) with it)", DMSMKeyText(rec), target != cur ? @"is on" : (mine ? @"comes forward on" : @"joins"), DMMSWDeskName(ti), (unsigned long)with]);
    DMMSWSMLeftOut(left, DMMSWDeskName(ti));
    if (fullNote) DMMSWSMNotice(fullNote);
    if (target != cur) {
        if (!fullNote) DMLog([NSString stringWithFormat:@"[macswitcher] %@ opened: it is on %@, which comes", DMSMKeyText(rec), DMMSWDeskName(ti)]);
        DMMSWSMSwitch(ti, fullNote ? @"desktop full" : @"launch", rec, 0, nil);
    } else DMMSWSave();
    return YES;
}

// ---- SpringBoard's own transitions with the Mac Switcher on (SMDesktop.h DMSMJoinStageAsked: a transition whose layout roles SpringBoard set
//      itself -- the App Switcher's card, Cmd-Tab, Stage Manager's drag from the Dock) ----
// They join the CURRENT desktop, as a launch does (DMMSWSMJoin), and leave none of its windows out while it has room. The engine's own desktop --
// the most recent stage with a window -- can be another desktop's (the one left last, while the current one is empty or behind the Home Screen) or
// only part of the current one (after a remove its windows are in two stages until it is shown): a window opened that way joined the wrong
// desktop, and the 4-window rule left the oldest out. The current desktop's windows here: the ones recorded on it (DMMSWSMDeskWindows) and the
// windows of the stage on screen recorded nowhere yet (the tick records them on that desktop within half a second, DMMSWSMApply), newest first,
// each @[stage, item, attributes, key]. nil = the engine's own desktop: the Mac Switcher off, one desktop, or a stage on screen that holds
// another desktop's window (the records are not settled: the tick makes that desktop current, "came up by itself"; until then the stage on
// screen is the desktop).
static NSArray<NSArray *> *DMMSWSMAskedDeskWindows(void) {
    if (!gMSWOn || !DMSMEngine() || !DMMSWMulti()) return nil;
    NSInteger cur = DMMSWCurId();
    NSMutableArray<NSArray *> *wins = [DMMSWSMDeskWindows(cur) mutableCopy];
    if (DMFrontApp()) {
        NSMutableSet<NSString *> *have = [NSMutableSet set];
        for (NSArray *w in wins) [have addObject:w[3]];
        id front = DMSMFrontStage();
        NSDictionary *m = DMSMStageItemsMap(front);
        for (id it in m) {
            NSString *k = DMSMItemKey(it);
            if (!k.length || DMSMIsMinimized(k) || [have containsObject:k]) continue;
            NSNumber *d = DMMSWSMRecordOf(k);
            if (d && [gMSWDesks containsObject:d] && d.integerValue != cur) {
                DMLog([NSString stringWithFormat:@"[macswitcher] SpringBoard's own transition: the stage on screen holds %@ of %@ -- the desktop on screen joins", DMSMKeyText(k), DMMSWDeskName([gMSWDesks indexOfObject:d])]);
                return nil;
            }
            [have addObject:k];
            [wins addObject:@[front, it, m[it], k]];
        }
        [wins sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
            long long ta = DMSMAttrTimeOr(a[2], 0), tb = DMSMAttrTimeOr(b[2], 0);
            return ta > tb ? NSOrderedAscending : (ta < tb ? NSOrderedDescending : NSOrderedSame);
        }];
    }
    return wins;
}
// SpringBoard's own transition joined the current desktop (DMSMJoinStageAsked wrote it): its new windows are recorded there at once, as a launch's
// are (the tick would within half a second), and the windows a full desktop left out (DMMSWSMAtCap: MinimizeOldest) are minimized and said.
// left: nil or empty when none. (The Mac Switcher off: nothing -- DMMSWSMLeftOut only acts with it on.)
static void DMMSWSMAskedJoined(NSArray<NSString *> *fresh, NSArray<NSString *> *left) {
    if (gMSWOn && DMSMEngine() && DMMSWMulti()) {
        NSInteger cur = DMMSWCurId();
        NSMutableArray *names = [NSMutableArray array];
        for (NSString *k in fresh) { gMSWWinDesk[k] = @(cur); [names addObject:DMSMKeyText(k)]; }   // (each window by its key -- an app key where windows are told apart by app)
        DM_FEATURE_MARK("mac-switcher-sm-asked-joins-current");
        DMLog([NSString stringWithFormat:@"[macswitcher] %@ joined %@ (SpringBoard's own transition)", [names componentsJoinedByString:@", "], DMMSWDeskName(gMSWCur)]);
        DMMSWSave();
    }
    DMMSWSMLeftOut(left, DMMSWMulti() ? DMMSWDeskName(gMSWCur) : nil);
}
// The current desktop is empty (the Home Screen) and SpringBoard's own transition shows a stage of windows of no other desktop (a minimized
// window's card, an app dragged from the Dock): left as SpringBoard built it -- that stage IS the current desktop now. Its windows are recorded on
// it and are no longer minimized ones; without this the tick took a minimized window's old record for "its desktop came up by itself" and moved
// to that desktop, where a launch brings a minimized window to the CURRENT one (DMMSWSMJoin).
static void DMMSWSMAskedOnEmpty(NSArray<NSString *> *keys) {   // (keys: the windows SpringBoard's transition shows)
    if (!gMSWOn || !DMSMEngine() || !DMMSWMulti() || !keys.count) return;
    NSInteger cur = DMMSWCurId();
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *k in keys) { gMSWWinDesk[k] = @(cur); DMSMSetMinimized(k, NO); [names addObject:DMSMKeyText(k)]; }
    DMLog([NSString stringWithFormat:@"[macswitcher] %@ opened on %@, which had no window (SpringBoard's own transition)", [names componentsJoinedByString:@", "], DMMSWDeskName(gMSWCur)]);
    DMMSWSave();
}
// SpringBoard's own transition would leave windows of a FULL desktop out (DMSMDeskJoinPlan keeps the newest, room for the new ones): what
// DMMSWSMAtCap says, as for a launch. NewDesktop: the new windows open on a new desktop of their own -- the context rewritten as that desktop's
// whole stage (every other role emptied: nothing of the full desktop comes with them), which the Mac Switcher follows as current, as when a stage
// comes up by itself (SpringBoard's own animation shows it: no slide) -- YES. MinimizeOldest: NO -- the join goes on and DMMSWSMAskedJoined
// minimizes and says the windows it leaves out. Also NO when anything is refused (then the join as planned). asked: SpringBoard's roles, @[role,
// entity] each (put back if a write fails); askedEntity: key (and bundle) -> its entity; fresh / front: the new windows' keys (SMDesktop.h: by app
// when the decision compared apps) and the one SpringBoard is activating among them.
static BOOL DMMSWSMAskedFull(id ctx, NSArray<NSArray *> *asked, NSArray<NSString *> *fresh, NSDictionary<NSString *, id> *askedEntity, id identity, NSString *front) {
    if (!gMSWOn || !DMSMEngine() || !DMMSWDesktopsHere() || !fresh.count || !gMSWDesks.count || gMSWSwitching) return NO;
    BOOL minimizedOne = !DMMSWMulti() && fresh.count == 1 && DMSMIsMinimized(fresh.firstObject);
    if (DMMSWSMAtCap(DMMSWSMCapOpen, minimizedOne) != DMMSWSMCapNewDesktop) return NO;
    BOOL windowed = DMWindowedLaunchOn();
    NSMutableArray<NSString *> *order = [fresh mutableCopy];   // (the window in front last: the newest interaction time)
    if (front && [order containsObject:front]) { [order removeObject:front]; [order addObject:front]; }
    NSMutableArray<NSArray *> *plan = [NSMutableArray array];
    NSMutableSet<NSNumber *> *used = [NSMutableSet set];
    id frontEntity = nil;
    long t = 0;
    for (NSString *b in order) {
        id e = askedEntity[b] ?: DMSMNewEntity(DMSMKeyBundle(b), identity);
        id a = DMSMJoinAttributes(b, nil, windowed, t++, nil);   // (as on an empty desktop: its own last window, else the default one; full screen as Open Apps as Windows says)
        long long r = DMSMFirstFreeRole(used);
        if (!e || !a || !r) { DMLog([NSString stringWithFormat:@"[macswitcher] %@ could not be planned for a new desktop: it joins the full desktop instead", DMSMKeyText(b)]); return NO; }
        [plan addObject:@[e, @(r), a]];
        frontEntity = e;
    }
    NSArray<NSArray *> *toWrite = DMSMPlanFitted(identity, plan);
    NSString *bad = nil;
    if (!DMSMPlanValid(toWrite, DMSMNewWindowRoles(), &bad)) { DMSMAPIFail(@"Mac Switcher: a full desktop's new desktop", [NSString stringWithFormat:@"plan refused, it joins the full desktop instead (%@)", bad]); return NO; }
    if (!DMSMCtxCanWrite(ctx)) return NO;
    SEL setE = NSSelectorFromString(@"setEntity:forLayoutRole:");
    void (^putBack)(void) = ^{ for (NSArray *a in asked) @try { ((void (*)(id, SEL, id, long long))objc_msgSend)(ctx, setE, a[1], [a[0] longLongValue]); } @catch (id y) {} };
    @try { for (NSArray *a in asked) ((void (*)(id, SEL, id, long long))objc_msgSend)(ctx, setE, nil, [a[0] longLongValue]); }
    @catch (NSException *x) { putBack(); DMSMAPIFail(@"Mac Switcher: a full desktop's new desktop", [NSString stringWithFormat:@"unsetting SpringBoard's roles: %@ (put back)", x.reason ?: @"exception"]); return NO; }
    if (!DMSMWritePlan(ctx, toWrite, frontEntity)) { putBack(); DMLog(@"[macswitcher] writing a full desktop's new desktop failed: SpringBoard's roles put back, it joins the full desktop instead"); return NO; }
    DMSMCtxClearOtherRoles(ctx, toWrite);   // (a whole stage of its own: the full desktop's windows stay in theirs)
    // (the records: the new desktop holds the new windows -- with one desktop, Desktop 1 is recorded first, as at the first "+")
    if (!DMMSWMulti()) DMMSWSMRecordFirst();
    NSInteger fromId = DMMSWCurId(), nid = 2;
    NSString *fromName = DMMSWDeskName(gMSWCur);
    while ([gMSWDesks containsObject:@(nid)]) nid++;
    [gMSWDesks addObject:@(nid)];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSString *b in fresh) { gMSWWinDesk[b] = @(nid); DMSMSetMinimized(b, NO); [names addObject:DMMSWAppName(DMSMKeyBundle(b))]; }
    if (!gMSWFit) gMSWFit = [NSMutableDictionary dictionary];   // (the left desktop's Fit arrangement kept, as when a stage comes up by itself)
    gMSWFit[[@(fromId) stringValue]] = @{@"smslots": [gSMFitSlots copy] ?: @{}, @"smfree": [gSMFreeWindows allObjects] ?: @[]};
    gMSWCur = gMSWDesks.count - 1;
    DMMSWSMArrive(nid);
    gMSWSMQuietUntil = CACurrentMediaTime() + 1.0;   // (the tick lets SpringBoard's transition land first)
    DMMSWSave();
    gMSWSMDiag[2] += (unsigned)fresh.count;   // (iPadOS 17 diagnostics)
    DM_FEATURE_MARK("mac-switcher-sm-asked-full-new-desktop");
    DMLog([NSString stringWithFormat:@"[macswitcher] %@ is full: %@ open%@ on a new desktop, %@ (SpringBoard's own transition)", fromName, [names componentsJoinedByString:@", "], fresh.count == 1 ? @"s" : @"", DMMSWDeskName(gMSWCur)]);
    DMMSWSMNotice([NSString stringWithFormat:@"%@: %@ opened on %@.", DMMSWSMHoldsUpTo(fromName), [names componentsJoinedByString:@", "], DMMSWDeskName(gMSWCur)]);
    return YES;
}

// ---- the view's thumbnails: the current desktop's windows are Stage Manager's window cards (our title bar on top of each), back to front ----
static NSArray *DMMSWSMCollect(UIView *root) {
    NSMutableArray<DMMSWTile *> *out = [NSMutableArray array];
    NSDictionary *m = DMFrontApp() ? DMSMStageItemsMap(DMSMFrontStage()) : nil;   // (the Home Screen: the desktop's stage is hidden, no window shows)
    NSMutableDictionary<NSString *, NSNumber *> *order = [NSMutableDictionary dictionary];   // (window key -> its interaction time)
    for (id it in m) { NSString *k = DMSMItemKey(it); if (k.length) order[k] = @(DMSMAttrTimeOr(m[it], 0)); }
    NSMutableArray<UIView *> *cards = [NSMutableArray array];
    for (UIView *card in DMMSWSMVisibleCards()) if (order[DMSMCardKey(card)]) [cards addObject:card];   // (not in the front stage: a card of another stage on its way out)
    [cards sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        long long ta = order[DMSMCardKey(a)].longLongValue, tb = order[DMSMCardKey(b)].longLongValue;
        return ta < tb ? NSOrderedAscending : (ta > tb ? NSOrderedDescending : NSOrderedSame);
    }];
    for (UIView *card in cards) {
        NSString *k = DMSMCardKey(card);
        DMMSWTile *t = [DMMSWTile new];
        BOOL full = DMSMCardIsFullSize(card);
        // (a tile names its window by its KEY (MacSwitcher.h t.bundle): a pick brings that very window forward, a drag moves that window only --
        //  two windows of one app are two tiles; the title is its app's name)
        t.kind = full ? DMMSWKindFullScreen : DMMSWKindStage; t.source = card; t.title = DMMSWAppName(DMSMKeyBundle(k)); t.bundle = k;
        t.inner = [[UIView alloc] initWithFrame:root.bounds];
        t.inner.userInteractionEnabled = NO;
        CGRect r = CGRectNull;
        if (!DMMSWPortalInPlace(card, root, t.inner, &r) || CGRectIsNull(r) || r.size.width < 20.0 || r.size.height < 20.0) {
            for (UIView *p in [t.inner.subviews copy]) { [gMSWPortals removeObjectIdenticalTo:p]; DMMSWPortalLetGo(p); }
            continue;
        }
        if (!full && DMSMCardHasBar(card)) r = CGRectUnion(r, [card convertRect:CGRectMake(0, -kSMBarH, card.bounds.size.width, kSMBarH) toView:root]);   // (the title bar is part of the window: drawn by the portal, it sits above the card)
        t.sourceRect = r;
        [out addObject:t];
    }
    if (gNativeLayer && !gNativeLayer.hidden)   // (Finder's windows over them, as in MacSwitcher.h's own collect)
        for (DMNativeWindow *w in [gNativeWindows copy]) {
            if (w.hidden || !w.superview || w.alpha < 0.05) continue;
            DMMSWTile *t = [DMMSWTile new];
            t.kind = DMMSWKindNative; t.source = w; t.title = w.title.length ? w.title : (w.appName ?: @"Window"); t.native = w;
            t.inner = [[UIView alloc] initWithFrame:root.bounds];
            t.inner.userInteractionEnabled = NO;
            CGRect r = CGRectNull;
            if (!DMMSWPortalInPlace(w, root, t.inner, &r) || CGRectIsNull(r) || r.size.width < 20.0 || r.size.height < 20.0) {
                for (UIView *p in [t.inner.subviews copy]) { [gMSWPortals removeObjectIdenticalTo:p]; DMMSWPortalLetGo(p); }
                continue;
            }
            t.sourceRect = r;
            [out addObject:t];
        }
    return out;
}

// The Home Screen as last left (gMSWSMHomeShot) as a picture of its own, for behind a desktop's windows: a new view showing the same contents (a
// picture view is in one place at a time, and an empty desktop's slide picture is the original). nil when it has no contents to share (a picture
// drawn by its sublayers) or the screen has another shape now: then the wallpaper, as before.
static CALayer *DMMSWSMHomeBackdropSource(CGRect b) {   // (the layer holding the Home Screen picture's contents, nil when none to share)
    UIView *h = gMSWSMHomeShot;
    if (!h || !CGSizeEqualToSize(h.bounds.size, b.size)) return nil;
    if (h.layer.contents) return h.layer;
    for (CALayer *l in h.layer.sublayers) if (l.contents && CGRectEqualToRect(CGRectIntegral(l.frame), CGRectIntegral(h.layer.bounds))) return l;
    return nil;
}
static BOOL DMMSWSMHomeBackdropOK(CGRect b) { return DMMSWSMHomeBackdropSource(b) != nil; }
static UIView *DMMSWSMHomeBackdrop(CGRect b) {
    UIView *h = gMSWSMHomeShot;
    CALayer *src = DMMSWSMHomeBackdropSource(b);
    if (!src) return nil;
    UIView *v = [[UIView alloc] initWithFrame:b];
    v.userInteractionEnabled = NO;
    v.layer.contents = src.contents; v.layer.contentsRect = src.contentsRect; v.layer.contentsGravity = src.contentsGravity; v.layer.contentsScale = src.contentsScale;
    id slot = objc_getAssociatedObject(h, kMSWSlotKey);   // (an image slot of the render server's: kept alive while any view shows it, MacSwitcher.h)
    if (slot) objc_setAssociatedObject(v, kMSWSlotKey, slot, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return v;
}
// An away desktop drawn from its parts (its picture is stale: windows moved onto it by a remove, or one closed while away): what is behind the
// windows -- the Home Screen as last left (since 1.3.5 every Stage Manager desktop has the Home Screen behind its windows, sm-desktop), else the
// wallpaper -- and its windows' pictures at their places, back to front.
static UIView *DMMSWSMComposedDesktop(NSInteger did, CGRect b) {
    UIView *c = [[UIView alloc] initWithFrame:b];
    c.backgroundColor = [UIColor blackColor];
    c.clipsToBounds = YES;
    DMMSWWallLazy();   // (the wallpaper, read once: right after a respring nothing had asked for it yet -- a drawn desktop had nothing behind its windows)
    UIView *home = DMMSWSMHomeBackdrop(b);
    if (home) { [c addSubview:home]; DM_FEATURE_MARK("mac-switcher-sm-home-behind"); }
    else {
        if (gMSWWallContents) {
            UIView *wv = [UIView new];
            wv.layer.contents = gMSWWallContents; wv.layer.contentsRect = gMSWWallContentsRect; wv.layer.contentsGravity = gMSWWallGravity ?: kCAGravityResize;
            wv.bounds = gMSWWallBounds; wv.center = gMSWWallCenter; wv.transform = gMSWWallTransform;
            [c addSubview:wv];
        }
        // (no picture of the Home Screen to put behind the windows -- since a respring, or let go under memory pressure --: the Home Screen, the
        //  Dock and the menu bar come in live on the slide, under the windows' pictures (MacSwitcher.h DMMSWSlShared, tag 0x4D53 below), as on an
        //  empty desktop without that picture and on the other engines' desktops drawn from their parts (DMMSWDeskPicture). They were missing in
        //  the slide and popped in at the reveal, 1.4.1 logic test; more often since H-2 drew every such desktop. Debug /tmp/msw-sm-noshared = before.)
        if (!DMTestFlag("/tmp/msw-sm-noshared")) {
            objc_setAssociatedObject(c, kMSWSharedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(c, kMSWDrawnKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);   // (kept after a window lands on it: asked again at each slide)
        }
    }
    NSUInteger n = 0, icons = 0;
    for (NSArray *w in [DMMSWSMDeskWindows(did) reverseObjectEnumerator]) {
        UIView *pic = gMSWWinShots[w[3]];
        NSString *f = gMSWWinFrame[w[3]];
        if (!f) continue;
        if (pic) {
            [pic removeFromSuperview];
            pic.transform = CGAffineTransformIdentity;
            pic.frame = CGRectFromString(f);
            pic.tag = 0x4D53;   // (a window's picture: over the shared windows' portals)
            [c addSubview:pic];
            n++;
            continue;
        }
        // (no picture kept: the window's place, a dark card with its app's icon -- what is on that desktop, at a glance)
        CGRect r = CGRectFromString(f);
        UIView *card = [[UIView alloc] initWithFrame:r];
        card.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.92];
        card.layer.cornerRadius = 10.0; card.layer.cornerCurve = kCACornerCurveContinuous;
        card.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.18].CGColor; card.layer.borderWidth = 1.0;
        UIImage *icon = DMAppIcon(DMSMKeyBundle(w[3]));
        if (icon) {
            CGFloat side = MIN(96.0, MIN(r.size.width, r.size.height) * 0.4);
            UIImageView *iv = [[UIImageView alloc] initWithImage:icon];
            iv.frame = CGRectMake((r.size.width - side) / 2.0, (r.size.height - side) / 2.0, side, side);
            [card addSubview:iv];
        }
        card.tag = 0x4D53;   // (its place: over the shared windows' portals too)
        [c addSubview:card];
        icons++;
    }
    DMLog([NSString stringWithFormat:@"[macswitcher] desktop %ld's thumbnail drawn from %@, %lu window pictures and %lu app icons", (long)did,
        home ? @"the Home Screen" : [NSString stringWithFormat:@"%@ (the Home Screen, the Dock and the menu bar live on a slide)", gMSWWallContents ? @"its wallpaper" : @"nothing behind"], (unsigned long)n, (unsigned long)icons]);
    return c;
}

#if DEBUG
// ---- debug triggers: mswsm_desks (every desktop's windows as Stage Manager has them), mswsm_note (the notice), mswsm_cap (the full-desktop answers) ----
static BOOL DMMSWSMTrigger(NSString *cmd) {
    if ([cmd isEqualToString:@"mswsm_desks"]) {
        NSMutableString *o = [NSMutableString stringWithFormat:@"[macswitcher] SM desktops %@ current %@ (id %ld), switching %d, front app %@, minimized %@",
            [gMSWDesks componentsJoinedByString:@","], DMMSWDeskName(gMSWCur), (long)DMMSWCurId(), gMSWSwitching, [DMFrontApp() bundleIdentifier] ?: @"-", [[DMSMMinimizedSet() allObjects] componentsJoinedByString:@","] ?: @"-"];
        for (NSNumber *d in gMSWDesks) {
            NSMutableArray *names = [NSMutableArray array];
            for (NSArray *w in DMMSWSMDeskWindows(d.integerValue)) [names addObject:[NSString stringWithFormat:@"%@ (t %lld, policy %ld, stage %p)", DMSMKeyText(w[3]), DMSMAttrTimeOr(w[2], 0), DMSMPolicyOf(w[2]), w[0]]];
            [o appendFormat:@"\n  %@: %@", DMMSWDeskName([gMSWDesks indexOfObject:d]), names.count ? [names componentsJoinedByString:@", "] : @"no window"];
        }
        for (NSString *b in gMSWWinDesk) [o appendFormat:@"\n  record %@ -> %@", DMSMKeyText(b), gMSWWinDesk[b]];
        NSUInteger k = 0;
        for (id al in DMSMRecentStages()) {
            if (k++ >= 8) break;
            NSMutableArray *bs = [NSMutableArray array];
            for (id it in DMSMStageItemsMap(al)) [bs addObject:[NSString stringWithFormat:@"%@/%lld", DMSMKeyText(DMSMItemKey(it)), DMSMRoleOr(al, it, -1)]];
            [o appendFormat:@"\n  stage %p%@: %@", al, DMSMIsMainIdentity(DMSMStageDisplayIdentity(al)) ? @"" : @" (other display)", [bs componentsJoinedByString:@", "]];
        }
        DMLog(o);
    }
    else if ([cmd hasPrefix:@"mswsm_watch_"]) {   // mswsm_watch_<ms>: the window cards as drawn, every frame for <ms>, each change logged (I-5: what shows after a switch)
        __block int left = MAX(1, MIN(600, [[cmd substringFromIndex:12] intValue] * 60 / 1000));
        __block NSString *before = nil;
        CFTimeInterval t0 = CACurrentMediaTime();
        __block void (^step)(void);
        void (^s)(void) = ^{
            NSString *now = DMMSWSMCardsDrawn();
            if (![now isEqualToString:before]) DMLog([NSString stringWithFormat:@"[mswwatch] +%.0f ms: %@", (CACurrentMediaTime() - t0) * 1000, now.length ? now : @"-"]);
            before = now;
            if (--left > 0) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NSEC_PER_SEC / 60)), dispatch_get_main_queue(), step);
            else { DMLog([NSString stringWithFormat:@"[mswwatch] done after %.0f ms", (CACurrentMediaTime() - t0) * 1000]); step = nil; }
        };
        step = s;
        dispatch_async(dispatch_get_main_queue(), step);
    }
    else if ([cmd hasPrefix:@"mswsm_note"]) DMMSWSMNotice([NSString stringWithFormat:@"%@: Clock was minimized.", DMMSWSMHoldsUpTo(@"Desktop 2")]);
    else if ([cmd isEqualToString:@"mswsm_cap"])   // (the full-desktop answers, DMMSWSMAtCap: 0 a new desktop, 1 the oldest minimized, 2 refused)
        DMLog([NSString stringWithFormat:@"[macswitcher] a desktop holds up to %lu windows; full: open %d (minimized, one desktop %d), merge %d, drop %d", (unsigned long)DMSMWindowCap(),
            DMMSWSMAtCap(DMMSWSMCapOpen, NO), DMMSWSMAtCap(DMMSWSMCapOpen, YES), DMMSWSMAtCap(DMMSWSMCapMerge, NO), DMMSWSMAtCap(DMMSWSMCapDrop, NO)]);
    else if ([cmd isEqualToString:@"mswsm_pics"] || [cmd isEqualToString:@"mswsm_drop"]) {   // the pictures kept (and mswsm_drop: all let go, to measure their memory)
        DMLog([NSString stringWithFormat:@"[macswitcher] pictures: %lu desktops (%@), %lu windows, Home %d", (unsigned long)gMSWShots.count, [[gMSWShots allKeys] componentsJoinedByString:@","], (unsigned long)gMSWWinShots.count, gMSWSMHomeShot != nil]);
        if ([cmd isEqualToString:@"mswsm_drop"]) { [gMSWShots removeAllObjects]; [gMSWShotSet removeAllObjects]; [gMSWWinShots removeAllObjects]; gMSWSMHomeShot = nil; DMLog(@"[macswitcher] pictures: all let go"); }
    }
    else return NO;
    return YES;
}
#endif
