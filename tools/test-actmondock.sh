#!/bin/bash
# Mac test of Activity Monitor in the Dock (1.7.3 item 5) and the App Library search's rules and window keys (item 13): the shared rules
# (common/ActMonDock.h, test-actmondock.m), and the wiring in the sources -- never in the Dock without the store's hook, nothing of ours in a layout
# file, the Dock-only rule, the record, its menus, the Dock's dot and Trash, the crash guard's rule, the search following the list's own text,
# Command-W / Command-M for every native window, and its running entry while its window is open (1.7.7 item 1b).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/tam" test-actmondock.m
"$W/tam"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
D=../statusbar/ActMonDock.h; A=../statusbar/AppLibraryApps.h; N=../statusbar/NativeWindow.h
check "the Dock part is part of the App Library's file (one include, the shared rules first)" \
  "grep -q '#include \"ActMonDock.h\"' $A && grep -q '#include \"../common/ActMonDock.h\"' $A && ! grep -q '#include \"ActMonDock.h\"' ../statusbar/StatusBar.x"
check "every layout SpringBoard writes goes through our hook: the current and the desired one, each store class with its own save" \
  "grep -q 'saveCurrentIconState:error:' $D && grep -q 'saveDesiredIconState:error:' $D && grep -q 'SBIconModelPropertyListFileStore' $D && grep -q 'SBDefaultIconModelStore' $D \
   && grep -q 'MSBDLayoutWithout(state, kDMALActMonIdentifier, &n)' $D && grep -q 'orig(self, _cmd, clean, err)' $D"
check "each store class gets its own trampoline (a subclass's super call never runs its own save again)" \
  "grep -q 'DMAM_STORE_TRAMPOLINES(0)' $D && grep -q 'DMAM_STORE_TRAMPOLINES(1)' $D && grep -q 'DMAM_STORE_TRAMPOLINES(2)' $D && grep -q 'DMAMOwnMethod(c, @\"saveCurrentIconState:error:\")' $D"
check "never in the Dock without the layout kept clean and the Dock-only rule (ready = save && desired && allowed; put in only when ready)" \
  "grep -q 'gDMAMReady = save && desired && allowed;' $D && grep -q 'if (!gDMAMReady || !gDMALOn || !dock || !icon || !icons) return NO;' $D"
check "we never write SpringBoard's layout file ourselves (only SpringBoard's own save, through its store)" \
  "! grep -q '@\"[^\"]*IconState\.plist' $D && ! grep -q 'writeToFile\|writeToURL\|NSPropertyListSerialization' $D"
check "the record is our own preference (activityMonitorDock in MacStatusBar's domain), read through the shared rule" \
  "grep -q 'CFSTR(\"activityMonitorDock\")' $D && grep -q 'MSBDActMonDockRecord((__bridge id)v)' $D && grep -q 'CFPreferencesSetValue(kDMAMDockKey' $D"
check "a save before the start's look never changes the record; SpringBoard taking it out of our list is not fought" \
  "grep -q 'if (gDMAMStarted && gDMALOn) DMAMRecordWrite(here, why);' $D && grep -q 'gDMAMListPutIn == dock) return;' $D"
check "only the Dock: the root folder's rule, SpringBoard's drop, and anything else taken out of other lists" \
  "grep -q 'iconListModel:isAllowedToContainIcon:' $D && grep -q 'canAcceptDropInSession:inIconListView:' $D && grep -q 'DMAMTakeOutElsewhere();' $D"
check "the Dock-only rule is the Home Screen's: the App Library's own folders keep SpringBoard's rule (refused there, a category update inserted past its list's end: SpringBoard's assertion after SnowBoard's Apply, 1.7.3-1.7.4)" \
  "grep -q 'if (!DMALIsOurs(icon) || DMAMLibraryFolder(self)) return o_DMAMAllowed(self, _cmd, list, icon);' $D && grep -q 'isLibraryCategoryFolder' $D"
check "a drag out of the Dock let go where nothing took it leaves the Dock (UIKit's own end of the drag, cancelled or forbidden, outside the Dock)" \
  "grep -q 'dragInteraction:session:didEndWithOperation:' $D && grep -q 'if (fromDock && outside && op <= 1)' $D"
check "its menu: Open, Add to Dock / Keep in Dock (its running entry's icon; greyed: Dock full) / Remove from Dock, by the shared rule, run once the menu has closed" \
  "grep -q 'actionWithTitle:@\"Open\"' $D && grep -q 'actionWithTitle:keep ? @\"Keep in Dock\" : @\"Add to Dock\"' $D && grep -q 'actionWithTitle:@\"Remove from Dock\"' $D \
   && grep -q 'MSBDActMonRow row = MSBDActMonMenuRow(inList && !gDMAMTemp, runningHere);' $D \
   && grep -q 'add.subtitle = @\"Dock full\"' $D && grep -q 'performAfterIconContextMenuDismissesUsingBlock:' $D && grep -q 'return DMAMMenu(location);' $A"
check "a tap on its Dock icon -- kept, or its running entry after the Dock's apps or in the recents -- opens the window directly (no App Library to dismiss)" \
  "grep -q 'if (DMAMLocationInDock(location)) {' $A && grep -q 'DMActivityMonitorOpen();' $A && grep -q 'containsString:@\"Dock\"\] && !\[loc containsString:@\"Library\"\];' $D"
check "it follows Show in App Library (off: out of the Dock, the record kept)" \
  "grep -q 'DMAMApply(on);' $A && grep -q 'DMAMDockTakeOut(@\"Show in App Library switched off\", NO);' $D"
check "the Dock's running dot asks MacStatusBar (dlsym), and the Dock's Trash takes it out of the Dock" \
  "grep -q 'dlsym(RTLD_DEFAULT, \"MSBDOwnAppsRunning\")' ../dock/RunningIndicator.m && grep -q 'MSBDOwnAppsRunning(void)' $D \
   && grep -q 'dlsym(RTLD_DEFAULT, \"MSBDActMonDockRemove\")' ../dock/Dock.x && grep -q 'BOOL MSBDActMonDockRemove(void)' $D && grep -q 'DMIsOwnAppIcon(icon)' ../dock/Dock.x"
# its running entry (1.7.7 item 1b)
check "its running entry follows the window: the window's own move into or out of a window (opened, closed, another desktop) asks for it; a window on another desktop still runs (the dot too)" \
  "grep -q 'DMAMWindowChanged(); }' ../statusbar/ActivityMonitor.h && grep -q 'static void DMAMWindowChanged(void);' ../statusbar/ActivityMonitor.h \
   && grep -q 'for (DMNativeWindow \*w in gMSWAwayNatives) if (\[w isKindOfClass:\[DMActivityMonitorWindow class\]\]) return YES;' $D \
   && grep -q 'return DMAMWindowExists() ? \[NSSet setWithObject:kDMALActMonIdentifier\] : nil;' $D"
check "its running entry is never recorded and never saved (SpringBoard's saves skip the record; it goes in and out without a save of ours)" \
  "grep -q 'if (gDMAMTemp) return;   // (its running entry: never recorded' $D && grep -q 'DMAMDockLeave(\[NSString stringWithFormat:@\"the running entry leaves the Dock.s list: %@\", why\], NO, NO);' $D \
   && grep -q 'if (save) DMAMSaveLayout();' $D"
check "in the Dock's recents: SpringBoard's recents copied with ours first while it makes the shown list, put back right after; the Dock's view gets our icon for our item" \
  "grep -q '\"_currentRecentDisplayItems\"' $D && grep -q 'with = MSBDActMonRecentsWithOurs(was, DMAMRecentsItem());' $D \
   && grep -q 'if (with) object_setIvarWithStrongDefault(self, gDMAMRecentsIvar, was);' $D && grep -q '@\"_iconForDisplayItem:\", @\"@@:@\"' $D \
   && grep -q '_updateCurrentDisplayItemsAfterContinuityChange:notifyDelegate:\", @\"v@:BB\"' $D"
check "never ours in the recents while it is in the Dock's own list; the recents path off where SpringBoard does not take it or throws (after the Dock's apps then)" \
  "grep -q 'if (spot == MSBDActMonSpotRecents && gDMAMRecentsIvar && DMAMDockIndex() < 0 && DMALIcon()) {' $D && grep -q 'gDMAMRecentsPath = 0; gDMAMInRecents = NO;' $D && grep -q 'if (!with) @throw;' $D"
check "a Dock list SpringBoard made anew (the layout reloaded or restored) gets the running entry again: only the list it was put in refuses it (1.7.7 review N2)" \
  "grep -q 'BOOL letGo = dock == gDMAMListPutIn;' $D && grep -q '        if (letGo) gDMAMTempRefused = dock;' $D && ! grep -q 'gDMAMTemp = NO; gDMAMTempRefused = dock;' $D && [ \$(grep -c 'gDMAMTempRefused = dock' $D) = 1 ]"
check "its display item for the recents is asked for once, only where the recents' hooks and list are in, its throw caught (every start asked it before, hooks or not)" \
  "grep -q 'id item = icons && gDMAMRecentsIvar ? DMAMRecentsItem() : nil;' $D && grep -q 'gDMAMRecentsPath = item ? 1 : 0;' $D && [ \$(grep -c 'DMAMRecentsItem()' $D) = 2 ] \
   && awk '/^static id DMAMRecentsItem\\(void\\) \\{/,/^}/' $D | grep -q 'if (item || asked) return item;' && awk '/^static id DMAMRecentsItem\\(void\\) \\{/,/^}/' $D | grep -q '@try { item = ' && awk '/^static id DMAMRecentsItem\\(void\\) \\{/,/^}/' $D | grep -q '@catch (NSException \\*e) { item = nil;'"
check "Keep / Add: the record first (the recents let go of it as it goes in), then the Dock's end, as 1.7.3 adds it" \
  "grep -q 'DMAMRecordWrite(end, why);' $D && grep -q 'if (!DMAMDockPutIn(end, why)) { DMAMRecordWrite(-1, @\"not put in\"); DMAMRunningSync(why); return; }' $D"
check "the Dock part runs the recents view's parked changes for ours too (exported, found with dlsym)" \
  "grep -q 'void MSBDDockRecentsFlush(NSString \*why) { DMFlushDeferredDockIcons(why); }' ../dock/Dock.x && grep -q 'dlsym(RTLD_DEFAULT, \"MSBDDockRecentsFlush\")' $D"
check "an open Activity Monitor's running entry is never taken out by a drag or the Trash (an open app stays); unkept while open it stays in place or goes to the recents" \
  "grep -q '|| gDMAMTemp) return NO;' $D && grep -q 'if (gDMAMTemp) DMLog(@\"\[amdock\] its running entry stays in the Dock: its window is open\");' $D \
   && grep -q 'MSBDActMonUnkeptStaysInPlace(gDMAMReady && gDMALOn, DMAMWindowExists(), recents)' $D"
check "the crash guard: a crash in the Dock part turns Show in App Library off (the same icon)" "grep -q '^file MacStatusBarCore ^ActMonDock\\\\.h\$ actmonLibrary' crashmap-rules.txt"
check "the debug triggers are debug only" "awk '/^#if DEBUG/{d=1} /^#endif/{d=0} /DMAMDebugTrigger\\(NSString/{print d}' $D | grep -qx 1 && grep -q 'amdbg_' ../statusbar/StatusBar.x"
# item 13: the search follows the list's own text; the empty search is never made anew (1d4ac5a); the window keys
check "a result is decided by the search field's text (the list's query made from it), then the one it asks for, then the one it keeps" \
  "grep -q 'withOurs = DMALResultWithOurs(result, DMALFieldQuery(self));' $A && grep -q '_queryForCurrentSearchTextField' $A && grep -q 'return q ?: (gDMALAsked ?: DMALIvarObj(list, \"_currentQuery\"));' $A \
   && grep -q 'id was = gDMALAsked; gDMALAsked = query;' $A && grep -q 'gDMALAsked = was;' $A && grep -q 'id decide = current ?: query;' $A && grep -q '!DMALQueryMatches(decide, icon)' $A"
check "the engine's unchanged answers: the library's callback hooked, the shared rule decides, given through the same rule (DMALResults)" \
  "grep -q 'DMALHook(@\"SBHTableViewIconLibrary\", @\"engine:queryResultsWereUpdated:\", @\"v@:@@\", (IMP)DMALEngine' $A \
   && grep -q 'MSBDALGiveAnswer(nothing, DMCall(DMCall(result, @\"query\"), @\"searchString\"), DMCall(field, @\"searchString\"), DMALQueryMatches(field, icon), gDMALShown)' $A \
   && grep -q 'DMALResults(list, NSSelectorFromString(@\"iconLibrary:hasUpdatedQueryResult:\"), library, result);' $A && ! grep -q 'MSBDALRecheck' $A"
check "a result with ours is made anew only when neither text is empty (the 18.5 crash of the empty search stays fixed)" \
  "grep -q 'if (!r && !MSBDALMayMakeAnew(DMCall(query, @\"searchString\"), DMCall(decide, @\"searchString\"))) return nil;' $A"
check "Command-W / Command-M for every native window without keys of its own (Activity Monitor), a sheet's Return / Esc first" \
  "grep -q 'own ? ((BOOL (\*)(id, SEL, id))objc_msgSend)(w, @selector(dm_handleKey:), p.key) : DMNativeWindowKeys(w, p.key);' $N \
   && grep -q 'UIKeyboardHIDUsageKeyboardW) { DM_FEATURE_MARK(\"native-window-keys\"); \[w close\]; return YES; }' $N && grep -q 'UIKeyboardHIDUsageKeyboardM) { \[w minimize\]; return YES; }' $N \
   && ! grep -q 'dm_handleKey' ../statusbar/ActivityMonitor.h"
check "the window keys never swallow the system's Command shortcuts while a sheet is up" "grep -q 'if (m & (UIKeyModifierCommand | UIKeyModifierControl)) return NO;' $N"
[ $fails = 0 ] && echo "test-actmondock: all wiring checks pass" || { echo "test-actmondock: wiring checks FAILED"; exit 1; }
