#!/bin/bash
# Mac test of Recent Apps with Left-Edge Swipe (Stage Manager engine, 1.8.4.2, off unless switched on): the gate, the pref, the Settings row and where it
# shows. With it off the gate stays as it was.
set -e
cd "$(dirname "$0")"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
S=../statusbar/StatusBar.x; P=../statusbar/macstatusbarprefs/Resources/Windows.plist; R=../common/OwnPageRows.h; M=../statusbar/macstatusbarprefs/MSBRootListController.m; 
check "the gate: off, held off as before; on, Apple's decides, never over the Mac Switcher's view nor with the Dock at Left" \
  "grep -qF 'if (DMSMFree() && (!gSMStripSwipe || gMSWOpen || gMSWSwitching || DMDockSideNow([UIScreen mainScreen].bounds.size) == MSBDDockLeft)) { DM_FEATURE_MARK(\"sm-no-strip-reveal\"); return NO; }' $S && grep -qF 'BOOL begins = o_SMStripRevealBegin(self, _cmd, g);' $S"
check "the strip stays hidden for Stage Manager, also during a reveal" "grep -qF 'return DMSMFree() ? YES : %orig;' $S && ! grep -qF 'during the swipe.s reveal Stage Manager says strip hidden' $S"
check "off unless switched on, a boolean only" "grep -qF 'static BOOL gSMStripSwipe = NO;' $S && grep -qF 'BOOL stripSwipe = sw && CFGetTypeID(sw) == CFBooleanGetTypeID() && CFBooleanGetValue(sw);' $S"
check "a window drag still can't start in the edge zone" "grep -qF '(IMP)DMSMUnpinBegin' $S"
check "the Settings row: off by default, in the Mac Switcher's group since 1.8.6, its sentence in the group's footer, no em dash" \
  "python3 -I -c \"import plistlib,sys; it=plistlib.load(open('$P','rb'))['items']; i=[x.get('id') for x in it].index('STRIP_SWIPE'); s=it[i]; g=[x for x in it[:i] if x.get('cell')=='PSGroupCell'][-1]; sys.exit(0 if s['key']=='smStripSwipe' and s['default'] is False and g.get('id')=='MSW_GROUP' and 'Recent Apps with Left-Edge Swipe:' in g['footerText'] and '\\u2014' not in g['footerText'] else 1)\""
check "shown with Stage Manager as the engine only, in the page and the search (its row; the Mac Switcher's group stays)" \
  "grep -qF 'if ([ident isEqualToString:kMSBDStripSwipeRowID] && (!s.engineWorks || !s.stageManagerEngine || !MSBDStripSwipeOS([NSProcessInfo processInfo].operatingSystemVersion.majorVersion))) return YES;' $R && grep -qF 'for (PSSpecifier *sp in _specifiers) if (![sp.identifier isEqualToString:kMSBDStripSwipeRowID]) [kept addObject:sp];' $M"
check "  ... and only on iPadOS 16 to 18: row and switch" \
  "grep -qF 'static inline BOOL MSBDStripSwipeOS(long major) { return major >= 16 && major <= 18; }' $R && grep -qF 'if (!MSBDStripSwipeOS([NSProcessInfo processInfo].operatingSystemVersion.majorVersion)) {' $M \
   && grep -qF 'if (stripMajor < 16 || stripMajor > 18) stripSwipe = NO;' ../statusbar/StatusBar.x"
check "a strip a swipe brought out is put away by our surfaces as a touch in an app puts it away (Apple's own method, the switch on only)" \
  "grep -qF 'gSMStripTouchedSel = NSSelectorFromString(@\"eventSource:userTouchedApplication:\");' $S && grep -qF 'if (!DMSMFree() || !gSMStripSwipe || !gSMSwitcherVCs.count || !DMSMStripEndKnown()) return NO;' $S \
   && grep -qF 'DMSMActivateOnTouch(event); DMSMStripTouch(event);' $S && grep -qF 'if (DMSMStripHoldsBack(what, ^{ DMSMWindowActionAs(sk, sn, users); })) return YES;' $S \
   && grep -qF 'DMSMStripPresentationEnd(@\"the Mac Switcher opens\");' ../statusbar/MacSwitcher.h && grep -qF 'DMSMStripPresentationEnd(@\"a desktop slides in\");' ../statusbar/MacSwitcherSM.h"
check "  ... drawn while Stage Manager presents it, and a touch judged where it landed, not by the system gestures' copy" \
  "grep -A 1 'if (DMSMStripPresentedFor(al)) return YES;' $S | grep -qF 'if (!gSMStripRevealing) return NO;' && grep -qF 'if ([wc isEqualToString:@\"_UISystemGestureWindow\"]) continue;' $S"
# (review 1.8.4.4 L4) Presented or not is asked of the switcher of the display the stage is on: the other display's hidden strip stays hidden.
check "  ... asked of the stage's own display's switcher, in both drawing hooks" \
  "grep -qF 'if (o > 0.0 && DMSMFree() && !DMSMStripDebugApple() && !DMSMStripIsRevealed(self, al) && DMSMStripOffStage(self, al)) {' $S \
   && grep -qF 'if (DMSMStripIsRevealed(self, al) || !al || !DMSMStripOffStage(self, al)) return o;' $S \
   && grep -qF 'if (sc == [UIScreen mainScreen] ? DMSMIsMainIdentity(identity) : (identity && [identity isEqual:DMSMIdentityOfScreen(sc)])) return YES;' $S \
   && grep -qF 'static BOOL DMSMStripPresented(void) { return DMSMStripPresentedFor(nil); }' $S"
# (review 1.8.4.4 L5 and the title bars of 2f8f30e4) A touch puts the strip away only where it landed on one of our surfaces: never one with no
# window, never Stage Manager's own window (strip cards, our title bars: a light's action puts it away itself).
check "  ... a touch with no window or in Stage Manager's own window leaves it" \
  "grep -A 3 'UIWindow \*w = t.window;' $S | grep -qF 'if (!w) continue;' && grep -qF 'if ([wc isEqualToString:@\"SBMainSwitcherWindow\"]) continue;' $S"
# (review 1.8.4.4 L7) The Mac Switcher puts the strip away before its pictures, and keeps none from a moment the strip was out.
check "the Mac Switcher: the strip goes before the desktop's picture, and no picture is kept from a moment it was out" \
  "grep -B 10 'BOOL byGesture = DMMSWGestureGrace()' ../statusbar/MacSwitcher.h | grep -qF 'BOOL stripOut = DMSMStripPresentationEnd(@\"the Mac Switcher opens\");' \
   && grep -qF 'BOOL lift = !stripOut && byGesture && gMSWLiftPic' ../statusbar/MacSwitcher.h && grep -qF 'else if (!stripOut) {' ../statusbar/MacSwitcher.h \
   && [ \$(grep -c 'DMSMStripPresentationEnd(' ../statusbar/MacSwitcher.h) = 1 ]"
# (review 1.8.4.4 M1) No strip a swipe brings out where nothing of ours can put it away (17, 18; 16 as it ran), and an action SpringBoard lays out
# waits while Stage Manager still presents the strip, a quarter second at a time, and is left after a second: never under it.
check "fails closed: on 17 and 18 the swipe brings no strip out without its end as read; 16 as before" \
  "grep -qF 'if (DMSMFree() && DMNewOS() && !DMSMStripEndKnown()) { DM_FEATURE_MARK(\"sm-no-strip-reveal-no-end\"); return NO; }' $S \
   && grep -qF 'static BOOL DMSMStripEndKnown(void);   // (below: ' $S"
check "  ... an action waits while Stage Manager still presents the strip (re-read after the ask), at most 1 s, one action however often asked" \
  "grep -A 3 '^static BOOL DMSMStripHoldsBack(NSString \*what, dispatch_block_t act) {' $S | grep -qF 'if (!DMSMStripPresented()) return NO;' \
   && grep -A 3 '^static void DMSMStripWaitStep(' $S | grep -qF 'if (!DMSMStripPresented()) {' && grep -A 10 '^static void DMSMStripWaitStep(' $S | grep -qF 'if ((!held && step >= 4) || ticks >= 120) {' \
   && grep -qF 'if ([gSMStripWaiting containsObject:what]) {' $S && grep -qF 'static BOOL DMSMStripHoldsBack(NSString *what, dispatch_block_t act);' $S"
# (review 1.8.4.4 L1) The strip is asked to go only after a switcher gesture's hold is over, and never from under its own swipe's finger: an action
# waits for the finger, and its second counts from the lift.
check "the strip's end: after the switcher gesture's deferrals, and not while its own swipe's finger is on it" \
  "grep -A 12 'if (last && DMSMGestureLive()) {' $S | grep -qF 'if (DMSMStripHoldsBack(what, ^{ DMSMWindowActionAs(sk, sn, users); })) return YES;' \
   && ! grep -B 3 'if (DMSMGestureHoldsStage(DMSMStageOf(key))) {' $S | grep -qF 'DMSMStripHoldsBack' \
   && grep -qF 'gSMStripRevealGesture = [g isKindOfClass:[UIGestureRecognizer class]] ? g : nil;' $S && grep -qF 'return s == UIGestureRecognizerStateBegan || s == UIGestureRecognizerStateChanged;' $S \
   && grep -qF 'BOOL out = NO, asked = NO, held = !force && DMSMStripSwipeHeld();' $S && grep -qF 'DMSMStripWaitStep(what, act, held ? step : step + 1, ticks + 1);' $S"
# (review 1.8.4.4 L2) The desktop's last window, taken out after the Home transition, and a force quit (a key's too: no touch put the strip away)
# wait for the strip as the action does; the removal keeps whether the Home was seen to end.
check "the last window's removal after Home and a force quit wait for the strip too" \
  "grep -A 2 'DMSMAfterOurHome(removal, closing, ^{' $S | grep -qF 'if (!DMSMStripHoldsBack(removal, ^{ takeOut(ended); })) takeOut(ended);' \
   && grep -qF 'BOOL ended = DMSMAfterHomeEnded();' $S && grep -qF 'if (shown && homeEnded) {' $S && ! grep -qF 'if (shown && DMSMAfterHomeEnded()) {' $S \
   && grep -B 6 'gAppQuitAt\[bundleID\] = @(CACurrentMediaTime());' $S | grep -qF 'if (DMSMStripHoldsBack([@\"force quit \" stringByAppendingString:bundleID], ^{ DMForceQuitBundle(bundleID); })) return;'"
# (review 1.8.4.4 L3) The green light (title bar and menu bar) and a title bar's double tap (Fill, Zoom, back) put the strip away before they act.
check "the green light and the title bar's double tap put the strip away first" \
  "grep -A 4 '^static BOOL DMSMToggleZoom(NSString \*key) {' $S | grep -qF 'DMSMStripPresentationEnd([NSString stringWithFormat:@\"zoom on %@\", DMSMKeyText(key)]);' \
   && grep -A 1 'int step = MSBDTitleStep(action, atTarget, rec != nil);' ../statusbar/TitleBarTap.h | grep -qF 'DMSMStripPresentationEnd([NSString stringWithFormat:@\"%@ on %@\", why, DMSMKeyText(key)]);'"
# (1.8.4.5) SpringBoard's own window removals (iPadOS's Command-W, an app ending its scene, the switcher's delete, a force quit) put a presented strip
# away before the transition is laid out: the switcher's animation for a workspace request that names leaving scenes; on 17 and 18 no reveal without it.
check "SpringBoard's own window removals put the strip away first, and 17/18 reveal nothing without that" \
  "grep -qF 'if (DMSMFree() && DMNewOS() && gSMStripSwipe && DMSMStripPresented()) {' $S && grep -qF 'NSUInteger n = DMSMRequestRemovals(request);' $S \
   && grep -qF 'SEL s = NSSelectorFromString(@\"animationControllerForTransitionRequest:\");' $S && grep -qF 'MSHookMessageEx(c, s, (IMP)DMSMAnimForRequest, (IMP *)&o_SMAnimForRequest);' $S \
   && grep -qF 'ents = NSSelectorFromString(@\"entitiesWithRemovalContexts\");' $S && grep -qF 'return o_SMAnimForRequest(self, _cmd, request);' $S \
   && grep -qF 'if (DMSMFree() && DMNewOS() && gSMStripSwipe && !o_SMAnimForRequest) { DM_FEATURE_MARK(\"sm-no-strip-reveal-no-removal-end\"); return NO; }' $S \
   && grep -A 2 'DMSMHookStripRemovalEnd();' $S | grep -qF '}'"
check "review 1.8.4.5 M1: a strip still presented right after the ask on 17/18 stops the swipe for this iPadOS build (kept in prefs, cleared by turning the switch on)" \
  "grep -qF 'if (still) DMSMStripNoteSlowEnd(why);' $S && grep -qF 'if (!DMNewOS() || DMSMStripEndSlow()) return;' $S \
   && grep -qF 'CFPreferencesSetValue(MSBD_STRIP_SLOW_KEY, (__bridge CFStringRef)b, MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);' $S \
   && grep -qF 'if (DMSMFree() && DMNewOS() && gSMStripSwipe && DMSMStripEndSlow()) { DM_FEATURE_MARK(\"sm-no-strip-reveal-slow-end\"); return NO; }' $S \
   && grep -qF 'if (stripLoaded && stripSwipe && !gSMStripSwipe) DMSMStripClearSlowEnd();' $S"
check "review 1.8.4.5 L1: SpringBoard's removal asks even with the swipe's finger on the strip, cancels that gesture, and holds new reveals for a second" \
  "grep -qF 'if (g && DMSMStripSwipeHeld()) { g.enabled = NO; g.enabled = YES; }' $S && grep -qF 'gSMStripRemovalUntil = CACurrentMediaTime() + 1.0;' $S \
   && grep -qF 'if (DMSMFree() && gSMStripSwipe && CACurrentMediaTime() < gSMStripRemovalUntil) { DM_FEATURE_MARK(\"sm-no-strip-reveal-removal\"); return NO; }' $S"
check "review 1.8.4.5 L3: the leaving scenes read with signature and type checks, both accessors required before the hook" \
  "grep -qF 'DMSMSigOK(request, ac, DMSMSigObj(), \"applicationContext\")' $S && grep -qF 'return [list isKindOfClass:[NSArray class]] ? [list count] : 0;' $S \
   && grep -qF '|| !ma || ![DMSMSigOfMethod(ma) isEqualToString:DMSMSigObj()] || !me || ![DMSMSigOfMethod(me) isEqualToString:DMSMSigObj()]) {' $S"
exit $fails
