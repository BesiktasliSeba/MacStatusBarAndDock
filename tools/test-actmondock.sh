#!/bin/bash
# Mac test of Activity Monitor in the Dock (1.7.3 item 5) and the App Library search's rules and window keys (item 13): the shared rules
# (common/ActMonDock.h, test-actmondock.m), and the wiring in the sources -- never in the Dock without the store's hook, nothing of ours in a layout
# file, the Dock-only rule, the record, its menus, the Dock's dot and Trash, the crash guard's rule, the search following the list's own text, and
# Command-W / Command-M for every native window.
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
check "a drag out of the Dock let go where nothing took it leaves the Dock (UIKit's own end of the drag, cancelled or forbidden, outside the Dock)" \
  "grep -q 'dragInteraction:session:didEndWithOperation:' $D && grep -q 'if (fromDock && outside && op <= 1)' $D"
check "its menu: Open, Add to Dock (greyed: Dock full) / Remove from Dock, run once the menu has closed" \
  "grep -q 'actionWithTitle:@\"Open\"' $D && grep -q 'actionWithTitle:@\"Add to Dock\"' $D && grep -q 'actionWithTitle:@\"Remove from Dock\"' $D \
   && grep -q 'add.subtitle = @\"Dock full\"' $D && grep -q 'performAfterIconContextMenuDismissesUsingBlock:' $D && grep -q 'return DMAMMenu(location);' $A"
check "a tap on its Dock icon opens the window directly (no App Library to dismiss)" "grep -q 'if (DMAMLocationIsDock(location)) {' $A && grep -q 'DMActivityMonitorOpen();' $A"
check "it follows Show in App Library (off: out of the Dock, the record kept)" \
  "grep -q 'DMAMApply(on);' $A && grep -q 'DMAMDockTakeOut(@\"Show in App Library switched off\", NO);' $D"
check "the Dock's running dot asks MacStatusBar (dlsym), and the Dock's Trash takes it out of the Dock" \
  "grep -q 'dlsym(RTLD_DEFAULT, \"MSBDOwnAppsRunning\")' ../dock/RunningIndicator.m && grep -q 'MSBDOwnAppsRunning(void)' $D \
   && grep -q 'dlsym(RTLD_DEFAULT, \"MSBDActMonDockRemove\")' ../dock/Dock.x && grep -q 'BOOL MSBDActMonDockRemove(void)' $D && grep -q 'DMIsOwnAppIcon(icon)' ../dock/Dock.x"
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
