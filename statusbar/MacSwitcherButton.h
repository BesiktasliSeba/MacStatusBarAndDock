// MacSwitcherButton.h -- the Home button with the Mac Switcher on (iPads with a Home button, like the iPad Pro 9.7"), included into StatusBar.x
// right after MacSwitcher.h. The owner's rule: iPadOS's own App Switcher never appears while the Mac Switcher is on, and Home stays Home.
//  - A DOUBLE press opens the Mac Switcher (or closes it when it is open) instead of iPadOS's App Switcher: SpringBoard's own double-press handler
//    (SBUIController), taken over only while the Mac Switcher is on, nothing is over the screen (Lock Screen, Control Center) and iPadOS's
//    switcher is not already showing or asked for from the Apple menu (a press then closes it, as always).
//  - A SINGLE press while the view is open closes the view first; SpringBoard then does what it always does (the Home Screen).
//  - Home by any other way while the view is open (the Home gesture, an app quitting): the view goes too (DMMSWHomeTick), as iPadOS's switcher
//    goes when the Home Screen comes.
// Every hook is installed only on a method whose exact type encoding matches (DMMSWHasMethod), has a re-entry guard, and asks the Settings switch
// at each press (debug builds also the test flag /tmp/msb-noswitcher, as the gestures do).

static BOOL DMMSWButtonOff(void) { return !gMSWOn || DMTestFlag("/tmp/msb-noswitcher"); }
static NSString *gMSWDiagButton = @"-";   // (untested iPadOS: which Home button handlers were hooked, for the StatusBar diagnostic record)
static CFTimeInterval gMSWDoubleAt = 0;   // (the last double press we took: a single press right after it never closes the view it opens)
// A double press: the Mac Switcher instead (YES), or SpringBoard's own (NO).
static BOOL DMMSWHomeDoubleTakesOver(void) {
    static BOOL inside = NO;
    if (inside || DMMSWButtonOff() || DMCoverSheetShown() || DMControlCenterActive() || DMSwitcherVisible() || DMMSWStockOnce()) return NO;   // (iPadOS's switcher up or asked for from the menu: its press)
    inside = YES;
    gMSWDoubleAt = CACurrentMediaTime();
    DM_FEATURE_MARK("mac-switcher-home-button");
    DMLog(@"[macswitcher] Home button double press: the Mac Switcher, not iPadOS's App Switcher");
    dispatch_async(dispatch_get_main_queue(), ^{ DMMSWOpen(@"Home button double press"); });   // (after SpringBoard's button handling: a toggle)
    inside = NO;
    return YES;
}
// A single press: the open view closes first, then SpringBoard's own press (Home).
// (gMSWOwnHomeAt: the Home Screen asked for by the Mac Switcher itself while its view stays open -- a full-screen app dragged onto another desktop
//  goes Home through the same simulated press, MacSwitcher.h DMMSWOwnHome; that press is not the user's and does not close the view)
static void DMMSWHomeSingle(void) {
    static BOOL inside = NO;
    if (inside || DMMSWButtonOff() || !DMMSWIsOpen() || gMSWClosing || CACurrentMediaTime() - gMSWDoubleAt < 0.6 || CACurrentMediaTime() - gMSWOwnHomeAt < 1.0) return;
    inside = YES;
    DMLog(@"[macswitcher] Home button: the view closes (the Home press goes on)");
    DMMSWClose(nil, NO);
    inside = NO;
}

// ---- the hooks: one replacement per signature the handler has had (iPadOS 15: ...WithSourceType:; 16: ...ForWindowScene:(withSourceType:)) ----
static BOOL (*o_MSWDoubleSceneSource)(id, SEL, id, long long);
static BOOL DMMSWDoubleSceneSource(id self, SEL _cmd, id scene, long long source) { return DMMSWHomeDoubleTakesOver() ? YES : o_MSWDoubleSceneSource(self, _cmd, scene, source); }
static BOOL (*o_MSWDoubleScene)(id, SEL, id);
static BOOL DMMSWDoubleScene(id self, SEL _cmd, id scene) { return DMMSWHomeDoubleTakesOver() ? YES : o_MSWDoubleScene(self, _cmd, scene); }
static BOOL (*o_MSWDoubleSource)(id, SEL, long long);
static BOOL DMMSWDoubleSource(id self, SEL _cmd, long long source) { return DMMSWHomeDoubleTakesOver() ? YES : o_MSWDoubleSource(self, _cmd, source); }
static BOOL (*o_MSWDoublePlain)(id, SEL);
static BOOL DMMSWDoublePlain(id self, SEL _cmd) { return DMMSWHomeDoubleTakesOver() ? YES : o_MSWDoublePlain(self, _cmd); }
static BOOL (*o_MSWSingleSceneSource)(id, SEL, id, long long);
static BOOL DMMSWSingleSceneSource(id self, SEL _cmd, id scene, long long source) { DMMSWHomeSingle(); return o_MSWSingleSceneSource(self, _cmd, scene, source); }
static BOOL (*o_MSWSingleScene)(id, SEL, id);
static BOOL DMMSWSingleScene(id self, SEL _cmd, id scene) { DMMSWHomeSingle(); return o_MSWSingleScene(self, _cmd, scene); }
static BOOL (*o_MSWSingleSource)(id, SEL, long long);
static BOOL DMMSWSingleSource(id self, SEL _cmd, long long source) { DMMSWHomeSingle(); return o_MSWSingleSource(self, _cmd, source); }
// (iPadOS 16.7.7: the source type is unsigned, B@:@Q -- read on the iPad 2)
static BOOL (*o_MSWDoubleSceneSourceU)(id, SEL, id, unsigned long long);
static BOOL DMMSWDoubleSceneSourceU(id self, SEL _cmd, id scene, unsigned long long source) { return DMMSWHomeDoubleTakesOver() ? YES : o_MSWDoubleSceneSourceU(self, _cmd, scene, source); }
static BOOL (*o_MSWSingleSceneSourceU)(id, SEL, id, unsigned long long);
static BOOL DMMSWSingleSceneSourceU(id self, SEL _cmd, id scene, unsigned long long source) { DMMSWHomeSingle(); return o_MSWSingleSceneSourceU(self, _cmd, scene, source); }
// (iPadOS 15.6.1: the single press is -handleHomeButtonSinglePressUpWithSourceType: with an unsigned source, B@:Q -- read on the M1; our own
//  Minimize reaches it through -[SpringBoard _simulateHomeButtonPressWithCompletion:])
static BOOL (*o_MSWSingleSourceU)(id, SEL, unsigned long long);
static BOOL DMMSWSingleSourceU(id self, SEL _cmd, unsigned long long source) { DMMSWHomeSingle(); return o_MSWSingleSourceU(self, _cmd, source); }

// Installed once, when the Mac Switcher is first switched on (off: every replacement goes straight to SpringBoard's own). Each found handler is
// hooked (a variant can forward to another: the guards make that one action); none found = the presses stay iPadOS's own, logged.
static void DMMSWHookHomeButton(void) {
    static BOOL done = NO;
    if (done || !gMSWOn) return;
    done = YES;
    Class ui = objc_getClass("SBUIController");
    typedef struct { const char *sel; const char *types; IMP repl; IMP *orig; } DMMSWButtonHook;
    DMMSWButtonHook hooks[] = {
        { "handleHomeButtonDoublePressDownForWindowScene:withSourceType:", "B@:@q", (IMP)DMMSWDoubleSceneSource, (IMP *)&o_MSWDoubleSceneSource },
        { "handleHomeButtonDoublePressDownForWindowScene:withSourceType:", "B@:@Q", (IMP)DMMSWDoubleSceneSourceU, (IMP *)&o_MSWDoubleSceneSourceU },
        { "handleHomeButtonDoublePressDownForWindowScene:", "B@:@", (IMP)DMMSWDoubleScene, (IMP *)&o_MSWDoubleScene },
        { "handleHomeButtonDoublePressDownWithSourceType:", "B@:q", (IMP)DMMSWDoubleSource, (IMP *)&o_MSWDoubleSource },
        { "handleHomeButtonDoublePressDown", "B@:", (IMP)DMMSWDoublePlain, (IMP *)&o_MSWDoublePlain },
        { "handleHomeButtonSinglePressUpForWindowScene:withSourceType:", "B@:@q", (IMP)DMMSWSingleSceneSource, (IMP *)&o_MSWSingleSceneSource },
        { "handleHomeButtonSinglePressUpForWindowScene:withSourceType:", "B@:@Q", (IMP)DMMSWSingleSceneSourceU, (IMP *)&o_MSWSingleSceneSourceU },
        { "handleHomeButtonSinglePressUpForWindowScene:", "B@:@", (IMP)DMMSWSingleScene, (IMP *)&o_MSWSingleScene },
        { "handleHomeButtonSinglePressUpWithSourceType:", "B@:q", (IMP)DMMSWSingleSource, (IMP *)&o_MSWSingleSource },
        { "handleHomeButtonSinglePressUpWithSourceType:", "B@:Q", (IMP)DMMSWSingleSourceU, (IMP *)&o_MSWSingleSourceU },
    };
    NSMutableArray *in = [NSMutableArray array], *other = [NSMutableArray array];
    for (size_t i = 0; i < sizeof(hooks) / sizeof(hooks[0]); i++) {
        NSString *sel = @(hooks[i].sel);
        Method m = ui ? class_getInstanceMethod(ui, NSSelectorFromString(sel)) : NULL;
        if (!m) continue;
        if (!DMMSWHasMethod(ui, sel, @(hooks[i].types))) { [other addObject:sel]; continue; }
        MSHookMessageEx(ui, NSSelectorFromString(sel), hooks[i].repl, hooks[i].orig);
        [in addObject:sel];
    }
    [other removeObjectsInArray:in];   // (the same selector is listed once per signature it has had)
    other = [[NSOrderedSet orderedSetWithArray:other].array mutableCopy];
    for (NSUInteger i = 0; i < other.count; i++) other[i] = [NSString stringWithFormat:@"%@ (%s)", other[i], method_getTypeEncoding(class_getInstanceMethod(ui, NSSelectorFromString(other[i])))];
    {   // (diagnostics: each hooked handler by its short name -- "double", "doubleScene", ... -- and how many were left alone)
        NSMutableArray *shortNames = [NSMutableArray array];
        for (NSString *sel in in) [shortNames addObject:[[[sel stringByReplacingOccurrencesOfString:@"handleHomeButton" withString:@""] stringByReplacingOccurrencesOfString:@"PressDown" withString:@""]
                                                         stringByReplacingOccurrencesOfString:@"PressUp" withString:@""]];
        gMSWDiagButton = [NSString stringWithFormat:@"%@/other%lu", shortNames.count ? [shortNames componentsJoinedByString:@","] : @"none", (unsigned long)other.count];
    }
    DMLog([NSString stringWithFormat:@"[macswitcher] Home button: %@%@", in.count ? [NSString stringWithFormat:@"hooked %@", [in componentsJoinedByString:@", "]] : @"no handler of the expected kind (the presses stay iPadOS's own)",
        other.count ? [NSString stringWithFormat:@"; left alone (another signature): %@", [other componentsJoinedByString:@", "]] : @""]);
}

// The tick (StatusBar.x, after DMMSWTick): the view goes when the Home Screen comes by any other way (the Home gesture, the app quitting) -- it was
// opened over an app that is no longer in front. Read every tick only while the view is open.
static void DMMSWHomeTick(void) {
    static BOOL wasOpen = NO;
    static NSString *frontAtOpen = nil;
    BOOL open = DMMSWIsOpen() && !gMSWClosing;
    if (!open) { wasOpen = NO; frontAtOpen = nil; return; }
    NSString *front = [DMFrontApp() bundleIdentifier];
    if (!wasOpen) { wasOpen = YES; frontAtOpen = front; return; }
    if (CACurrentMediaTime() - gMSWOwnHomeAt < 3.0) { frontAtOpen = front; return; }   // (the Mac Switcher sent the app Home itself: the view stays)
    if (frontAtOpen.length && !front.length && !gMSWSwitching) {
        DMLog([NSString stringWithFormat:@"[macswitcher] the Home Screen came (%@ is no longer in front): the view closes", frontAtOpen]);
        DMMSWClose(nil, NO);
    }
}
