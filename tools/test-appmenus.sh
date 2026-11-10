#!/bin/bash
# Mac test of the app's own menus in the menu bar (1.8.5 item 3): common/AppMenuRules.h (test-appmenus.m), then the sites in the app's and
# SpringBoard's code.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O1 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/t" test-appmenus.m
fails=0; "$W/t" || fails=1
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
S=../statusbar/StatusBar.x; M=../statusbar/AppMenus.h; A=../appbridge/AppMenus.h; B=../appbridge/AppBridge.x
check "the app answers in every build: registered right after its other actions, outside any debug block" \
  "grep -A1 -F 'MABRegisterActions();' $B | grep -qF 'MABRegisterMenus();   // (its own menus for the menu bar: AppMenus.h)' && awk '/^#if DEBUG/{d=1} /^#endif/{d=0} /MABRegisterMenus\\(\\);   \\/\\/ \\(its own/{exit d}' $B"
check "only commands something would act on: no target, left out; hidden, left out; disabled, kept greyed" \
  "grep -qF 'if (!target) { noTarget++; continue; }' $A && grep -qF 'if (c.attributes & UIMenuElementAttributesHidden) { hidden++; continue; }' $A && grep -qF '@\"e\": @(!(c.attributes & UIMenuElementAttributesDisabled))' $A"
check "the main menu and the responders' key commands both count; at most 64 responders (L8)" "grep -qF 'UIMenu *root = MABMenuRoot();' $A && grep -qF 'for (UIResponder *x = start; x && depth < 64; x = x.nextResponder, depth++) {' $A"
check "our Edit's own commands are left out before the app is asked anything about them (L5)" \
  "awk '/MSBDAppMenuOursHasHint\\(hint\\)\\)\\) continue;\$/{if(!t)p=1} /targetForAction:action withSender:c/{t=1} END{exit !p}' $A"
check "a picked row: the command with its key the app offers now (a row from an older snapshot works), only this process's, sent to the responder that takes it" \
  "grep -qF '? gMABMenuCmds[@(key)] : nil;' $A && grep -qF 'if (!c && ours) { MABMenuSnapshot(); c = gMABMenuCmds[@(key)]; }' $A && grep -qF 'BOOL ours = nonce == MABMenuNonce();' $A && grep -qF 'sendAction:c.action to:target from:c forEvent:nil' $A"
check "each row carries its key, each answer the process's nonce and pid; SpringBoard sends the key and the nonce back" \
  "grep -qF '@\"x\": key' $A && grep -qF 'NSDictionary *snap = @{@\"n\": @(MABMenuNonce()), @\"p\": @(getpid()),' $A && grep -qF 'notify_set_state(token, MSBDAppMenuActState(key, nonce));' $M && grep -qF 'uint32_t key = [r[@\"x\"] unsignedIntValue];' $M"
check "an answer is only announced once written; SpringBoard takes none without the nonce and pid" \
  "grep -qF 'if (wrote) notify_post(ready);' $A && grep -qF '|| ![d[@\"n\"] isKindOfClass:[NSNumber class]] || ![d[@\"p\"] isKindOfClass:[NSNumber class]]) return nil;' $M"
check "SpringBoard checks every field of an answer, takes only our menus' titles, reads at most 256 KB (L1)" \
  "grep -qF 'NSDictionary *d = sizeOK ? DMAMClean([NSDictionary dictionaryWithContentsOfFile:path], bundle) : nil;' $M && grep -qF 'st.st_size <= 256 * 1024;' $M && grep -qF 'if (![known containsObject:m[@\"t\"]] || [titles containsObject:m[@\"t\"]]) continue;' $M && grep -qF '![r[@\"x\"] isKindOfClass:[NSNumber class]]) continue;' $M"
check "an answer it can't read is asked for again only after 30 s; the container's path is looked up once, again after a failed read (L4)" \
  "grep -qF 'if (failed && CACurrentMediaTime() - failed.doubleValue < 30.0) return;' $M && grep -qF 'if (!dir.length) { dir = DMFDContainer(bundle).path; if (dir.length) gAMContainer[bundle] = dir; }' $M && grep -qF '[gAMContainer removeObjectForKey:bundle];' $M"
check "an answer from a process that has gone is dropped; Home or Finder in front: the same app coming back is asked again" \
  "grep -qF 'if (gAMSnap[bundle] && pid > 0 && [gAMSnap[bundle][@\"p\"] intValue] != pid) {' $M && grep -qF 'if (!bundle.length) { last = nil; return; }' $M && grep -qF 'else if (gAMOn && !frontApp) DMAMFrontSeen(nil);' $S"
check "the window the app's shortcuts reach: the keyboard's scene, else the only one in front, else the app's key window; never the set's first (M2)" \
  "grep -qF 'SEL kbTarget = NSSelectorFromString(@\"_isTargetOfKeyboardEventDeferringEnvironment\");' $A && grep -qF 'if (active == 1) for (UIWindow *w in only.windows) if (w.isKeyWindow) return w;' $A && grep -qF 'return app.keyWindow;' $A && ! grep -qF 'for (UIWindow *w in [UIApplication sharedApplication].windows) if (w.isKeyWindow) return w;' $A"
check "a row picked with another of the app's windows in front is looked up in a snapshot of that one" \
  "grep -qF 'gMABMenuScene = win.windowScene;' $A && grep -qF 'UICommand *c = ours && win.windowScene == gMABMenuScene ? gMABMenuCmds[@(key)] : nil;' $A && grep -qF 'UIResponder *start = MABMenuStart(win);' $A"
check "a destructive command only as the app's own shortcut (performed as that key command, the app's confirmation with it), else left out (M4)" \
  "grep -qF 'if (((c.attributes & UIMenuElementAttributesDestructive) || MSBDAppMenuDestructive(title)) && !kc.input.length) { destructive++; continue; }' $A"
check "titles kept fresh while the app stays in front: asked again after its taps, after a pick, after a thin answer (M5)" \
  "grep -qF 'BOOL partial = !win || win.windowScene.activationState != UISceneActivationStateForegroundActive;' $A && grep -qF 'if (n <= 3) DMAMAskSoon(bundle, 1.0);' $M && grep -qF 'snprintf(touched, sizeof touched, \"com.besiktasliseba.appbridge.touched.%08x\", h);' $M && grep -qF 'DMAMAskSoon(b, 0.8);' $M && grep -qF 'if (mine != seq || !gAMOn || ![[DMActiveApp() bundleIdentifier] isEqualToString:b]) return;' $M"
check "a keyboard shortcut, Return or another of its windows made key asks the app again, as a tap does (A12Z 18.5)" \
  "grep -qF 'if (isDown && ((m & (UIKeyModifierCommand | UIKeyModifierControl)) || code == 0x28 || code == 0x58)) MABMenusChanged();' $B && grep -qF 'for (NSNotificationName nn in @[UIWindowDidBecomeKeyNotification, UISceneDidActivateNotification, UISceneDidEnterBackgroundNotification, UISceneDidDisconnectNotification])' $A && grep -qF 'if (!MABMenusOn()) return;' $A && grep -qF 'snprintf(name, sizeof name, \"com.besiktasliseba.appbridge.menuschanged.%08x\", hash);' $A && grep -qF 'snprintf(changed, sizeof changed, \"com.besiktasliseba.appbridge.menuschanged.%08x\", h);' $M"
check "Edit rows ours has are not added twice, the others go under our Find" \
  "grep -qF 'if ([menu isEqualToString:kMSBDAppMenuEdit] && (MSBDAppMenuOursHas(title) || MSBDAppMenuOursHasHint(hint))) continue;' $A && grep -qF 'NSArray *extras = DMAMEditExtras(activeBundle);' $S"
check "the bar: our Go, Window and Audio keep their room; an app title that doesn't fit whole is left out" \
  "grep -qF 'amReserve = MAX(DMAMTitleWidth(@\"Go\", timeFont), kTitleMinShown) + amGap;' $S && grep -qF 'if (x + DMAMTitleWidth(t, timeFont) > titleMaxRight - amReserve) break;' $S"
check "Go, Window and Audio keep at least what DMLayoutTitle needs to show a title (M3: Go alone was hidden); one constant for both" \
  "grep -qF 'BOOL show = text.length && maxW >= kTitleMinShown;' $S && grep -qF 'amReserve += MAX(DMAMTitleWidth(@\"Window\", timeFont), kTitleMinShown) + amGap;' $S && grep -qF 'amReserve += MAX(DMAMTitleWidth(@\"Audio\", timeFont), kTitleMinShown) + amGap;' $S && grep -qF 'MAX(DMAMTitleWidth(@\"Edit\", timeFont), kTitleMinShown) - amGap) {' $S"
check "a title's width is measured once per size and text (L3)" "grep -qF 'NSNumber *w = widths[k];' $M && grep -qF 'widths[k] = w;' $M"
check "not over our Finder window (its own File and View)" "grep -qF 'NSString *amBundle = (gAMOn && !finderTitles && appRight > 0 && frontApp) ? [frontApp bundleIdentifier] : nil;' $S"
check "the slots unused now are hidden at every layout" "grep -qF 'DMAMHideSlots(fg, amShown.count);' $S"
n=$(grep -c 'DM_AM_BUTTONS' $S)
check "the slots' buttons are in every list of bar titles (hover, tap switch, hit tests, debug lists: 8)" "[ $n -ge 9 ]"
check "the slots go with the bar's other titles on the Lock Screen and in a collapsed copy" "grep -qF 'const void *am[] = { DM_AM_LABELS, DM_AM_BUTTONS, DM_AM_PILLS };' $S && grep -qF 'kViewPillKey, DM_AM_LABELS, DM_AM_BUTTONS, DM_AM_PILLS };' $S"
check "colour and fade follow the slots' labels" "grep -qF 'kDateProxyKey, DM_AM_LABELS };' $S && grep -qF '[NSValue valueWithPointer:&gAMLabelKeys[6]]' $S && grep -qF '\"appmenu5\", \"appmenu6\" };' $S && grep -qF '_Static_assert(kMSBDAppMenuSlots == 7,' $S"
check "a title tap with another menu open switches menus" "grep -qF 'else if (DMAMSlotOf(b) >= 0) DMOpenAppOwnMenu(b);' $S && grep -qF 'if (DMTitleTapWithMenuOpen(btn)) return;' $M"
check "a menu opens under the slot that shows its title once the fresh answer is laid out, not at all if it is gone (L6)" \
  "grep -qF '[f layoutIfNeeded];' $M && grep -qF 'NSUInteger i = [(NSArray *)objc_getAssociatedObject(f, kAMShownKey) indexOfObject:menu];' $M && grep -qF 'DMPresentMenu(b, &gAMLabelKeys[i], &gAMPillKeys[i], items);' $M"
check "debug logs name a row by its key or place, never its title (user content: L9)" \
  "grep -qF '[appmenus] %@ > row %08x picked: sent to %@\", menu, key, b' $M && grep -qF 'appmenus: row %08x (%@) sent to %@: %d\", key,' $A && grep -qF 'appmenus:   %@ > %08x %@%@%@\", m[@\"t\"], [r[@\"x\"] unsignedIntValue],' $A && grep -qF '[appmenus] debug pick: %@ > row %ld (enabled %d)' $S"
check "the release marker" "grep -qF 'DM_FEATURE_MARK(\"app-own-menus\");' $A"
# Show Apps' Own Menus (review 1.8.5 item 3, M6): a switch, off unless switched on; off, no title, no Edit extras, no ask, and no snapshot in any app
P=../statusbar/macstatusbarprefs/Resources/Root.plist; R=crashmap-rules.txt
check "the switch in Settings > Status Bar: Show Apps' Own Menus, off unless switched on, applied when changed" \
  "python3 -I -c 'import plistlib,sys; it=plistlib.load(open(sys.argv[1],\"rb\"))[\"items\"]; r=[x for x in it if x.get(\"key\")==\"appOwnMenus\"]; sys.exit(0 if len(r)==1 and r[0].get(\"cell\")==\"PSSwitchCell\" and r[0].get(\"default\") is False and r[0].get(\"label\")==\"Show Apps\x27 Own Menus\" and r[0].get(\"defaults\")==\"com.besiktasliseba.macstatusbar\" and r[0].get(\"PostNotification\")==\"com.besiktasliseba.macstatusbar/prefsChanged\" else 1)' $P"
check "SpringBoard reads it (off unless a stored yes) and publishes it for every app" \
  "grep -qF 'CFPreferencesCopyValue(CFSTR(\"appOwnMenus\"), MSB_DOMAIN' $S && grep -qF 'BOOL amOn = amRef && CFGetTypeID(amRef) == CFBooleanGetTypeID() && CFBooleanGetValue(amRef);' $S && grep -qF 'DMAMApplyPref(amOn);' $S && grep -qF '#define kDMAMSwitchName \"com.besiktasliseba.appbridge.appmenus\"' $M"
check "off: no titles (the layout), no Edit extras, no ask, no answer read" \
  "grep -qF 'NSString *amBundle = (gAMOn && !finderTitles' $S && grep -qF 'return gAMOn && bundle.length ? DMAMRows(bundle, kMSBDAppMenuEdit) : @[];' $M && grep -qF 'if (!gAMOn || !bundle.length) return;' $M && grep -qF 'if (!gAMOn) return;   // (an answer that comes in after the switch went off)' $M"
check "off: the app makes no snapshot and performs no row (only state 1 is on; never published is off)" \
  "grep -qF 'return state == 1;' $A && grep -A1 -F 'notify_register_dispatch(name, &tokenAsk' $A | grep -qF 'if (!MABMenusOn()) return;' && grep -A1 -F 'static void MABMenuPerform(uint64_t state) {' $A | grep -qF 'if (!MABMenusOn()) return;'"
check "the crash guard turns the switch off for a crash in either side, not the whole status bar" \
  "grep -qF 'target appOwnMenus pref com.besiktasliseba.macstatusbar appOwnMenus 0 0 Show Apps' $R && grep -qxF 'file MacStatusBarCore ^AppMenus\\.h\$ appOwnMenus' $R && grep -qxF 'file MacAppBridge ^AppMenus\\.h\$ appOwnMenus' $R"
check "no em dash in the new files" "! grep -q \$'\\xe2\\x80\\x94' ../common/AppMenuRules.h $A $M test-appmenus.m"
[ "$fails" = 0 ] && echo "test-appmenus: all pass" || { echo "test-appmenus: FAILED"; exit 1; }
