// SMSpotKeyboard.h -- Spotlight over the windows keeps its keyboard (1.7.0, the Stage Manager engine). Included by StatusBar.x after SMDesktop.h;
// installed by the engine's start-up self-check (optional: a method missing or of another signature = Apple's way, the engine runs).
//   Found on the 17.5 (17.5.1, TrollPad 1.3, no hardware keyboard; 29 Oct): Spotlight brought up over a window showed its on-screen keyboard and lost it
//   as its presentation ended; a tap in the search field did not bring it back, so nothing could be typed (a hardware keyboard typed). The same with
//   Apple's Stage Manager on its own (our engine's start-up left out); at Home and with Aerial the keyboard stays. Read on the device (the keyboard
//   arbiter's state traced while Spotlight opened, and each step's code):
//    - the keyboard arbiter (KeyboardArbiter.framework, in SpringBoard) works out the keyboard focus from -_activeHandleForFocusEvaluation: the client
//      that last asked for focus (_focusRequestedHandle), else the one last activated. Spotlight's search field asked and had the keyboard; as the
//      presentation ended the window's app (Clock) asked again and the focus went to it, whose empty keyboard state replaced Spotlight's;
//    - that request was SpringBoard's own: -[SBWorkspaceKeyboardFocusController userFocusRequestForScene:reason:completion:] (what a tap in an app's
//      window asks), passed on by SpringBoard's arbiter client (-userSelectedProcessIdentifier:withSceneIdentity:onCompletion:) for Clock's pid;
//    - and it came from -[SBMainSwitcherControllerCoordinator _focusNewlyAddedApplicationIfNeededTransitioningFromLayoutState:toLayoutState:
//      windowScene:] at the end of the switcher transition Spotlight's presentation runs (SBTransientOverlayPresentWorkspaceTransaction, the stage as it
//      was): with Stage Manager's windowing on and the stage's app layout the same before and after, it hands the user focus to the stage's front
//      window (the first of its -zOrderedItems) -- while Spotlight shows its keyboard above it. At Home, and with Aerial, SpringBoard's stage holds no
//      app, so nothing is handed the focus there.
//   (The coordinator's -noteKeyboardIsForMedusaWithOwningScene: / -noteKeyboardIsNotForMedusa, the first idea, only change the scene handle it watches
//    and the keyboard's Home-affordance assertion -- their one caller is SBMedusaHostedKeyboardWindowController: they decide nothing about the focus.)
//   So while Spotlight's overlay is up over our engine's windows and is not being dismissed, a transition on Spotlight's screen that leaves the stage as
//   it was does not hand its front window the focus: Spotlight keeps the keyboard. Everything else stays Apple's: a window added or the stage changed (a
//   result opened), Spotlight's own dismissal (its transition hands the window in front its focus back, so it types again at once), every other
//   overlay, and another screen's stage (an external display's: the switcher hands its front window the focus there as before, review of 1.7.0).
//   Debug /tmp/msb-sm-nospotkb: Apple's way.
#pragma once

static unsigned gSMSpotKept;   // (how often Spotlight kept its keyboard over the windows: the diagnostics record)
// SpringBoard is dismissing a transient overlay right now (its workspace's current transaction): its own dismissal, or the one an app's transition
// asks for while the overlay is up (a result opened, an app already in the stage too: 17.5.1 runs that as ...DismissToApps..., a sibling class).
static BOOL DMSMOverlayGoing(void) {
    id ws = DMCall(objc_getClass("SBMainWorkspace"), @"sharedInstance");
    SEL cur = NSSelectorFromString(@"currentTransaction");
    id tx = ws && DMSMSigOK(ws, cur, DMSMSigObj(), "currentTransaction") ? ((id (*)(id, SEL))objc_msgSend)(ws, cur) : nil;
    if (!tx) return NO;
    for (NSString *n in @[@"SBTransientOverlayDismissWorkspaceTransaction", @"SBTransientOverlayDismissToAppsWorkspaceTransaction"]) {
        Class going = objc_getClass(n.UTF8String);
        if (going && [tx isKindOfClass:going]) return YES;
    }
    return NO;
}
// The two layout states hold the same stage (their app layouts are equal; none missing): nothing was added, removed or moved by the transition.
static BOOL DMSMSameStage(id from, id to) {
    SEL al = NSSelectorFromString(@"appLayout");
    if (!DMSMSigOK(from, al, DMSMSigObj(), "appLayout") || !DMSMSigOK(to, al, DMSMSigObj(), "appLayout")) return NO;
    id a = ((id (*)(id, SEL))objc_msgSend)(from, al), b = ((id (*)(id, SEL))objc_msgSend)(to, al);
    return a && b && [a isEqual:b];
}
static void (*o_SMSpotFocusNew)(id, SEL, id, id, id);
static void DMSMSpotFocusNew(id self, SEL _cmd, id from, id to, id windowScene) {
    // (Spotlight on the screen whose stage this is: with Spotlight up on the iPad, a transition on an external display's stage hands that stage's
    //  front window the focus as Apple does. Not a window scene: Spotlight on any screen, as before)
    UIWindowScene *screen = [windowScene isKindOfClass:[UIWindowScene class]] ? windowScene : nil;
    BOOL spot = DMSMEngine() && !DMTestFlag("/tmp/msb-sm-nospotkb") && DMSpotlightShownOn(screen);   // (the cheap part first: most transitions have no Spotlight)
    BOOL keep = spot && !DMSMOverlayGoing() && DMSMSameStage(from, to);
#if DEBUG
    if (DMTestFlag("/tmp/macstatusbar-debug")) DMLog([NSString stringWithFormat:@"[smspotkb] the stage's front window to be handed the focus? %@ -> %@ (Spotlight up on this screen %d, on any %d, dismissing %d; %@ screen): %@",
        DMSWDescribe(DMCall(from, @"appLayout")), DMSWDescribe(DMCall(to, @"appLayout")), DMSpotlightShownOn(screen), DMSpotlightShown(), DMSMOverlayGoing(),
        !screen ? @"no" : screen == MSBDMainWindowScene() ? @"the iPad's" : @"another", keep ? @"no, Spotlight keeps the keyboard" : @"Apple's way"]);
#endif
    if (keep) {
        DM_FEATURE_MARK("sm-spotlight-keeps-keyboard");
        if (gSMSpotKept < 100000) gSMSpotKept++;
        return;
    }
    o_SMSpotFocusNew(self, _cmd, from, to, windowScene);
}
static void DMSMSpotKeyboardInstall(void) {   // (optional: once, from the start-up self-check)
    static BOOL done = NO;
    if (done) return;
    done = YES;
    Class c = objc_getClass("SBMainSwitcherControllerCoordinator");
    SEL sel = sel_registerName("_focusNewlyAddedApplicationIfNeededTransitioningFromLayoutState:toLayoutState:windowScene:");
    Method m = c ? class_getInstanceMethod(c, sel) : NULL;
    if (!m || ![DMSMSigOfMethod(m) isEqualToString:DMSMExpect(@encode(void), @encode(id), @encode(id), @encode(id), NULL)]) {
        DMLog([NSString stringWithFormat:@"[smspotkb] the switcher's focus for a stage's front window is %s here: Spotlight over the windows keeps Apple's keyboard focus", m ? method_getTypeEncoding(m) : "not there"]);
        return;
    }
    MSHookMessageEx(c, sel, (IMP)DMSMSpotFocusNew, (IMP *)&o_SMSpotFocusNew);
    DMLog(@"[smspotkb] Spotlight over the windows keeps its keyboard: the stage's front window is not handed the focus while Spotlight is up");
}
