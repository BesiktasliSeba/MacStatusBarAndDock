#!/bin/bash
# Mac tests of the crash guard's step 1b (only what crashed goes off): the lookup (common/CrashFeature.h, test-crashfeature.m), the guard's order
# (common/CrashGuard.h + CrashStep.h, test-crashstep.c) and, if a package was built, the real CrashMap.txt against the real symbols.
# Writes to the Mac's preference domains com.besiktasliseba.macstatusbaranddock and com.besiktasliseba.test-crashstep (removed at the end).
set -e
cd "$(dirname "$0")"
FIXDIR="$PWD/crash-fixtures"
W=$(mktemp -d); export FIX="$FIXDIR" REPORTS="$W/reports"
cleanup() {   # (the domains go, and their empty files -- com.besiktasliseba.macstatusbar only when this script made it, for the Mac Switcher lines)
  for d in com.besiktasliseba.macstatusbaranddock com.besiktasliseba.test-crashstep com.besiktasliseba.test-crashstep.displays com.besiktasliseba.test-crashstep.dock ${MSW_DOMAIN_MADE:+com.besiktasliseba.macstatusbar}; do
    defaults delete $d >/dev/null 2>&1 || true
    defaults read $d >/dev/null 2>&1 || rm -f ~/Library/Preferences/$d.plist
  done
  rm -rf "$W"
}
if defaults read com.besiktasliseba.macstatusbaranddock >/dev/null 2>&1; then echo "the Mac has settings in com.besiktasliseba.macstatusbaranddock: not touching them"; exit 1; fi
trap cleanup EXIT
fails=0
echo "== lookup (synthetic map)"
TDISP=(-DMSBD_DISP_DOMAIN='"com.besiktasliseba.test-crashstep.displays"' -DMSBD_DISP_MSB_DOMAIN='"com.besiktasliseba.test-crashstep"' -DMSBD_DISP_DOCK_DOMAIN='"com.besiktasliseba.test-crashstep.dock"')   # (1.8.7: the displays domain and its parts' domains, test ones)
clang -fobjc-arc -Wall -Wno-unused-function -framework Foundation "${TDISP[@]}" -o "$W/tcf-synthetic" test-crashfeature.m
"$W/tcf-synthetic" "$FIXDIR" || fails=1
clang -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/tcf" test-crashfeature.m   # (the real domains: a built map's cases below)
echo "== guard order"
clang -fobjc-arc -dynamiclib -framework Foundation -framework CoreFoundation -DMSBD_CRASHMAP="\"$FIXDIR/test-crashmap.txt\"" "${TDISP[@]}" -o "$W/MacCrashBlame.dylib" ../loader/CrashBlameHelper.m ../loader/CrashFeatureHelper.m
clang -Wall -Wno-unused-function -framework CoreFoundation -DMSBD_GUARD_REPORTS="\"$REPORTS\"" -DMSBD_GUARD_VERDICTS="\"$W/verdicts.txt\"" \
  -DMSBD_GUARD_BLAME_LIB="\"$W/MacCrashBlame.dylib\"" -DMSBD_STEP_FILE="\"$W/step.txt\"" -DMSBD_CRASHMAP="\"$FIXDIR/test-crashmap.txt\"" \
  -DMSBD_GUARD_RECORD="\"$W/record.txt\"" -DMSBD_GUARD_RECENT="\"$W/recent.txt\"" \
  -DMSBD_DISP_DOMAIN="\"com.besiktasliseba.test-crashstep.displays\"" -DMSBD_DISP_MSB_DOMAIN="\"com.besiktasliseba.test-crashstep\"" \
  -o "$W/tcs" test-crashstep.c
run() {   # run <scenario> <fixture for 10:00> [<fixture for 10:01>]
  rm -rf "$REPORTS" "$W/verdicts.txt" "$W/step.txt" "$W/record.txt" "$W/recent.txt"; mkdir -p "$REPORTS"
  [ "$1" = recent ] && echo "$(date -j -f '%Y-%m-%d %H:%M:%S' '2026-09-26 09:59:30' +%s) com.besiktasliseba.test-crashstep recentSwitch Recent Switch" > "$W/recent.txt"
  defaults delete com.besiktasliseba.macstatusbaranddock >/dev/null 2>&1 || true; defaults delete com.besiktasliseba.test-crashstep >/dev/null 2>&1 || true
  defaults delete com.besiktasliseba.test-crashstep.displays >/dev/null 2>&1 || true
  cp "$FIXDIR/$2" "$REPORTS/SpringBoard-2026-09-26-100000.ips"
  [ -n "$3" ] && cp "$FIXDIR/$3" "$REPORTS/SpringBoard-2026-09-26-100100.ips"
  echo "-- $1"; "$W/tcs" "$1" || fails=1
}
run banners step1b-core-banners.ips step1b-core-banners-exception.ips
run parts step1b-dock.ips step1b-small-part.ips
echo "-- the loaders' skip list"
defaults write com.besiktasliseba.macstatusbaranddock crashGuardAction -int 4
"$W/tcs" skip MixAudio && r=0 || r=$?; [ $r = 10 ] && echo "PASS  MixAudio not loaded while the note is there" || { echo "FAIL  MixAudio skip ($r)"; fails=1; }
"$W/tcs" skip MacStatusBarCore && r=0 || r=$?; [ $r = 20 ] && echo "PASS  MacStatusBarCore still loaded" || { echo "FAIL  MacStatusBarCore ($r)"; fails=1; }
defaults delete com.besiktasliseba.macstatusbaranddock crashGuardAction
"$W/tcs" skip MixAudio && r=0 || r=$?; [ $r = 20 ] && echo "PASS  note cleared: MixAudio loads again" || { echo "FAIL  MixAudio after clearing ($r)"; fails=1; }
[ ! -e "$W/step.txt" ] && echo "PASS  note cleared: the skip list is removed" || { echo "FAIL  skip list still there"; fails=1; }
rm -f "$W/step.txt"; "$W/tcs" skip MixAudio && r=0 || r=$?; [ $r = 20 ] && echo "PASS  no skip list: everything loads" || { echo "FAIL  no list ($r)"; fails=1; }
# a piece (review of 1.8.6: the battery icon's plug, statusbar/BatteryMenu.h reads it by its target's name): off while the note is there, back once
# it is cleared (Turn Back On)
printf 'row 1\nskip batteryHoldPlug the battery icon|the plug in the battery icon during a charge hold\n' > "$W/step.txt"
defaults write com.besiktasliseba.macstatusbaranddock crashGuardAction -int 4
"$W/tcs" skip batteryHoldPlug && r=0 || r=$?; [ $r = 10 ] && echo "PASS  the plug (a piece) stays off while the note is there" || { echo "FAIL  the plug's skip ($r)"; fails=1; }
defaults delete com.besiktasliseba.macstatusbaranddock crashGuardAction
"$W/tcs" skip batteryHoldPlug && r=0 || r=$?; [ $r = 20 ] && [ ! -e "$W/step.txt" ] && echo "PASS  note cleared (Turn Back On): the plug comes back, the list goes" || { echo "FAIL  the plug after clearing ($r)"; fails=1; }
run apple apple-only-our-class-in-reason.ips apple-only-our-class-in-reason.ips
run mixed step1b-loader.ips step1b-dock-downloads.ips
run recent step1b-core-banners.ips step1b-core-banners.ips
run one step1b-core-banners.ips
run cclookup step1b-core-cc-lookup.ips step1b-core-cc-lookup.ips
run dockstyle step1b-dock-style.ips step1b-dock-style.ips
run dispon step1b-core-banners.ips step1b-core-banners-exception.ips
run dispdefault step1b-core-banners.ips
echo "== Fit to Window in the rules (no build needed): every function of it window code, Resize Apps to Fit Windows only its own two"
# (1.8.0 engine parity pass: ^_?DMFit took Fit's own functions to Resize Apps to Fit Windows, and the sections holding its tiles and the turn had no
#  rule, so DMAssignDefaultSlots, DMSlotFrame, the closure watcher and DMRelayoutForOrientation fell to Stock status bar mode)
python3 -I - crashmap-rules.txt ../statusbar/StatusBar.x <<'PY' || fails=1
import re, sys
rules, src = sys.argv[1], open(sys.argv[2], errors='replace').read()
sym, sec, fil = [], [], []
for raw in open(rules):
    line = re.split(r'\s+#', raw, 1)[0].strip()
    f = line.split()
    if len(f) == 4 and f[0] in ('sym', 'sec', 'file') and f[1] == 'MacStatusBarCore':
        (sym if f[0] == 'sym' else sec if f[0] == 'sec' else fil).append((re.compile(f[2]), f[3]))
def by_sym(name):   # (the first sym rule that matches wins, as make-crashmap.py: sym before sec before file)
    for rx, t in sym:
        if rx.search(name): return t
    return None
def by_file(name):
    for rx, t in fil:
        if rx.search(name): return t
    return None
bad = 0
def check(ok, what):
    global bad
    print(('PASS  ' if ok else 'FAIL  ') + what)
    if not ok: bad += 1
# Fit to Window's functions as StatusBar.x defines them (every DMFit... but Resize Apps to Fit Windows' own two, and its helpers by name), with blocks
fit = sorted(set(re.findall(r'^(?:static |void |BOOL |CGRect )[^(=;]*?\b(DMFit[A-Z]\w*)\(', src, re.M)) - {'DMFitIfNeeded', 'DMFitWindowContent'})
helpers = ['DMSetFitEnabled', 'DMInvalidateFitCache', 'DMStageTakesPartInFit', 'DMAssignDefaultSlots', 'DMAssignTilesKeepingPlaces', 'DMDefaultSlotNames',
           'DMSlotFrame', 'DMSlotNameForFrame', 'DMTilesText', 'DMMirrorSlot', 'DMApplyGroupSlots', 'DMWatchFitClosures', 'DMWatchFitToggle',
           'DMRelayoutForOrientation', 'DMRelayoutStageWhenLanded', 'DMRememberFitForFullScreen', 'DMSetSideChoiceGroup', 'DMSideChoiceFrame',
           'DMApplySideChoice', 'DMPromptForSide', 'DMPromptForSideApply', 'DMPromptBeforeLaunch', 'DMThirdWindowSides', 'DMLaunchIntoTile', 'DMPreSideTileFor',
           'DMNoFitFrame', 'DMMarkFreeWindow', 'DMTileOpenWindows', 'DMSpreadFitGroup']
missing = [h for h in helpers if not re.search(r'^static [^(=;]*?\b' + h + r'\(', src, re.M)]
check(len(fit) >= 9 and not missing, 'Fit to Window\'s functions found in StatusBar.x: %d DMFit... (%s) and %d helpers%s' % (len(fit), ', '.join(fit), len(helpers), (' -- not found: ' + ', '.join(missing)) if missing else ''))
wrong = [n for n in fit + helpers for v in ('_' + n, '___' + n + '_block_invoke', '___' + n + '_block_invoke_2.123') if by_sym(v) != 'windowingEnabled']
check(not wrong, 'each of them, its blocks too, is Windowing by name, whatever section it sits in' + (' -- not: ' + ', '.join(wrong) if wrong else ''))
flex = [n for n in ('_DMFitIfNeeded', '_DMFitWindowContent', '___DMFitIfNeeded_block_invoke', '___DMFitWindowContent_block_invoke') if by_sym(n) != 'flexResizeWindows']
check(not flex, 'Resize Apps to Fit Windows keeps its own two (DMFitIfNeeded, DMFitWindowContent)' + (' -- not: ' + ', '.join(flex) if flex else ''))
check(by_sym('_DMFitIfNeededX') != 'flexResizeWindows' and by_sym('_DMFitEnabled') == 'windowingEnabled', '  ... and only them (a longer name is Fit\'s)')
# the three sections around Fit's tiles and the turn: window code, no section left to Stock status bar mode
heads = [h.strip() for h in re.findall(r'^//\s?(?:----|====).*$', src, re.M)]
want = [h for h in heads if re.match(r'^//\s?-+\s(Window Size \(Settings >|the screen turns \(portrait|SofaScore quick relaunch)', h)]
got = [h for h in heads if any(rx.search(h) and t == 'windowingEnabled' for rx, t in sec)]
check(len(want) == 3 and all(h in got for h in want), 'the sections of the Window menu\'s layouts, the turn and SofaScore\'s relaunch are Windowing (%d of 3 found)' % len(want))
# "is a hardware keyboard attached?" (DMHardwareKeyboardAttached, at the end of the turn's section): asked by the keyboard pill, the engines' keyboard
# code, the desktop's keys, the Wi-Fi menu, the menus' key rows -- its caller's, transparent, as the shared Control Center lookups (code review 1.8.0)
kb = re.findall(r'^static BOOL (DMHardwareKeyboardAttached)\(void\) \{', src, re.M)
check(kb == ['DMHardwareKeyboardAttached'], 'DMHardwareKeyboardAttached found in StatusBar.x')
kbt = [by_sym(v) for v in ('_DMHardwareKeyboardAttached', '___DMHardwareKeyboardAttached_block_invoke', 'DMHardwareKeyboardAttached')]
check(kbt == ['transparent'] * 3 and by_sym('_DMHardwareKeyboardAttachedX') != 'transparent', 'DMHardwareKeyboardAttached and its once-only block are transparent by name (the caller decides), not the turn section\'s Windowing (got %s)' % kbt)
# Control Center's gallery on iPadOS 18 (code review 1.8.1, 7): the section of our Mac tiles is Control Center Style's, whose switch takes it away, not Show in App Library's, whose switch
# leaves the hook in; the rest of AppLibraryApps.h stays Show in App Library's. The Mac layout's header has a file rule: a function of it out of line in a release build fell to Stock status bar mode.
gal = [by_sym(v) for v in ('_DMALGalleryMerged', '___DMALGalleryMerged_block_invoke', '_DMALMacTilesSection', '_DMALMacTilesImage', '___DMALMacTilesImage_block_invoke')]
check(gal == ['controlcenter'] * 5, 'the Mac tiles\' section in the gallery, its blocks too, is Control Center Style (got %s)' % gal)
act = [by_sym(v) for v in ('_DMALCollIcon', '_DMALReload', '_DMALGalleryIconInit', '_DMALGalleryModules', '_DMALMenuConfig')]
check(act == ['actmonLibrary'] * 5, 'the rest of AppLibraryApps.h keeps Show in App Library (got %s)' % act)
check(by_sym('_MSBDCC18MacLayoutFrom') is None and by_sym('_MSBDCC18GridPlace') is None and by_file('CC18MacLayout.h') == 'controlcenter' and by_file('CC18Shape.h') == 'controlcenter' and by_file('CC18Tiles.h') == 'controlcenter', 'common/CC18MacLayout.h\'s functions, out of line, are Control Center Style by their file, as CC18Shape.h\'s')
# Swipe Up to Quit (review 1.8.6, gestures): both halves are its switch's -- the finger's flick and the trackpad's two-finger swipe, their blocks, the
# two-finger pan's forwarder and the rule's own functions --; the rest of the Mac Switcher (its drag among them) stays the Mac Switcher's
msw = open('../statusbar/MacSwitcher.h', errors='replace').read() + open('../statusbar/MSWFlick.h', errors='replace').read()
quit = ['DMMSWFlickEnd', 'DMMSWFlickQuit', 'DMMSWFlickable', 'DMMSWFlickOverDesks', 'DMMSWScrollPan', 'DMMSWScrollMayBegin', 'MSBDMSWFlickQuits', 'MSBDMSWFlickOverStrip', 'MSBDMSWScrollQuits']
gone = [n for n in quit if not re.search(r'^(?:__attribute__\(\(noinline\)\) )?static [^(=;]*?\b' + n + r'\(', msw, re.M)]
# (kept out of line in a release build, so the map has them by name: the swipe's own functions in MacSwitcher.h)
inl = [n for n in ('DMMSWFlickEnd', 'DMMSWFlickQuit', 'DMMSWFlickable', 'DMMSWScrollPan', 'DMMSWScrollMayBegin') if not re.search(r'^__attribute__\(\(noinline\)\) static [^(=;]*?\b' + n + r'\([^;]*\{', msw, re.M)]
check(not inl, 'the swipe\'s functions in MacSwitcher.h are kept out of line (a crash map has them by name)' + (' -- not: ' + ', '.join(inl) if inl else ''))
if '- (void)scroll:(UIPanGestureRecognizer *)g { DMMSWScrollPan(g); }' not in msw: gone.append('-[DMMSWTarget scroll:]')
check(not gone, 'Swipe Up to Quit\'s functions found in MacSwitcher.h and MSWFlick.h' + (' -- not found: ' + ', '.join(gone) if gone else ''))
wrong = [v for n in quit for v in ('_' + n, '___' + n + '_block_invoke', '___' + n + '_block_invoke_2') if by_sym(v) != 'mswSwipeUpQuit']
if by_sym('-[DMMSWTarget scroll:]') != 'mswSwipeUpQuit': wrong.append('-[DMMSWTarget scroll:]')
check(not wrong, 'each of them, its blocks too, and the two-finger pan\'s -[DMMSWTarget scroll:] is Swipe Up to Quit by name' + (' -- not: ' + ', '.join(wrong) if wrong else ''))
rest = [by_sym(v) for v in ('_DMMSWDragEnd', '_DMMSWDragPan', '___DMMSWDrop_block_invoke', '_DMMSWTapped')]
check(rest == ['macSwitcher'] * 4 and by_sym('-[DMMSWTarget pan:]') is None and by_sym('-[DMMSWTarget scroll:x]') is None and by_file('MacSwitcher.h') == 'macSwitcher',
      'the rest of the Mac Switcher stays its own (the drag, the drop, the taps by name; the pan\'s other forwarders by MacSwitcher.h; got %s)' % rest)
sys.exit(1 if bad else 0)
PY
echo "== the parts' names in the guard's words"
# (the Dock part is "the Dock": "SpringBoard crashed twice in the Dock, so the Dock was turned off for now." -- never MacDock, the name of
#  another tweak, in a text the user reads)
if grep -qx 'title DockMagnification the Dock|the Dock' crashmap-rules.txt && ! grep -E '^title ' crashmap-rules.txt | grep -q 'MacDock'; then
  echo "PASS  the Dock part is \"the Dock\" in the guard's words (footer, notice, Report a Problem), never MacDock"
else echo "FAIL  the Dock part's title in crashmap-rules.txt names MacDock"; fails=1; fi
echo "== the per-display settings in the rules (1.8.7, plans/design-1.8.7-displays.md section 8)"
python3 -I - crashmap-rules.txt ../common/DisplayPrefs.h <<'PY' || fails=1
import re, sys
rules, prefs = sys.argv[1], open(sys.argv[2]).read()
targets, sym, fil, dsym = {}, [], [], []
for raw in open(rules):
    line = re.split(r'\s+#', raw, 1)[0].strip()
    if not line or line.startswith('#'): continue
    f = line.split()
    if f[0] == 'target': targets[f[1]] = f[2:]
    elif len(f) == 4 and f[0] in ('sym', 'file') and f[1] == 'MacStatusBarCore': (sym if f[0] == 'sym' else fil).append((re.compile(f[2]), f[3]))
    elif len(f) == 4 and f[0] == 'sym' and f[1] == 'DockMagnification': dsym.append((re.compile(f[2]), f[3]))
def first(rs, name):
    for rx, t in rs:
        if rx.search(name): return t
    return None
bad = 0
def check(ok, what):
    global bad
    print(('PASS  ' if ok else 'FAIL  ') + what)
    if not ok: bad += 1
dom = re.search(r'#define MSBD_DISP_DOMAIN "([^"]+)"', prefs).group(1)
check(targets.get('displaySettings') == ['pref', dom, 'displaySettings', '0', '1', 'Display', 'Settings|the', 'per-display', 'settings'],
      'the layer\'s master switch: Display Settings in the displays domain (%s), set off (0), on when never set (1: absent is on)' % dom)
check(targets.get('displayScale', [None])[0:5] == ['pref', dom, 'displayScale', '0', '1'], 'More Space has its own switch in the same domain')
got = [first(sym, n) for n in ('_DMDispReload', '_DMDispRegistryUpdate', '___DMDispInit_block_invoke', '___DMDispAskNames_block_invoke_2', '_DMDispBool', '_DMDispWrite', '_DMDispBoolForKey', '_DMDispValueForKey')]
check(got == ['displaySettings'] * 8, 'the layer\'s functions and blocks by name (DMDisp...): Display Settings, no earlier rule takes them (got %s)' % got)
got = [first(sym, n) for n in ('_DMDispKeyOfScreen', '_DMDispDesktopScreen', '_MSBDDispGet', '_MSBDDispKeyOfScreen', '_MSBDDispConfigOfScreen')]
check(got == ['transparent'] * 5, '  ... the display key\'s derivation is passed over (Menu Bar Size, the TV\'s auto-hide and the Dock\'s auto-hide look keys up too, whatever the switch says): the caller decides (got %s)' % got)
got = [first(sym, n) for n in ('_DMDispKeyOfScreenX', '_DMDispDesktopScreens', '_DMDispScreens', '_DMDispKeyOfIdentity')]
check(got == ['displaySettings'] * 4, '  ... and only those: the layer\'s other DMDisp... stay Display Settings\' (got %s)' % got)
got = [first(dsym, n) for n in ('_DMDispKeyOfScreen', '_MSBDDispGet', '_DMDispBool', '_DMDispNum', '_DMDispReload', '___DMDispInit_block_invoke')]
check(got == ['transparent', 'transparent'] + ['displaySettings'] * 4, '  ... the Dock part\'s the same: its key derivation passed over, its getters and cache Display Settings\' (got %s)' % got)
check(first(sym, '_DMDisplayString') != 'displaySettings' and first(sym, '_DMDisposeX') != 'displaySettings', '  ... and only them (DMDisplay..., DMDispose... are not the layer)')
got = [first(fil, n) for n in ('DisplayPrefs.h', 'DisplayIdentity.h', 'DisplayRows.h', 'DisplaySettings.h')]
check(got == ['displaySettings'] * 4, 'its files (both DisplayPrefs.h, DisplayIdentity.h; DisplayRows.h, DisplaySettings.h from later commits): Display Settings (got %s)' % got)
got = [first(fil, 'SceneLayer.h'), first(sym, '_DMSceneLayerInScene'), first(sym, '___DMSceneLayerInScene_block_invoke'), first(sym, '_DMSceneLayersRelease')]
check(got == [None] * 4, '  ... not the per-scene layer helper (SceneLayer.h: 1.8.6\'s menu window on another display and the TV\'s strip, the status bar\'s: Stock status bar mode, as 1.8.6; got %s)' % got)
check(first(fil, 'DisplayTurn.h') != 'displaySettings' and first(fil, 'DisplaySpike.h') != 'displaySettings', '  ... not the screen turn\'s DisplayTurn.h or the debug spike\'s file')
got = [first(sym, n) for n in ('_DMDispPanelSendEvent', '_DMDispPanelTouch', '_DMDispPanelKeys')]
check(got == ['transparent', 'displaySettings', 'displaySettings'], 'the TV panel\'s -[SpringBoard sendEvent:] pass-through is passed over (on every touch stack), what it calls is Display Settings\' (got %s)' % got)
got = [first(fil, n) for n in ('MSWDisplays.h', 'MacSwitcher.h', 'MacSwitcherSM.h', 'MacSwitcherButton.h')]
check(got == ['macSwitcher'] * 4, 'the Mac Switcher\'s desktops per display (MSWDisplays.h) are the Mac Switcher\'s, with its other files (got %s)' % got)
sys.exit(1 if bad else 0)
PY
echo "== Window Tiling Shortcuts and Custom Shortcuts in the rules (review of 1.8.7: on for new installs, no rule named them; crashmap-keys-check.py)"
python3 -I crashmap-keys-check.py crashmap-rules.txt .. || fails=1
# made to fail: the rules without either switch's sym rule, with the file rule the review first suggested (it takes the title bar's records), without
# the rules' plain functions passed over, or with a switch that reads off when never set (step 1b would pass over it): each must fail the check
M3=$(mktemp -d)
grep -v '^sym MacStatusBarCore ^_\*(DMWinKey(' crashmap-rules.txt > "$M3/nowin.txt"
grep -v '^sym MacStatusBarCore ^_\*(DMCS(' crashmap-rules.txt > "$M3/nocs.txt"
{ echo 'file MacStatusBarCore ^WindowKeys\.h$ windowTilingKeys'; cat crashmap-rules.txt; } > "$M3/winfile.txt"
grep -v '^file MacStatusBarCore ^(WindowKeysRule|' crashmap-rules.txt > "$M3/notransparent.txt"
sed 's/^target customShortcuts pref com.besiktasliseba.customshortcuts enabled 0 1 /target customShortcuts pref com.besiktasliseba.customshortcuts enabled 0 0 /' crashmap-rules.txt > "$M3/default0.txt"
for m in nowin nocs winfile notransparent default0; do
  if cmp -s crashmap-rules.txt "$M3/$m.txt"; then echo "FAIL  made to fail ($m): the change did not apply"; fails=1
  elif python3 -I crashmap-keys-check.py "$M3/$m.txt" .. >/dev/null; then echo "FAIL  made to fail ($m): the check still passes"; fails=1
  else echo "PASS  made to fail ($m): the check fails"; fi
done
rm -rf "$M3"
echo "== every switch the guard sets off can be switched back on (review of 1.8.7: displaySettings / displayScale had no row; 1.8.6's batteryHoldPlug the same)"
python3 -I - crashmap-rules.txt .. <<'PY' || fails=1
import re, sys, glob, os, plistlib
rules, root = sys.argv[1], sys.argv[2]
targets = [m.groups() for m in re.finditer(r'^target (\S+) pref (\S+) (\S+) ', open(rules).read(), re.M)]
bundles = [os.path.join(root, 'statusbar/macstatusbarprefs'), os.path.join(root, 'dock/dockmagnificationprefs'), os.path.join(root, 'macsettings')]   # (macsettings: the Keyboard page's rows, Window Tiling Shortcuts and Custom Shortcuts)
rows = set()
def walk(o):
    if isinstance(o, dict):
        if isinstance(o.get('key'), str) and isinstance(o.get('defaults'), str): rows.add((o['defaults'], o['key']))
        for v in o.values(): walk(v)
    elif isinstance(o, list):
        for v in o: walk(v)
for b in bundles:
    for p in glob.glob(os.path.join(b, '**/*.plist'), recursive=True):
        try: walk(plistlib.load(open(p, 'rb')))
        except Exception: pass
code = ''.join(open(f, errors='ignore').read() for b in bundles for f in glob.glob(os.path.join(b, '**/*.[mhx]'), recursive=True))
defines = {}   # (a key's name through a #define of the common or status bar headers: kMSBDWallpaperPathKey, MSBD_DISP_MASTER_KEY ...)
for f in glob.glob(os.path.join(root, 'common/*.h')) + glob.glob(os.path.join(root, 'statusbar/*.h')):
    for m in re.finditer(r'^#define (\w+) +"([^"]+)"', open(f, errors='ignore').read(), re.M): defines.setdefault(m.group(2), set()).add(m.group(1))
missing = []
for name, dom, key in targets:
    if (dom, key) in rows or ('"%s"' % key) in code or any(re.search(r'\b%s\b' % d, code) for d in defines.get(key, ())): continue
    missing.append('%s (%s %s)' % (name, dom, key))
ok = not missing and len(targets) >= 40
print(('PASS  ' if ok else 'FAIL  ') + 'every pref target (%d) has a row in Settings that writes its key (a piece is brought back by Turn Back On)%s' % (len(targets), ' -- none for: ' + ', '.join(missing) if missing else ''))
m = open(os.path.join(root, 'statusbar/macstatusbarprefs/MSBRootListController.m')).read()
ok2 = 'set:@selector(msb_setDisplaySwitch:specifier:)' in m and '[master setProperty:@MSBD_DISP_MASTER_KEY forKey:@"msbdSwitch"];' in m and '[scale setProperty:@MSBD_DISP_SCALE_SWITCH_KEY forKey:@"msbdSwitch"];' in m
print(('PASS  ' if ok2 else 'FAIL  ') + '  ... Display Settings and More Space: their switches in Settings > Desktop > Displays')
sys.exit(0 if ok and ok2 else 1)
PY
M2=$(mktemp -d); mkdir -p "$M2/statusbar" "$M2/dock" "$M2/common"; cp -R ../statusbar/macstatusbarprefs "$M2/statusbar/"; cp -R ../dock/dockmagnificationprefs "$M2/dock/"; cp -R ../macsettings "$M2/"; cp ../common/*.h "$M2/common/"; cp ../statusbar/*.h "$M2/statusbar/"
sed -i '' 's/@MSBD_DISP_MASTER_KEY forKey/@"x" forKey/' "$M2/statusbar/macstatusbarprefs/MSBRootListController.m"
if sed -n '/^python3 -I - crashmap-rules.txt \.\. <<.PY/,/^PY$/p' test-crashstep.sh | sed '1d;$d' | python3 -I - crashmap-rules.txt "$M2" >/dev/null; then echo "FAIL  made to fail: Display Settings' switch row taken out, and the check still passes"; fails=1
else echo "PASS  made to fail: Display Settings' switch row taken out: the check fails"; fi
rm -rf "$M2"
echo "== the words (footer, notice, Report a Problem)"
clang -fobjc-arc -Wall -Wno-unused-function -framework Foundation -DMSBD_GUARD_RECORD="\"$W/words-record.txt\"" -o "$W/tse" test-stepexplain.m
"$W/tse" || fails=1
# The real map of the last build (if there is one): crashes placed in real functions must find the right switch.
MAP=../.theos/_/var/jb/usr/lib/MacStatusBarAndDock/CrashMap.txt
DSYM=   # (the symbols of the build the map was made from: release or test build)
for o in ../.theos/obj ../.theos/obj/debug; do
  c=$o/arm64e/MacStatusBarCore.dylib.dSYM/Contents/Resources/DWARF/MacStatusBarCore.dylib
  [ -f "$c" ] && [ -f "$MAP" ] && grep -q "$(dwarfdump --uuid "$c" | awk '{print tolower($2)}')" "$MAP" && DSYM=$c
done
if [ -f "$MAP" ] && [ -n "$DSYM" ]; then
  echo "== the built map ($(wc -c < "$MAP" | tr -d ' ') bytes)"
  real() {   # real <name> <expected answer> <fixture args...>
    local n=$1 want=$2; shift 2
    python3 make-crash-fixture.py "$W/$n.ips" "$@" >/dev/null && "$W/tcf" "$MAP" "$W/$n.ips" "$want" || fails=1
  }
  D=com.besiktasliseba.macstatusbar
  ccmac() {   # ccmac <real|cclook> <args...>: a line in our Control Center's code, with Control Center Style "mac" stored (ours runs only when picked,
              # KT 3 Nov: nothing stored is not ours) -- in this Mac's $D domain, made for it and removed again; skipped when the Mac has that domain
    if defaults read $D >/dev/null 2>&1; then echo "SKIP  $2: this Mac has a $D domain (not touched)"; return; fi
    MSW_DOMAIN_MADE=1; defaults write $D controlCenterStyle -string mac
    "$@"
    defaults delete $D >/dev/null 2>&1 || true
  }
  real core-banner "pref MacStatusBarCore $D bannerStyle 0 *" --symbol "$DSYM" MacStatusBarCore 'logos_method\$MacBanners\$'
  real core-menu "pref MacStatusBarCore $D stockStatusBar 1 *" --symbol "$DSYM" MacStatusBarCore 'DMShowMenu|DMMenuWindow|DMMenu'
  # (auto-hide is off on this Mac, as for a new user: a crash in its code can't be the switch, so Stock status bar mode instead)
  real core-autohide "pref MacStatusBarCore $D stockStatusBar 1 *" --symbol "$DSYM" MacStatusBarCore '^_DMAutoHide'
  # the per-display settings (1.8.7): the registry and a getter are Display Settings' (nothing stored on this Mac: on); the display key's derivation is
  # its caller's (under a getter: Display Settings; under the TV's auto-hide: auto-hide, off here, so Stock status bar mode); the per-scene layer
  # helper (1.8.6's TV menu window, the TV's strip) the status bar's: Stock status bar mode, as 1.8.6
  DD=com.besiktasliseba.macstatusbar.displays
  if defaults read $DD >/dev/null 2>&1; then echo "SKIP  the per-display settings' built-map cases: this Mac has a $DD domain (not touched)"; else
    real core-disp-registry "pref MacStatusBarCore $DD displaySettings 0 *" --symbol "$DSYM" MacStatusBarCore '^_DMDispRegistryUpdate$'
    real core-disp-getter-key "pref MacStatusBarCore $DD displaySettings 0 *" --symbol "$DSYM" MacStatusBarCore '^_DMDispKeyOfScreen$' --then '^_DMDispBool$'
    real core-disp-autohide-key "pref MacStatusBarCore $D stockStatusBar 1 *" --symbol "$DSYM" MacStatusBarCore '^_DMDispKeyOfScreen$' --then '^_DMAutoHide'
    real core-scenelayer "pref MacStatusBarCore $D stockStatusBar 1 *" --symbol "$DSYM" MacStatusBarCore '^___DMSceneLayerInScene_block_invoke$'
  fi
  # Window Tiling Shortcuts and Custom Shortcuts (review of 1.8.7): never set on this Mac, so on (their default 1): a crash in their key code is their
  # own switch's, not Stock status bar mode; a rule's plain function is its caller's; the title bar's records in WindowKeys.h, the shortcuts' load and
  # Yours over a built-in stay with the status bar. (A map built before these rules has no target for them: skipped, as a stale build.)
  if ! grep -q '^T windowTilingKeys ' "$MAP"; then echo "SKIP  the keyboard shortcuts' built-map cases: the map was built before their rules"
  elif defaults read $D windowTilingKeys >/dev/null 2>&1 || defaults read com.besiktasliseba.customshortcuts >/dev/null 2>&1; then echo "SKIP  the keyboard shortcuts' built-map cases: this Mac has their switches set (not touched)"
  else
    real core-winkeys "pref MacStatusBarCore $D windowTilingKeys 0 *" --symbol "$DSYM" MacStatusBarCore '^_DMWinKeyRun$'
    real core-winkeys-arrange "pref MacStatusBarCore $D windowTilingKeys 0 *" --symbol "$DSYM" MacStatusBarCore '^___DMArrangeWindows_block_invoke$'
    real core-winkeys-press "pref MacStatusBarCore $D windowTilingKeys 0 *" --symbol "$DSYM" MacStatusBarCore '^_MSBDWinKeyFor$' --then '^_DMWinKeysPressesBegan$'
    real core-cshort "pref MacStatusBarCore com.besiktasliseba.customshortcuts enabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_DMCSRunOnce$'
    real core-cshort-app "pref MacStatusBarCore com.besiktasliseba.customshortcuts enabled 0 *" --symbol "$DSYM" MacStatusBarCore '^___DMCSPublishStates_block_invoke$'
    real core-titlerecord "pref MacStatusBarCore $D stockStatusBar 1 *" --symbol "$DSYM" MacStatusBarCore '^_DMTitleRecordView$'
    real core-cshort-load "pref MacStatusBarCore $D stockStatusBar 1 *" --symbol "$DSYM" MacStatusBarCore '^_DMCSLoad$'
    real core-kc-yours "pref MacStatusBarCore $D stockStatusBar 1 *" --symbol "$DSYM" MacStatusBarCore '^_DMKCYoursPublish$'
  fi
  real core-aerial "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore 'logos_method\$AerialStyle\$'
  # (the app exit hook, on every engine since 1.4.2 -- its own group, no longer AerialSpringBoard: Windowing, not Stock status bar mode)
  real core-appexit "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore 'logos_method\$AppExitForget\$'
  # the Stage Manager engine (its functions, its hook groups, the window fit and the stage-area hook, 1.3.2): Windowing off, the Mac status bar stays
  # (iPadOS 18's gallery: the Mac tiles' section is Control Center Style's, code review 1.8.1, 7)
  ccmac real core-gallery-merged "pref MacStatusBarCore $D controlCenterStyle 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMALGalleryMerged$'
  ccmac real core-gallery-section "pref MacStatusBarCore $D controlCenterStyle 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMALMacTilesSection$'
  real core-sm-zoom "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMToggleZoom$'
  real core-sm-fit "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMAttrsFitScreen'
  real core-sm-hook16 "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMConstrainEdges16'
  real core-sm-group "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore 'logos_method\$SMLayout16\$'
  # force quit: the Apple menu's and the app icons' (MSBDForceQuitApp, 1.3.5): Windowing off, not the traffic lights or the whole part (R2-L1)
  real core-forcequit "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMForceQuitBundle$'
  real core-forcequit-export "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?MSBDForceQuitApp$'
  real core-appswithwindows "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?MSBDAppsWithWindows$'
  # (its blocks -- the kill and the switcher clean-up after the window closed -- fell to their section before, 1.3.5 round 2 R3-L3; a DMSM function's
  #  block in StatusBar.x the same way)
  real core-forcequit-block "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^___DMForceQuitBundle_block_invoke'
  real core-sm-block "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^___DMSMWindowActionAs_block_invoke'
  # (the menu-closing wait of window changes and its poll's block, which closes SpringBoard's icon menu after 2 s: Windowing, not "part" -- L-3)
  real core-ctxwait "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMWaitForMenuToClose$'
  real core-ctxpoll "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^___DMContextMenuPoll_block_invoke'
  # (sm-desktop: the Home Screen behind the windows, the desktop join of SpringBoard's own transitions and its rule's blocks, the strip gate)
  real core-sm-desk "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMDeskHomeBehind$'
  real core-sm-joinasked "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMJoinStageAsked$'
  real core-sm-joinblock "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^___DMSMDeskJoinPlan_block_invoke'
  real core-sm-apiblock "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^___DMSMRequestPlan(Ex|Act)?_block_invoke'
  real core-sm-strip "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMStripRevealBegin$'
  # Stage Manager held off / given back (1.3.4): Control Center's button and its installer, SpringBoard's switch handler that waits
  real core-sm-button "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore 'logos_method\$StageManagerButton\$'
  real core-sm-buttonhook "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMInitStageManagerButtonHook$'
  real core-sm-offwait "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMDefaultChangeHook$'
  # (sm-nolimit: Apple's window limit answered by us, the role table, the Fit plan for more than four windows)
  real core-sm-limit "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMMaxAppsOnStage$'
  real core-sm-roles "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMRolesDerive$'
  real core-sm-fitplan "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMFitPlanDecide$'
  # (1.3.6: one window, one role -- the context put right before SpringBoard reads it, and its rule)
  real core-sm-rolerepair "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMRepairRoles$'
  real core-sm-rolerepairplan "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMRoleRepairPlan$'
  # (sm-free: the windows stay at Home -- the rewrite, its rule, the Home gesture's blur answer)
  real core-sm-home "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMHomeKeepsDesktop$'
  real core-sm-homeplan "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMHomePlan$'
  real core-sm-homeblur "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMHGBlurProgress$'
  # (1.3.8 logic test fixes: the App Switcher's bookkeeping after finalize, our own real Home request, the desktop choice of the joins and the restore)
  real core-sm-homenote "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMHomeNoteResult$'
  real core-sm-realhome "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMRequestRealHome$'
  real core-sm-desktopfor "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMDesktopFor$'
  # (1.3.9: the windows keep still during a Home gesture with Reduce Motion off -- the decision the gesture's frame and scale answers read)
  real core-sm-homestill "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMHGStill$'
  # (sm-multiwin, M-2: each window known by its own scene -- the window's entity, its lookup by key, a card's key on every card layout, the window
  #  keys' own header, force quit's later closes of the app's other windows)
  real core-sm-winentity "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMEntityForStageItem$'
  real core-sm-winitem "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMItemFor$'
  real core-sm-cardkey "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMCardKey$'
  real core-sm-keyset "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMKeySetHas$'
  real core-sm-fqblock "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^___DMSMForceQuitWindows_block_invoke'
  # (the Mac Switcher, 1.4: its Stage Manager desktops' functions and blocks, the Home button's blocks -> its own switch; the blocks fell to Stock
  #  status bar mode in the 1.4~int6 map. Its switch is off by default -- a crash then falls to Stock status bar mode -- so it is on for these lines,
  #  in this Mac's com.besiktasliseba.macstatusbar domain, which is removed again; skipped when the Mac has that domain already)
  # the shared Control Center lookups (1.8.0: transparent), with a trap in Apple code above them: the caller one frame lower decides. Only the
  # lookups this build has as functions (a release build inlines MSBDControlCenterController), in their calling order, then the caller.
  LOOKS=$(nm -s __TEXT __text "$DSYM" | sed -n -E 's/^[0-9a-f]+ [tT] _(MSBDControlCenterController|DMControlCenterController|DMControlCenterActive|DMCCTypes|DMCCGet|DMCCIvarOf)$/\1/p')
  cclook() {   # cclook <name> <expected answer> <caller regex> <lookup>...
    local n=$1 want=$2 caller=$3 l top= more=(); shift 3
    for l in "$@"; do echo "$LOOKS" | grep -qx "$l" || continue; if [ -z "$top" ]; then top="^_?$l\$"; else more+=(--then "^_?$l\$"); fi; done
    [ -n "$top" ] || { echo "FAIL  $n: none of the lookups ($*) in this build"; fails=1; return; }
    real "$n" "$want" --symbol "$DSYM" MacStatusBarCore "$top" "${more[@]}" --then "$caller" --apple-top
  }
  if ! defaults read $D >/dev/null 2>&1; then
    MSW_DOMAIN_MADE=1; defaults write $D macSwitcher -bool YES
    # (the Mac Switcher's Home button asks whether Control Center is up: its own switch)
    cclook core-cclook-msw "pref MacStatusBarCore $D macSwitcher 0 *" '^_?DMMSWHomeDoubleTakesOver$' MSBDControlCenterController DMControlCenterController DMControlCenterActive
    real core-msw-sm "pref MacStatusBarCore $D macSwitcher 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMMSWSMJoin$'
    real core-msw-sm-block "pref MacStatusBarCore $D macSwitcher 0 *" --symbol "$DSYM" MacStatusBarCore '^___DMMSWSMSwitch_block_invoke'
    real core-msw-button-block "pref MacStatusBarCore $D macSwitcher 0 *" --symbol "$DSYM" MacStatusBarCore '^___DMMSWHomeDoubleTakesOver_block_invoke'
    defaults delete $D >/dev/null 2>&1 || true
  else echo "SKIP  the Mac Switcher lines: this Mac has a $D domain (not touched)"; fi
  # every Stage Manager hook group of this build (%group SM...): Windowing off -- 16.0's SMLayout160 / SMGrid160 fell to the image's target in the
  # first 1.3.4 build (the stock status bar instead, logic test); a new SM group must not
  smgroups=$(nm -s __TEXT __text "$DSYM" | grep -oE 'logos_method\$SM[A-Za-z0-9]*\$' | sed 's/^logos_method\$//; s/\$$//' | sort -u)
  n=$(echo "$smgroups" | grep -c . || true)
  [ "$n" -ge 7 ] && echo "PASS  $n Stage Manager hook groups in the build: $(echo $smgroups)" || { echo "FAIL  only $n Stage Manager hook groups found: $(echo $smgroups)"; fails=1; }
  for g in $smgroups; do
    real "core-sm-group-$g" "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore "logos_method\\\$${g}\\\$"
  done
  # the keyboard section (its header names the keyboard button; the code runs for the window engines): Windowing, not the keyboard button -- off
  # for new users, so a crash there fell to Stock status bar mode, which keeps the engines running (1.4.2). Symbols kept in a release build too.
  real core-kb-pillin "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMPlaceKeyboardPillIn$'
  real core-kb-hostscene "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMKeyboardHostOwningScene$'
  real core-kb-sceneside "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSceneSide$'
  real core-kb-orientblock "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^___DMFixKeyboardOrientation_block_invoke'
  real core-fit-spreadblock "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^___DMSpreadFitGroup_block_invoke'
  real core-context "part MacStatusBarCore - - 0 the status bar|the Mac status bar" --symbol "$DSYM" MacStatusBarCore 'logos_method\$MacContextMenus\$'
  real core-today "pref MacStatusBarCore $D clockOpensToday 0 *" --map "$MAP" MacStatusBarCore arm64 clockOpensToday
  real dock-downloads "pref DockMagnification com.besiktasliseba.dockmagnification showDownloads 0 *" --map "$MAP" DockMagnification arm64e showDownloads
  real dock-part "part DockMagnification - - 0 the Dock|the Dock" --map "$MAP" DockMagnification arm64 part
  # Dock Style (1.8.4, review P2-L1): this Mac has no Dock Style stored (Default): a crash in its code is not Dock Style's -- the part
  real dock-style "part DockMagnification - - 0 the Dock|the Dock" --map "$MAP" DockMagnification arm64e dockStyle
  # the Dock's two 1.8.4 hooks (the platter's layout, the icon tap) are transparent: Apple's crash under one of them alone is the part's, never
  # Dock Style's or the bounce's (the symbols of the Dock part of the build the map was made from)
  DSYMD=
  for o in ../.theos/obj ../.theos/obj/debug; do
    d=$o/arm64e/DockMagnification.dylib.dSYM/Contents/Resources/DWARF/DockMagnification.dylib
    [ -f "$d" ] && grep -q "$(dwarfdump --uuid "$d" | awk '{print tolower($2)}')" "$MAP" && DSYMD=$d
  done
  if [ -n "$DSYMD" ]; then
    real dock-hook-layout "part DockMagnification - - 0 the Dock|the Dock" --symbol "$DSYMD" DockMagnification 'SBFloatingDockPlatterView\$layoutSubviews$' --apple-top
    real dock-hook-tap "part DockMagnification - - 0 the Dock|the Dock" --symbol "$DSYMD" DockMagnification 'SBIconView\$tapGestureDidChange\$$' --apple-top
  else echo "FAIL  no DockMagnification symbols for the built map"; fails=1; fi
  # Finder (Finder.h / NativeWindow.h / its glue in StatusBar.x): Finder's own switch, not the whole status bar; FinderIcon.m: the Dock's Finder
  real core-finder-window "pref MacStatusBarCore $D finderEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^-\[DMFinderWindow dm_run'
  real core-finder-native "pref MacStatusBarCore $D finderEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMNativeTouchBegan'
  real core-finder-glue "pref MacStatusBarCore $D finderEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMOpenFinderFileMenu'
  real core-finder-icontap "pref MacStatusBarCore $D finderEnabled 0 *" --symbol "$DSYM" MacStatusBarCore 'logos_method\$DMNativeHooks\$SBIconView'
  real core-finder-drag "pref MacStatusBarCore $D finderEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMFinderDragMove'
  real core-finder-keys "pref MacStatusBarCore $D finderEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMNativeHandlePress'
  real dock-finder "pref DockMagnification com.besiktasliseba.dockmagnification showFinder 0 *" --map "$MAP" DockMagnification arm64e showFinder
  # P4's trap (1.8.0~i11, M1): +[SBControlCenterController sharedInstance] entered again under MSBDControlCenterController <- DMControlCenterController
  # <- DMControlCenterActive <- our Control Center's sensor update: Control Center Style back to iPadOS's, not Stock status bar mode (the lookups
  # were the Stock status bar's code); a getter under our Control Center's code the same (DMCCGet was RAM & CPU's add's: the whole part)
  ccmac cclook core-cclook-sensor "pref MacStatusBarCore $D controlCenterStyle 0 *" '^_?DMCCPSensorUpdate$' MSBDControlCenterController DMControlCenterController DMControlCenterActive
  ccmac cclook core-cclook-getter "pref MacStatusBarCore $D controlCenterStyle 0 *" '^_?DMCCPAppleSize$' DMCCGet
  # (the lookups' other callers: their own targets -- the battery menu's Control Center icon, the menu bar's hook keeping iOS's bar, the tick, RAM &
  #  CPU's add's hooks; the tick and those hooks are pinned by their own rules: the engine notice's section and a %group header held them)
  cclook core-cclook-battery "pref MacStatusBarCore $D batteryMenu 0 *" '^_?DMBattOpenControlCenter$' MSBDControlCenterController DMControlCenterController DMControlCenterActive
  cclook core-cclook-keepbar "pref MacStatusBarCore $D stockStatusBar 1 *" 'logos_method\$_ungrouped\$UIStatusBar_Modern\$setAlpha\$$' MSBDControlCenterController DMControlCenterController DMControlCenterActive
  cclook core-cclook-tick "pref MacStatusBarCore $D stockStatusBar 1 *" '^_?DMTickBody$' MSBDControlCenterController DMControlCenterController DMControlCenterActive
  cclook core-cclook-autoadd "part MacStatusBarCore - - 0 the status bar|the Mac status bar" 'logos_method\$CCAutoAddWatch\$SBControlCenterController\$_willPresent$' DMCCGet
  # "is a hardware keyboard attached?" (code review 1.8.0): transparent, so a trap under it is its caller's -- the desktop's keys and the Wi-Fi
  # menu their own switches, the menus' key rows (a section with no rule) Stock status bar mode, the keyboard pill and the Stage Manager desktop
  # Windowing -- not the turn section's Windowing for all. The callers this build has as functions (a release build inlines some).
  KB=$(nm -s __TEXT __text "$DSYM" | sed -n -E 's/^[0-9a-f]+ [tT] _(DMHardwareKeyboardAttached|DMDesktopKeysFocus|DMWiFiShowPasswordSheet|DMShortcutRow|DMPlaceKeyboardPill|DMSMDeskOutsideTouch)$/\1/p')
  if echo "$KB" | grep -qx DMHardwareKeyboardAttached; then
    nkb=0
    for c in "desktop desktopIcons 0 DMDesktopKeysFocus" "wifi wifiMenu 0 DMWiFiShowPasswordSheet" "menurow stockStatusBar 1 DMShortcutRow" "pill windowingEnabled 0 DMPlaceKeyboardPill" "smdesk windowingEnabled 0 DMSMDeskOutsideTouch"; do
      read -r kn kt ko kf <<< "$c"
      echo "$KB" | grep -qx "$kf" || continue
      nkb=$((nkb+1)); real "core-hwkb-$kn" "pref MacStatusBarCore $D $kt $ko *" --symbol "$DSYM" MacStatusBarCore '^_?DMHardwareKeyboardAttached$' --then "^_?$kf\$" --apple-top
    done
    [ $nkb -ge 2 ] && echo "PASS  $nkb callers of DMHardwareKeyboardAttached in this build checked: each its own switch" || { echo "FAIL  only $nkb of its callers found in this build"; fails=1; }
  else echo "PASS  DMHardwareKeyboardAttached inlined into its callers in this build: they decide (nothing of its own in the map)"; fi
  real core-tick "pref MacStatusBarCore $D stockStatusBar 1 *" --symbol "$DSYM" MacStatusBarCore '^_?DMTickBody$'
  real core-autoadd-hook "part MacStatusBarCore - - 0 the status bar|the Mac status bar" --symbol "$DSYM" MacStatusBarCore 'logos_method\$CCAutoAddWatch\$'
  # (1.8.0, KT 3 Nov: our Control Center's Airplane Mode row -- the block that asks AppSupport's RadiosPreferences on our queue, the delegate it
  #  tells -- is the tiles' code: Control Center Style back to iPadOS's, as for every Mac tile)
  ccmac real core-cc-airplane "pref MacStatusBarCore $D controlCenterStyle 0 *" --symbol "$DSYM" MacStatusBarCore '^___DMCCTAirplaneSet_block_invoke'
  ccmac real core-cc-airplane-delegate "pref MacStatusBarCore $D controlCenterStyle 0 *" --symbol "$DSYM" MacStatusBarCore 'DMCCTAirplaneDelegate airplaneModeChanged'
  # (our Control Center's layout, common/CCLayout.h: not inlined in a release build -- MSBDCCLayout fell to Stock status bar mode)
  ccmac real core-cc-layout "pref MacStatusBarCore $D controlCenterStyle 0 *" --symbol "$DSYM" MacStatusBarCore '^_?MSBDCCLayout$'
  # (nothing stored -- this Mac --: our Control Center is not the style, so a crash in its code is not Control Center Style's: Stock status bar mode)
  real core-cc-layout-unset "pref MacStatusBarCore $D stockStatusBar 1 *" --symbol "$DSYM" MacStatusBarCore '^_?MSBDCCLayout$'
  # Fit to Window (1.8.0 engine parity pass): its functions Windowing, by name -- ^_?DMFit took them to Resize Apps to Fit Windows, their sections fell
  # to Stock status bar mode --, with the window code of the sections around them (the Window menu's layouts, the turn); Resize Apps to Fit Windows
  # keeps its own two. Every one this build has as a function (a release build inlines some).
  TEXT=$(nm -s __TEXT __text "$DSYM")
  nfit=0
  for f in DMFitGroupForget DMFitEnabled DMFitInto DMFitRepairOverlappingSlots DMFitWatchSync DMFitFullScreenAppGone DMFitRejoinAfterFullScreen DMAssignDefaultSlots DMAssignTilesKeepingPlaces \
           DMSlotFrame DMSlotNameForFrame DMWatchFitClosures DMWatchFitToggle DMRelayoutForOrientation DMRelayoutStageWhenLanded DMApplyGroupSlots DMTileOpenWindows DMWindowLayout DMSendToWindow DMScaleFrame; do
    echo "$TEXT" | grep -q " _$f\$" || continue
    nfit=$((nfit+1)); real "core-fit-$f" "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore "^_?$f\$"
  done
  [ $nfit -ge 6 ] && echo "PASS  $nfit of Fit to Window's functions (and the window code around them) in this build checked: Windowing" || { echo "FAIL  only $nfit of Fit to Window's functions found in this build"; fails=1; }
  for f in DMFitIfNeeded DMFitWindowContent; do
    echo "$TEXT" | grep -q " _$f\$" && real "core-flex-$f" "pref MacStatusBarCore $D flexResizeWindows 0 *" --symbol "$DSYM" MacStatusBarCore "^_?$f\$"
  done
else
  echo "== (no built map: build the package to test it)"
fi
[ $fails = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
