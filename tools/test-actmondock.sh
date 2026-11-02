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
check "its display item for the recents is asked for once, only where the recents' hooks and list are in (or Command-Tab's, 1.7.8), its throw caught (every start asked it before, hooks or not)" \
  "grep -q 'id item = icons && gDMAMRecentsIvar ? DMAMRecentsItem() : nil;' $D && grep -q 'gDMAMRecentsPath = item ? 1 : 0;' $D && [ \$(grep -c 'DMAMRecentsItem()' $D) = 4 ] \
   && grep -q 'gDMAMCmdTabReady = init && view && picks && lookups > 0 && DMAMRecentsItem() != nil;' $D && grep -q 'gDMAMCmdTabReady && DMAMWindowExists() && DMALIcon() ? DMAMRecentsItem() : nil;' $D \
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
# 1.7.8 item 10: iPadOS's Command-Tab, while its window exists
check "Command-Tab: the switcher's view controller gets the recents with ours added -- a copy, where its last use puts it (the shared rule) -- never SpringBoard's recents controller" \
  "grep -q 'at = MSBDActMonCmdTabIndex(DMAMBundlesOf(items), gDMAMCmdTabSnapshot, gDMAMCmdTabUsed, DMAMActiveNow());' $D && grep -q 'id m = \\[items mutableCopy\\];' $D && grep -q '@try { r = o_DMAMCmdTabInit(self, _cmd, with); }' $D \
   && ! grep -q 'setRecentDisplayItems:' $D && ! awk '/^static id DMAMCmdTabInit/{f=1} f&&/_recentDisplayItemsController/{print \"bad\"} f&&/^}/{exit}' $D | grep -q bad"
check "  ... only while its window exists, with its icon and the pick hooked (SpringBoard would launch a bundle that is no app)" \
  "grep -q 'gDMAMCmdTabReady && DMAMWindowExists() && DMALIcon() ? DMAMRecentsItem() : nil;' $D && grep -q 'gDMAMCmdTabReady = init && view && picks && lookups > 0 && DMAMRecentsItem() != nil;' $D"
check "  ... its order: the recents noted when its window becomes the active one (the window's onActiveChanged), the apps seen in front since emptied" \
  "grep -q 'self.onActiveChanged = ^(DMNativeWindow \\*w, BOOL active) { if (active) DMAMCmdTabNoteActive(); };' ../statusbar/ActivityMonitor.h \
   && grep -q '^static void DMAMCmdTabNoteActive(void) { if (gDMAMCmdTabReady) { gDMAMCmdTabSnapshot = DMAMRecentsNow(); gDMAMCmdTabUsed = \\[NSMutableArray array\\]; } }' $D"
check "  ... and the apps seen in front since (what the recents can't tell: the app behind it brought forward again): every 0.2 s by the watcher, once SpringBoard has settled" \
  "grep -q '^    DMAMCmdTabTick();' ../statusbar/StatusBar.x && awk '/^static void DMSyncWindowsForLibraryBody\\(void\\) \\{/{f=1} f&&/^    DMAMCmdTabTick\\(\\);/{print \"in\"} f&&/^}/{exit}' ../statusbar/StatusBar.x | grep -q in \
   && grep -q 'if (!gDMAMCmdTabReady || !gDMAMCmdTabUsed || gNativeActive || !DMAMWindowExists()) return;' $D \
   && grep -q 'if (now < gDMAMCmdTabQuietUntil || DMSMWorkspaceBusy() || now - gSwitcherEventAt < 0.35 || DMSwitcherVisible() || DMLibraryVisible()) return;' $D \
   && grep -q 'DMAMCmdTabUsedApp(\\[DMActiveApp() bundleIdentifier\\]);' $D"
check "  ... not in the first 0.5 s after the native windows hand the screen back (a touch on another app's window brings it forward as the finger lifts)" \
  "grep -q 'static void DMAMCmdTabAppsForward(void) { gDMAMCmdTabQuietUntil = CACurrentMediaTime() + 0.5; }' $D \
   && awk '/^static void DMNativeSetActive\\(DMNativeWindow \\*w\\) \\{/{f=1} f&&/^    if \\(!w\\) DMAMCmdTabAppsForward\\(\\);/{print \"in\"} f&&/^}/{exit}' $N | grep -q in"
check "  ... its icon: the icon model answers ours for our identifier only while the switcher builds (its list, its view, a model change)" \
  "grep -q 'if (gDMAMCmdTabBuilding && \\[ident isEqual:kDMALActMonIdentifier\\]) { id i = DMALIcon();' $D && [ \$(grep -c 'gDMAMCmdTabBuilding++;' $D) = 3 ] && [ \$(grep -c 'gDMAMCmdTabBuilding--;' $D) = 3 ]"
check "  ... picked (a tap, or Command let go on it): the switcher goes and its window comes forward, never SpringBoard's launch -- hooked whatever the engine" \
  "awk '/^static void DMAMCmdTabSelected\\(/{f=1} f' $D | head -5 | tr -d '\\n' | grep -q 'if (DMAMCmdTabPicked(self, item)) return;    o_DMAMCmdTabSelected(self, _cmd, vc, item);    DMAMCmdTabOtherPicked(item);}' \
   && awk '/^static void DMAMCmdTabLaunch\\(/{f=1} f' $D | head -6 | tr -d '\\n' | grep -q 'id item = DMCall(DMALIvarObj(self, \"_commandTabViewController\"), @\"selectedApplicationDisplayItem\");    if (DMAMCmdTabPicked(self, item)) return;    o_DMAMCmdTabLaunch(self, _cmd);    DMAMCmdTabOtherPicked(item);}' \
   && grep -q 'dispatch_async(dispatch_get_main_queue(), ^{ DMAMBringForward(@\"Command-Tab\"); });' $D && grep -q 'DMMSWSwitchTo(at, @\"Command-Tab\", then);' $D"
check "  ... Command-Q on it closes its window and takes it out of the switcher; an app picked while a native window is active comes forward over it" \
  "grep -q 'for (DMNativeWindow \\*w in \\[gNativeWindows copy\\]) if (\\[w isKindOfClass:\\[DMActivityMonitorWindow class\\]\\]) \\[w close\\];' $D \
   && [ \$(grep -c 'DMNativeStepBack(@\"an app picked in Command-Tab\");' ../statusbar/StatusBar.x) = 2 ] && grep -q 'if (DMNativeAnyActive()) return item;' ../statusbar/StatusBar.x"
check "  ... another app picked: after SpringBoard's own pick the native windows step back and it counts as used -- every engine (with Stage Manager the app in front behind them stayed covered, iPad 2)" \
  "grep -q 'static void DMAMCmdTabOtherPicked(id item) { if (!item) return; DMNativeStepBack(@\"an app picked in Command-Tab\"); DMAMCmdTabUsedApp(DMCall(item, @\"bundleIdentifier\")); }' $D"
check "  ... Command-Tab brought up while its window is the active one: the first pick skips it, as SpringBoard's skips the app in front (with an engine SpringBoard starts on the first app: ours)" \
  "grep -q 'BOOL start = picks && DMALHook(@\"SBCommandTabController\", @\"_activateWithForwardDirection:\", @\"v@:B\", (IMP)DMAMCmdTabActivate, (IMP \\*)&o_DMAMCmdTabActivate);' $D \
   && awk '/^static void DMAMCmdTabActivate\\(/{f=1} f' $D | head -10 | tr -d '\\n' | grep -q 'id before = DMALIvarObj(self, \"_commandTabViewController\");    o_DMAMCmdTabActivate(self, _cmd, forward);    id vc = DMALIvarObj(self, \"_commandTabViewController\");    if (before || !vc || !forward || !gDMAMCmdTabReady || !DMAMActiveNow() || !DMAMIsRecentsItem(DMCall(vc, @\"selectedApplicationDisplayItem\"))) return;' \
   && awk '/^static void DMAMCmdTabActivate\\(/{f=1} f' $D | head -10 | grep -q '((void (\\*)(id, SEL))objc_msgSend)(self, NSSelectorFromString(@\"next\"));'"
check "  ... the engines' own Command-Tab hooks hand its item to its pick (the next app they take after the front window's can be it): never SpringBoard's launch" \
  "[ \$(grep -c 'if (DMAMCmdTabPicked((id)self, pick)) return;' ../statusbar/StatusBar.x) = 2 ] \
   && awk '/^%hook SBCommandTabController/{f=1} f&&/DMAMCmdTabPicked\\(\\(id\\)self, pick\\)/{p++} f&&/DMNativeStepBack\\(@\"an app picked in Command-Tab\"\\)/{if (p <= s) bad=1; s++} f&&/^%end/{exit} END{exit !(p == 2 && s == 2 && !bad)}' ../statusbar/StatusBar.x"
check "  ... whatever Show in App Library says (KT, review m2): its hooks go in at the start from the preferences' first read, outside that switch -- never with the App Library's and the Dock's on its first on -- and the list never asks that switch" \
  "awk '/Activity Monitor in the App Library: on unless switched off/{f=1} f&&/DMALApplyPref\\(al && !DMCtorSkip\\(\"applib\"\\)\\);/{a=NR} f&&/^        if \\(!DMCtorSkip\\(\"cmdtab\"\\)\\) DMAMCmdTabInstall\\(\\);/{b=NR} f&&/^    }/{exit} END{exit !(a && b > a)}' ../statusbar/StatusBar.x \
   && [ \$(grep -c 'DMAMCmdTabInstall();' $D ../statusbar/StatusBar.x ../statusbar/AppLibraryApps.h | awk -F: '{n+=\$2} END{print n}') = 1 ] \
   && ! awk '/^static id DMAMCmdTabInit\\(/{f=1} f&&/gDMALOn/{print \"bad\"} f&&/^}/{exit}' $D | grep -q bad"
check "  ... installed from our constructor (inside SpringBoard's start): SpringBoard's classes by name only, never its instances (sharedInstance there hung SpringBoard before its first frame, M1 ui01)" \
  "! awk '/^static void DMAMCmdTabInstall\\(void\\) \\{/{f=1} f&&/DMAMModel\\(\\)|sharedInstance|DMAMCmdTabController\\(\\)|DMAMRecentsNow\\(\\)|DMAMCmdTabNoteActive\\(\\)/&&!/\\/\\//{print \"bad\"} f&&/^}/{exit}' $D | grep -q bad \
   && grep -q 'NSString \\*modelClass = objc_getClass(\"SBIconModel\") ? @\"SBIconModel\" : objc_getClass(\"SBHIconModel\") ? @\"SBHIconModel\" : nil;' $D"
[ $fails = 0 ] && echo "test-actmondock: all wiring checks pass" || { echo "test-actmondock: wiring checks FAILED"; exit 1; }
