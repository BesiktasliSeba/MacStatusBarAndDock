#!/bin/bash
# Mac test of App Window Sizes (1.8.8, KT 12 Nov: Settings > Windows & Multitasking > Window Size > App Window Sizes, a launch size per app:
# Small, Medium, Large, Fill or iPhone): the rule in common/AppWindowSize.h (test-appwindowsize.m on the header as built: the read rule, which size
# wins over Window Size and New Windows Open at Fill, Fit to Window leaving the window out, the frames on the iPads' and the TVs' desktops, the
# change list the forget runs on, the first read only setting the baseline), that the header is plain C with no dash a reader would see, then
# made-to-fail copies of the header (each must fail). Then C2's sites in StatusBar.x (Aerial, Zetsu, MilkyWay4: the opening frame, the cascade and
# Fit, the side question, the green light's record, the prefs read and the forget on change, the debug triggers) and the crash piece's rules, with
# their made-to-fail copies. Then C3's: our Stage Manager engine on the iPad and the TV (the opening frame by the display it joins, the join's
# cascade then free, the side question, the forget on change of Stage Manager's places), DMSMOpeningFrameIn built from StatusBar.x as it is and
# run on the iPad's and the TVs' desktops, with their made-to-fail copies. Then C4's: the Settings pages (the row under Window Size with its count,
# the list, Add App on AltList's picker by name only, the app's page, the one write, the texts), with their made-to-fail copies.
# Review R1 of the port onto 1.8.7.7 (1.8.7.5's behind-the-Dock mark goes with the place the forget takes): its C2 and C3 site checks among the
# others, Stage Manager's forget built from StatusBar.x as it is and run, their made-to-fail copies, and the files before its fix failing each.
# F1 (the A12Z's S1 on 18.5: a pick in Add App left the picker up): Add App on the navigation stack Settings builds on 15 to 17 and on 18
# (test-appsizestack.m runs the list's methods as written on stand-in stacks of both shapes), its made-to-fail copies, the files before the fix.
# F2 (row A6 on three iPads in s01: a second iPhone window over Fit's tiles went up and left over the first's traffic lights): the C test on
# made-to-fail copies of WindowSize.h's cascade, and on the WindowSize.h before the fix.
# F3 (the A12Z's G1 and the iPad 2's A12b in s01: a stored value that is not a dictionary read as no app with nothing logged; the green light's
# windows listed by the smfit trigger as full screen after they became windows): the read rule's report in the C test, DMAppSizesLoad built from
# StatusBar.x as written and run on G1's reads, DMSMFitTick's bookkeeping of the windows that went full screen pasted as written and run on A12b
# and its neighbours, their made-to-fail copies, and the files before the fix.
# The review of F1-F4 (Aerial, Zetsu and MilkyWay4 left the other window in its half when the app quit while full screen after a size change; Stage
# Manager filled it): the forget takes only the way back into the Fit tile (c_forget and its made-to-fail copy; test-fitgreen runs the code).
# G1 (KT's decision b: Stage Manager keeps the tiles while a tiled window is full screen out of sight, as Aerial): c3_unchanged reads the tick
# without G1's lines (g1drop), F3's run gives its cut the windows full screen out of sight; test-smfitfullaway runs the code.
# S1-F1 (row E1 of p03, A12Z 18.5: F1's pick left two empty hosting controllers on Settings' stack): test-appsizestack.m's fourth shape, SwiftUI's
# record of the stack, with one change to the stack at a time (the picker closed with a slide, the page pushed from the list settled); c4_setter's
# and c4_stack's site lines, their made-to-fail copies, and F1 as committed (da581859 / cfe5a4c6) failing on SwiftUI's record only.
# H3 (the iPad 2's C14 of p03: a window back from full screen into its kept tile stayed full screen's while another tile was minimized):
# c3_unchanged reads the tick also without H3's two calls of DMSMFitBackInTile (h3drop); test-smfitfullaway runs them.
# H2 (KT's decision A: minimized tiled windows keep their tiles on every engine): c3_unchanged reads the tick also without H2's lines (h2drop);
# test-fitminimized runs them.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
H=../common/AppWindowSize.h
EM=$(printf '\342\200\224'); EN=$(printf '\342\200\223')   # (the em and en dash, spelled by their bytes so this file has neither)
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
rule() {   # rule <AppWindowSize.h> <dir> [WindowSize.h]: the C test built on that header (beside this tree's WindowSize.h, or the one given, and WindowMinSize.h); its exit code, 3 if it does not build
  mkdir -p "$2/common" "$2/statusbar" "$2/tools"
  cp "$1" "$2/common/AppWindowSize.h"; cp "${3:-../common/WindowSize.h}" "$2/common/WindowSize.h"; cp ../statusbar/WindowMinSize.h "$2/statusbar/"; cp test-appwindowsize.m "$2/tools/"
  clang -O2 -fobjc-arc -Wall -Werror -Wno-unused-function -framework Foundation -framework CoreGraphics -o "$2/t" "$2/tools/test-appwindowsize.m" > "$2/build" 2>&1 || return 3
  "$2/t"
}
rule $H "$W/as-built" || fails=1
check "the header is plain C (CoreFoundation and CoreGraphics only), clean under -Wall -Werror, read by SpringBoard and Settings alike" \
  "printf '#include \"%s\"\nint main(void) { return MSBDOpeningSize(MSBDAppSizeNone, 0, false); }\n' \"\$PWD/$H\" > $W/c.c && clang -x c -std=c11 -fsyntax-only -Wall -Wextra -Werror -Wno-unused-parameter $W/c.c \
   && ! grep -q '@interface\|@implementation\|#import\|NSString\|NSDictionary' $H"
check "  ... it starts from Window Size's rule (WindowSize.h) and keeps the names the design gives (the key, the limit, the five choices, the phone)" \
  "grep -q '#include \"WindowSize.h\"' $H && grep -q '#define kMSBDAppWindowSizesKey \"appWindowSizes\"' $H && grep -q '#define kMSBDAppWindowSizesMax 200' $H \
   && grep -q '#define kMSBDPhoneW 393.0' $H && grep -q '#define kMSBDPhoneH 852.0' $H \
   && grep -q 'enum { MSBDAppSizeNone = -1, MSBDAppSizeSmall = 1, MSBDAppSizeLarge = 2, MSBDAppSizeMedium = 3, MSBDAppSizeFill = 4, MSBDAppSizeIPhone = 5 };' $H \
   && grep -q 'enum { kMSBDOpenFill = 4, kMSBDOpenIPhone = 5 };' $H"
check "no em or en dash in the header or this test" "! grep -q \"\$EM\\|\$EN\" $H test-appwindowsize.m test-appwindowsize.sh"
echo "-- made-to-fail copies (each must fail):"
mtf() {   # mtf <name> <perl substitution>
  local d="$W/mtf$((++n))"; mkdir -p "$d"; cp $H "$d/AppWindowSize.h"; perl -0pi -e "$2" "$d/AppWindowSize.h"
  cmp -s $H "$d/AppWindowSize.h" && { echo "FAIL  made-to-fail copy $1: the change did not apply"; fails=1; return; }
  rule "$d/AppWindowSize.h" "$d/tree" > "$d/out" 2>&1 && rc=0 || rc=$?
  if [ $rc = 3 ]; then echo "FAIL  made-to-fail copy $1 does not build (it must build and fail)"; head -5 "$d/tree/build"; fails=1
  elif [ $rc = 0 ]; then echo "FAIL  made-to-fail copy $1 PASSED (it must fail)"; fails=1
  else echo "PASS  made-to-fail copy $1 fails, as it must ($(grep -c '^FAIL:' "$d/out") checks)"; fi
}
n=0
mtf "the app's choice ignored (every app as no entry)" 's/    switch \(app\) \{\n        case MSBDAppSizeSmall: return MSBDWindowSizeSmall;/    switch (MSBDAppSizeNone + 0 * app) {\n        case MSBDAppSizeSmall: return MSBDWindowSizeSmall;/'
mtf "New Windows Open at Fill winning over the app's choice" 's/(static inline int MSBDOpeningSize\(int app, int windowSize, bool fillOn\) \{\n)/$1    if (fillOn) return kMSBDOpenFill;\n/'
mtf "the phone not scaled (the M1 in landscape: 393 wide, cut at the desktop)" 's/double k = fmin\(1\.0, fmin\([^\n]*\);/double k = 1.0;/'
mtf "the minimum dropped (a 289 pt phone on the iPad 2)" 's/fmax\(appW, min\.width\)/appW/; s/fmax\(appH \+ bar, min\.height\)/appH + bar/'
mtf "Medium as the 66% x 74% share (the internal medium layout)" 's/case MSBDAppSizeMedium: return MSBDWindowSizeDefault;/case MSBDAppSizeMedium: return 3;/; s/(        case kMSBDOpenIPhone: return MSBDWindowPhoneIn\(u, bar, min\);\n)/$1        case 3: return MSBDWindowMinSlotOf(MSBDWindowShareIn(u, 0.66, 0.74), 0, u, min);\n/'
mtf "no entry changing 1.8.7's answer (Open at Fill not read)" 's/default: return fillOn \? kMSBDOpenFill : windowSize;/default: return windowSize;/'
mtf "no entry's free window not 1.8.7's (Open at Fill not read)" 's/\(MSBDAppSizeValid\(app\) \|\| fillOn\)/MSBDAppSizeValid(app)/'
mtf "Aerial 3.0: an app at Medium taken as plain Default" 's/return !MSBDAppSizeValid\(app\) && !fillOn/return (!MSBDAppSizeValid(app) || app == MSBDAppSizeMedium) && !fillOn/'
mtf "the change list answering the first read's bundles (the baseline not kept)" 's/    if \(!baselineSet\) return CFArrayCreate\(kCFAllocatorDefault, NULL, 0, &kCFTypeArrayCallBacks\);\n//'
mtf "a NULL table read as {} (a slip forgets every app)" 's/    if \(!before \|\| !after\) return out;/    if (!after) return out;\n    if (!before) before = CFDictionaryCreate(kCFAllocatorDefault, NULL, NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);/'
mtf "the change list reading only the new table (a removed app not forgotten)" 's/    for \(int t = 0; t < 2; t\+\+\) \{/    for (int t = 1; t < 2; t++) {/'
mtf "the change list not sorted" 's/    CFArraySortValues\(out, CFRangeMake\(0, CFArrayGetCount\(out\)\), MSBDAppBundleCompare, NULL\);\n//'
mtf "the read rule: no 200 limit" 's/if \(i >= kMSBDAppWindowSizesMax\)/if (0)/'
mtf "the read rule: the 200 taken in the dictionary's order, not by key" 's/    CFArraySortValues\(good, CFRangeMake\(0, g\), MSBDAppBundleCompare, NULL\);\n//'
mtf "the read rule: any key length (an empty or 256-character key read)" 's/return n >= 1 && n <= kMSBDAppBundleMaxLength;/return n >= 0;/'
mtf "the read rule: a text in another case read (\"Small\")" 's/!strcmp\(text, "small"\)/!strcasecmp(text, "small")/'
mtf "F3: a stored value of another type not reported (read as no app with nothing to log, as on the A12Z)" 's/\*wrongType = stored && CFGetTypeID\(stored\) != CFDictionaryGetTypeID\(\) \? CFGetTypeID\(stored\) : 0;/*wrongType = 0;/'
mtf "F3: a dictionary reported as of another type too" 's/\*wrongType = stored && CFGetTypeID\(stored\) != CFDictionaryGetTypeID\(\) \? CFGetTypeID\(stored\) : 0;/*wrongType = stored ? CFGetTypeID(stored) : 0;/'
mtf "the read rule bypassed for the values (any string an entry)" 's/MSBDAppBundleKeyValid\(keys\[i\]\) && MSBDAppSizeFromStored\(\(CFTypeRef\)vals\[i\]\) != MSBDAppSizeNone/MSBDAppBundleKeyValid(keys[i]) \&\& CFGetTypeID(vals[i]) == CFStringGetTypeID()/'
# (C4, Settings' side of the header)
mtf "Settings writing an empty dictionary (the key not removed with the last app)" 's/    if \(CFDictionaryGetCount\(d\) == 0\) \{ CFRelease\(d\); return NULL; \}\n//'
mtf "Settings' write rebuilding the list (an entry it cannot read, a future choice, dropped)" 's/\? CFDictionaryCreateMutableCopy\(kCFAllocatorDefault, 0, \(CFDictionaryRef\)stored\)/? CFDictionaryCreateMutable(kCFAllocatorDefault, 0, \&kCFTypeDictionaryKeyCallBacks, \&kCFTypeDictionaryValueCallBacks)/'
mtf "Medium's footer naming Window Size's Default (amendment 2)" 's/(        case MSBDAppSizeFill: return "The window fills the desktop.";\n)/$1        case MSBDAppSizeMedium: return "Medium is Window Size\x27s Default.";\n/'
mtf "a sixth choice on the app's page (Custom)" 's/        case 4: return MSBDAppSizeIPhone;\n/        case 4: return MSBDAppSizeIPhone;\n        case 5: return 6;\n/'
mtf "the 200 limit off (Add App with 200 listed)" 's/return listed >= 0 && listed < kMSBDAppWindowSizesMax;/return listed >= 0;/'
mtf "the row's count \"1 Apps\"" 's/n == 1 \? "%ld App" : "%ld Apps"/"%ld Apps"/'
mtf "Remove App leaving the entry (None writes nothing)" 's/        \} else if \(choice == MSBDAppSizeNone\) CFDictionaryRemoveValue\(d, bundle\);\n/        }\n/'

# ---- C2 (design 5.1): Aerial, Zetsu, MilkyWay4 in StatusBar.x, the crash piece's rules ----------------------------------------------------------
# Each site check is a function of the files it reads (StatusBar.x, crashmap-rules.txt), so a copy of a source with one site broken runs the same
# checks: those made-to-fail copies, after, must each fail, and so must the files before C2 (7137b2f1).
S=../statusbar/StatusBar.x; C=crashmap-rules.txt
f1() { awk -v head="$1" 'index($0, head) == 1 {f=1} f {print} f && /^}/ {exit}' "$2"; }   # f1 <first line> <file>: that function, to its closing brace
order() { A="$1" B="$2" awk 'index($0, ENVIRON["A"]) && !x {x=NR} index($0, ENVIRON["B"]) && !y {y=NR} END {exit !(x && y && x < y)}' "$3"; }   # order <a> <b> <file>: a's first line before b's (as written: no awk escapes)
sites=(
"the opening frame for the app it is of: the app's own size first, else Fill with Open at Fill, else Window Size (MSBDOpeningSize); Fill the engine's Fill layout, the rest Window Size's window or the phone (1.8.7's window exactly with no entry)|c_opening"
"  ... the one window: Default the center layout, Small and Large Window Size's as in 1.8.7, iPhone the phone under our 24 pt bar with the engines' minimum, in the same desktop; Window Size's other uses ask Window Size alone|c_window"
"no DMOpeningWindowFrame() left: every opening site of Aerial, Zetsu and MilkyWay4 asks DMOpeningWindowFrameFor with its app (MilkyWay4's new window, Zetsu's adopt, the green light's way back, Aerial's cascade, its windowed launch and its warm start)|c_sites"
"the side question's launches, No Fit's window and the layouts ask no app size (Window Size's own, 1.2)|c_notsites"
"DMCascadeStage: the app's size read once; Aerial 3.0 keeps its own frame only at Window Size's plain Default; the Fill branch by the rule (an app at Fill too); an own-size opening goes to regularWindow, is let through its first line and is marked free only after MSBDWindowCascadeIn has picked its place (1.3: cascade, then free)|c_cascade"
"the way back with no last place still reaches DMCascadeStage on every flavour: Aerial 3.0's DMStyleStage asNew, Aerial 5.x's new stage, Zetsu's adopt, MilkyWay4's 0.6 s call (1.5)|c_wayback"
"no side question for an app with its own size: DMThirdWindowSides asks MSBDOpensFree (with no entry MSBDNewWindowAtFill exactly)|c_side"
"the green light keeps the window's place on Aerial and Zetsu as on MilkyWay4: DMRememberStageFrame after the context menu's wait and before the closing mark; their only caller is DMStageLightAction's green branch (1.9, amendment 6)|c_green"
"the prefs read: DMLoadPrefs reads appWindowSizes through the read rule only (MSBDAppSizesRead), the first read sets the baseline and forgets nothing (MSBDAppSizesToForget with gAppSizesRead, set after), the table never nil after it, each changed app to the forget|c_load"
"DMAppSizeOf: one lookup in the table, none with the crash guard's piece off (read once, appWindowSizes); the load reads and forgets nothing then|c_piece"
"the forget on change: where the window last was, the way back into the Fit tile for full screen (not the record: a quit while full screen still closes the tile up, as on Stage Manager), the saved window state's lastFrames (DMForgetSavedLastFrame, not DMSaveWindowState), Stage Manager's places (DMSMAppSizeForgetPlace, with every engine: amendment 6), the apps forgotten since the start; nothing else (no free or minimized mark, no stage, no Mac Switcher record)|c_forget"
"  ... 1.8.7.5's behind-the-Dock mark goes with the place the forget takes (review R1): a window that opens with no place of its own kept takes it on MilkyWay4 (DMEnlargeNewWindow, the green light's way back too), Zetsu (DMZetsuAdopt, read before the move records the new place) and Aerial (DMCascadeStage, every flavour); the forget itself leaves it (a window still open behind the Dock keeps it)|c_behind"
"  ... the saved window state: DMForgetSavedLastFrame and DMSaveWindowState write on one writer (DMWindowStateWriter), only lastFrames is changed, nothing written without the app's entry; DMRestoreLastFrames skips an app forgotten since the start|c_saved"
"  ... Stage Manager's file: only its preZoom, the places in memory as they are, on the file's own queue (DMSMStateWriteQueue)|c_smsaved"
"the debug triggers (appsizes, appsize_<bundle>): debug builds only, read only (nothing written, set or forgotten)|c_debug"
"the crash guard's piece: target appWindowSizes, a sym rule naming its functions (each defined in StatusBar.x) before Stage Manager's DMSM rule, AppWindowSize.h's file rule above WindowSize.h's; the opening frame stays window code|c_rules"
)
c_opening() {
  f1 'static CGRect DMOpeningWindowFrameFor(NSString *bundle) {' "$1" > "$W/of" && grep -qF 'int app = DMAppSizeOf(bundle), s = MSBDOpeningSize(app, gWindowSizeChoice, gNewWindowsFill);' "$W/of" \
    && order 'if (s == kMSBDOpenFill) {' 'return DMLayoutFrame(@"fill");' "$W/of" && grep -qF 'return DMA5StageFromWindow(DMNewWindowFrameWindowAt(s));' "$W/of" \
    && [ "$(grep -c 'return' "$W/of")" = 2 ] && ! grep -q 'gWindowSizeChoice\b.*==\|DMNewWindowFrame()' "$W/of" \
    && grep -qF 'static CGRect DMOpeningWindowFrameFor(NSString *bundle);' "$1" && ! grep -q 'static CGRect DMOpeningWindowFrame(void)' "$1"
}
c_window() {
  f1 'static CGRect DMNewWindowFrameWindowAt(int choice) {' "$1" > "$W/nw" && grep -qF 'if (choice == MSBDWindowSizeDefault) return DMLayoutFrameWindow(@"center");' "$W/nw" \
    && grep -qF 'if (choice == kMSBDOpenIPhone) { DM_FEATURE_MARK("app-window-size-iphone"); return MSBDWindowPhoneIn(u, kMSBDWindowBarHeight, MSBDWindowMinSize()); }' "$W/nw" \
    && grep -qF 'return MSBDWindowSizeFrameIn(choice, u, scr, DMCenterTopFor(scr), MSBDWindowMinSize());' "$W/nw" \
    && order 'if (CGRectGetMinY(u) < bar) u = CGRectMake(' 'if (choice == kMSBDOpenIPhone)' "$W/nw" && ! grep -q 'gWindowSizeChoice\|DMAppSizeOf' "$W/nw" \
    && grep -qF 'static CGRect DMNewWindowFrame(void) { return DMA5StageFromWindow(DMNewWindowFrameWindowAt(gWindowSizeChoice)); }' "$1" \
    && f1 'static CGRect DMNoFitFrame(void) {' "$1" | grep -qF 'return DMNewWindowFrame();' && ! grep -q 'DMNewWindowFrameWindow()' "$1"
}
c_sites() {
  ! grep -q 'DMOpeningWindowFrame()' "$1" && [ "$(grep -c 'DMOpeningWindowFrameFor(\(bundle\|bundleID\|me\))' "$1")" = 6 ] \
    && f1 'static BOOL DMEnlargeNewWindow(UIView *window) {' "$1" > "$W/mw" && grep -qF ': DMOpeningWindowFrameFor(bundle);' "$W/mw" && grep -qF 'if (![bundle isKindOfClass:[NSString class]]) bundle = nil;' "$W/mw" \
    && f1 'static void DMZetsuAdopt(UIWindow *w) {' "$1" | grep -qF '(lastPlace ? lastPlace.CGRectValue : DMOpeningWindowFrameFor(bundleID)));' \
    && f1 'static void DMWindowLayout(NSString *name) {' "$1" | grep -qF 'if (gPreferRememberedFrame) target = gLastWindowFrames[bundleID] ? gLastWindowFrames[bundleID].CGRectValue : DMOpeningWindowFrameFor(bundleID);' \
    && f1 'static void DMCascadeStage(UIView *stage) {' "$1" | grep -qF 'CGRect want = remembered ? DMFitInto(remembered.CGRectValue, usable) : DMOpeningWindowFrameFor(me);' \
    && f1 'static BOOL DMWindowedLaunch(NSString *bundleID) {' "$1" | grep -qF 'CGRect target = DMOpeningWindowFrameFor(bundleID);' \
    && f1 'BOOL DMAerialWarmStartIfNeeded(NSString *bundleID) {' "$1" | grep -qF 'CGRect target = gLastWindowFrames[bundleID] ? gLastWindowFrames[bundleID].CGRectValue : DMOpeningWindowFrameFor(bundleID);'
}
c_notsites() {
  for h in 'static void DMLaunchIntoTile(NSString *bundleID, CGRect frame) {' 'static void DMPromptBeforeLaunch(NSString *newBundle, NSString *leftBundle, NSString *rightBundle, void (^launch)(CGRect frame)) {' \
           'static CGRect DMNoFitFrame(void) {' 'static void DMApplyGroupSlots(UIView *fresh) {' 'static CGRect DMLayoutFrameInArea(NSString *name, CGRect u, CGSize screen) {'; do
    f1 "$h" "$1" > "$W/ns" && [ -s "$W/ns" ] && ! grep -q 'DMAppSizeOf\|DMOpeningWindowFrameFor\|kMSBDOpenIPhone' "$W/ns" || return 1
  done
}
c_cascade() {
  f1 'static void DMCascadeStage(UIView *stage) {' "$1" > "$W/cs" && [ "$(grep -c 'DMAppSizeOf(' "$W/cs")" = 1 ] && grep -qF '    int app = DMAppSizeOf(me);' "$W/cs" \
    && grep -qF 'BOOL a3Sized = gAerialFlavor == 3 && DMActiveEngine() == DMEngineAerial && !MSBDOpeningIsPlainDefault(app, gWindowSizeChoice, gNewWindowsFill) && !gLastWindowFrames[me];' "$W/cs" \
    && grep -qF 'BOOL atFill = MSBDNewWindowAtFill(MSBDOpeningSize(app, gWindowSizeChoice, gNewWindowsFill) == kMSBDOpenFill, own, preLaunched);' "$W/cs" \
    && grep -qF 'BOOL ownSizeOpening = fitOn && !atFill && MSBDOpensFree(app, gNewWindowsFill, own, preLaunched);' "$W/cs" \
    && order '    if (atFill) {' 'BOOL ownSizeOpening = ' "$W/cs" && order '    if (ownSizeOpening) goto regularWindow;' 'if (fitOn && [gFreeWindows containsObject:me]) goto regularWindow;' "$W/cs" \
    && order 'if (fitOn && [gFreeWindows containsObject:me]) goto regularWindow;' '    if (fitOn) {' "$W/cs" \
    && awk '/^regularWindow:;$/ {getline; print; exit}' "$W/cs" | grep -qxF '    if ([gFreeWindows containsObject:me] && !ownSizeOpening) return;   // (No Fit: it stays in the middle, where it was opened, even over the tiles)' \
    && awk '/CGRect pick = MSBDWindowCascadeIn\(base, otherFrames, nOthers, usable, ownPlace, &how\);/ {p=NR} /DMMarkFreeWindow\(me\);/ && p && !m {m=NR} /if \(how == MSBDCascadeOwnKept\) \{/ && p {k=NR} END {exit !(p && m > p && k > m)}' "$W/cs" \
    && awk '/^regularWindow:;$/ {r=1} r && /DMMarkFreeWindow\(me\)/ {n++} END {exit !(n == 1)}' "$W/cs" && awk '/    if \(ownSizeOpening\) \{/ {getline; getline; print; exit}' "$W/cs" | grep -qF 'DMMarkFreeWindow(me);'
}
c_wayback() {
  f1 'static void DMStyleStage(UIView *stage) {' "$1" | grep -qF 'dispatch_async(dispatch_get_main_queue(), ^{ if (asNew) DMCascadeStage(stage); DMBeginStageEntrance(stage, inner); });' \
    && f1 'static void DMAerial5AdoptNewStage(UIView *stage) {' "$1" | grep -qF 'if (DMAerialGreenOpensNew(bundle)) { DM_FEATURE_MARK("aerial-green-new-window"); DMCascadeStage(stage); }' \
    && f1 'static void DMZetsuAdopt(UIWindow *w) {' "$1" | grep -qF 'DMCascadeStage(s); DMZetsuFixScale(s); DMSaveWindowState();' \
    && grep -qF 'UIView *w = weakCreated; if (w && w.superview && !DMWindowMinimized(w)) DMCascadeStage(w); });' "$1" \
    && f1 'static void DMWindowLayout(NSString *name) {' "$1" > "$W/wl" && grep -qF 'gPendingWindowFrame = target;' "$W/wl" && grep -qF 'BOOL asked = !gPreferRememberedFrame || gLastWindowFrames[bundleID] != nil;' "$W/wl"
}
c_side() {
  f1 'static BOOL DMThirdWindowSides(NSString *bundleID, NSString **leftOut, NSString **rightOut) {' "$1" | grep -qF 'if (!MSBDFitTakesOpening(YES, MSBDOpensFree(DMAppSizeOf(bundleID), gNewWindowsFill, DMOpensAtOwnPlace(bundleID), NO))) return NO;'
}
c_green() {
  f1 'static void DMAerialToFullScreen(UIView *stage) {' "$1" > "$W/af" && order 'if (DMWaitForContextMenu(' '    DMRememberStageFrame(stage);' "$W/af" \
    && order '    DMRememberStageFrame(stage);' 'objc_setAssociatedObject(stage, kStageClosingKey, @YES' "$W/af" && [ "$(grep -c 'DMRememberStageFrame(' "$W/af")" = 1 ] \
    && f1 'static void DMZetsuToFullScreen(UIWindow *w) {' "$1" > "$W/zf" && order 'if (DMWaitForContextMenu(' '    DMRememberStageFrame((UIView *)w);' "$W/zf" \
    && order '    DMRememberStageFrame((UIView *)w);' 'UIWindow *host = DMStatusBarWindow();' "$W/zf" \
    && f1 'static void DMExpandWindowToFullScreen(AXWindowView *window, NSString *bundleID, id sender) {' "$1" | awk 'NR == 3' | grep -qF 'DMRememberStageFrame((UIView *)window);' \
    && [ "$(grep -c 'DMAerialToFullScreen(stage);\|DMZetsuToFullScreen((UIWindow \*)stage);\|DMZetsuToFullScreen(w); })' "$1")" = 4 ] \
    && f1 'static void DMStageLightAction(UIView *stage, NSInteger which) {' "$1" | order 'DMRememberFitForFullScreen(bundleID);' 'else DMAerialToFullScreen(stage);' /dev/stdin
}
c_load() {
  f1 'static void DMLoadPrefs(void) {' "$1" > "$W/lp" && [ "$(grep -c '    DMAppSizesLoad();' "$W/lp")" = 1 ] && ! grep -q 'kMSBDAppWindowSizesKey' "$W/lp" \
    && f1 'static void DMAppSizesLoad(void) {' "$1" > "$W/al" && grep -qF 'CFPropertyListRef v = CFPreferencesCopyValue(CFSTR(kMSBDAppWindowSizesKey), MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);' "$W/al" \
    && grep -qF 'NSDictionary *now = CFBridgingRelease(MSBDAppSizesRead(v, &bad, &over, &wrong));' "$W/al" && [ "$(grep -c '\bv\b' "$W/al")" = 3 ] \
    && grep -qF 'NSArray<NSString *> *forget = CFBridgingRelease(MSBDAppSizesToForget(gAppSizesRead, (__bridge CFDictionaryRef)gAppSizes, (__bridge CFDictionaryRef)now));' "$W/al" \
    && order 'MSBDAppSizesToForget(gAppSizesRead,' 'gAppSizes = now ?: @{}; gAppSizesRead = YES;' "$W/al" && order 'gAppSizes = now ?: @{}; gAppSizesRead = YES;' 'for (NSString *b in forget) DMAppSizeForgetPlace(b);' "$W/al" \
    && [ "$(grep -c 'DMAppSizeForgetPlace(' "$W/al")" = 1 ] && [ "$(grep -cE '^ +(.*; )?gAppSizes = ' "$1")" = 1 ] && [ "$(grep -c 'gAppSizesRead = YES' "$1")" = 1 ] && [ "$(grep -c 'DMAppSizesLoad()' "$1")" = 1 ] \
    && [ "$(grep -c 'CFSTR(kMSBDAppWindowSizesKey)' "$1")" = 2 ] && grep -qF 'static BOOL gAppSizesRead = NO;' "$1"
}
c_piece() {
  grep -qF '#define MSBD_APP_SIZES_PIECE "appWindowSizes"' "$1" && grep -qF 'static BOOL DMAppSizesSkipped(void) { static int s = -1; if (s < 0) s = MSBDCrashSkipped(MSBD_APP_SIZES_PIECE); return s != 0; }' "$1" \
    && f1 'static int DMAppSizeOf(NSString *bundle) {' "$1" > "$W/so" && grep -qF 'DMAppSizesSkipped()) return MSBDAppSizeNone;' "$W/so" \
    && grep -qF 'return MSBDAppSizeIn((__bridge CFDictionaryRef)gAppSizes, (__bridge CFStringRef)bundle);' "$W/so" \
    && f1 'static void DMAppSizesLoad(void) {' "$1" | awk 'NR == 2' | grep -qxF '    if (DMAppSizesSkipped()) return;'
}
c_forget() {
  f1 'static void DMAppSizeForgetPlace(NSString *bundle) {' "$1" > "$W/fp" && grep -qF '[gLastWindowFrames removeObjectForKey:bundle];' "$W/fp" \
    && grep -qxF '    DMFitForgetFullScreenWayBack(bundle, @"has a new size (App Window Sizes)");' "$W/fp" && ! grep -q 'DMFitForgetFullScreenTile' "$W/fp" && grep -qF '    DMForgetSavedLastFrame(bundle);' "$W/fp" \
    && grep -qF '    DMSMAppSizeForgetPlace(bundle);' "$W/fp" && grep -qF '[gAppSizeForgotten addObject:bundle];' "$W/fp" \
    && ! grep -q 'DMSaveWindowState\|gFreeWindows\|gSMFreeWindows\|Minimized\|gMSW\|DMMSW\|Stage(\|removeAllObjects\|gSMTurn\|gFitGroup\|gFitSlots' "$W/fp" \
    && [ "$(grep -c 'removeObjectForKey' "$W/fp")" = 1 ] && [ "$(grep -c 'DMAppSizeForgetPlace(b)\|DMAppSizeForgetPlace(bundle)' "$1")" = 1 ]
}
c_behind() {   # (review R1 of the port: the mark is the place's, gBehindDock "goes when the app exits" with gLastWindowFrames; the forget takes the place alone)
  order 'static void DMBehindDockSet(NSString *bundle, BOOL behind, NSString *why);' 'static BOOL DMEnlargeNewWindow(UIView *window) {' "$1" \
    && f1 'static BOOL DMEnlargeNewWindow(UIView *window) {' "$1" > "$W/bm" \
    && grep -qxF '    if (bundle && !gLastWindowFrames[bundle]) DMBehindDockSet(bundle, NO, @"its window opens with no place of its own kept (App Window Sizes)");' "$W/bm" \
    && order 'if (remembered && !pending) DMMarkOwnPlace(window, big);' 'if (bundle && !gLastWindowFrames[bundle]) DMBehindDockSet(' "$W/bm" \
    && order 'if (bundle && !gLastWindowFrames[bundle]) DMBehindDockSet(' 'if (CGRectEqualToRect(window.frame, big)) return NO;' "$W/bm" \
    && f1 'static void DMZetsuAdopt(UIWindow *w) {' "$1" | awk 'index($0, "    NSValue *lastPlace = gLastWindowFrames[bundleID];") == 1 {getline; print; exit}' \
       | grep -qF '    if (!lastPlace) DMBehindDockSet(bundleID, NO, @"its window opens with no place of its own kept (App Window Sizes)");' \
    && f1 'static void DMCascadeStage(UIView *stage) {' "$1" > "$W/bc" \
    && grep -qF '    if (DMActiveEngine() == DMEngineAerial && !gLastWindowFrames[me]) DMBehindDockSet(me, NO, @"its window opens with no place of its own kept (App Window Sizes)");' "$W/bc" \
    && order 'nothing to do (window %d' 'if (DMActiveEngine() == DMEngineAerial && !gLastWindowFrames[me]) DMBehindDockSet(' "$W/bc" \
    && order 'if (DMActiveEngine() == DMEngineAerial && !gLastWindowFrames[me]) DMBehindDockSet(' 'if ((gAerialFlavor == 5 || a3Sized) && !preLaunched) {' "$W/bc" \
    && [ "$(grep -c 'DMBehindDockSet(.*@"its window opens with no place of its own kept (App Window Sizes)")' "$1")" = 3 ] \
    && ! f1 'static void DMAppSizeForgetPlace(NSString *bundle) {' "$1" | grep -q 'BehindDock'
}
c_saved() {
  f1 'static void DMForgetSavedLastFrame(NSString *bundle) {' "$1" > "$W/fs" && [ "$(grep -c 'dispatch_async(DMWindowStateWriter(), ^{' "$W/fs")" = 2 ] && ! grep -q 'DMSaveWindowState' "$W/fs" \
    && grep -qF 'NSDictionary *state = DMForgetSavedLastFrameIn(gLastWindowState, b);' "$W/fs" && grep -qF 'gLastWindowState = state;' "$W/fs" \
    && grep -qF 'NSDictionary *state = DMForgetSavedLastFrameIn([NSDictionary dictionaryWithContentsOfFile:path], b);' "$W/fs" && [ "$(grep -c 'if (!state) return;' "$W/fs")" = 2 ] \
    && f1 'static NSDictionary *DMForgetSavedLastFrameIn(NSDictionary *state, NSString *bundle) {' "$1" > "$W/fi" && grep -qF 'if (!places[bundle]) return nil;' "$W/fi" \
    && [ "$(grep -o 'out\[@"[a-zA-Z]*"\]\|removeObjectForKey:@"[a-zA-Z]*"' "$W/fi" | sort -u | tr '\n' ' ')" = 'out[@"lastFrames"] removeObjectForKey:@"lastFrames" ' ] \
    && f1 'static void DMSaveWindowState(void) {' "$1" | grep -qF 'dispatch_async(DMWindowStateWriter(), ^{ [state writeToFile:path atomically:YES]; });' \
    && [ "$(grep -c 'dispatch_queue_create("MSBWindowStateWriter"' "$1")" = 1 ] && f1 'static dispatch_queue_t DMWindowStateWriter(void) {' "$1" | grep -qF 'dispatch_once(&once,' \
    && f1 'static void DMRestoreLastFrames(NSDictionary *state) {' "$1" > "$W/rl" && order 'gLastWindowFrames[b]) continue;' 'if ([gAppSizeForgotten containsObject:b]) continue;' "$W/rl" \
    && order 'if ([gAppSizeForgotten containsObject:b]) continue;' 'gLastWindowFrames[b] = [NSValue valueWithCGRect:f];' "$W/rl"
}
c_smsaved() {
  f1 'static void DMAppSizeWriteSMPreZoom(void) {' "$1" > "$W/sm" && grep -qF 'NSDictionary *left = [DMSMPreZoomPlaces() copy];' "$W/sm" \
    && grep -qF 'dispatch_async(DMSMStateWriteQueue(), ^{' "$W/sm" && grep -qF 'if (left.count) st[@"preZoom"] = left; else [st removeObjectForKey:@"preZoom"];' "$W/sm" \
    && [ "$(grep -o 'st\[@"[a-zA-Z]*"\]\|removeObjectForKey:@"[a-zA-Z]*"' "$W/sm" | sort -u | tr '\n' ' ')" = 'removeObjectForKey:@"preZoom" st[@"preZoom"] ' ] \
    && ! grep -q 'DMSMStateWrite()\|Minimized\|gSMTurn\|DMDockRoom\|removeObject:\|removeObjectForKey:k' "$W/sm" && [ "$(grep -c 'DMAppSizeWriteSMPreZoom()' "$1")" = 1 ]
}
c_debug() {
  awk '/^static void DMAppSizeDebugTrigger\(NSString \*cmd\);/ {d=1} END {exit !d}' "$1" \
    && awk '/^#if DEBUG$/ {i=1} /^#endif$/ {i=0} /^static void DMAppSizeDebugTrigger\(NSString \*cmd\) \{/ {exit !i}' "$1" \
    && awk '/^#if DEBUG$/ {i=1} /^#endif$/ {i=0} /DMAppSizeDebugTrigger\(cmd\);/ {n++; if (!i) bad=1} END {exit !(n == 1 && !bad)}' "$1" \
    && f1 'static void DMAppSizeDebugTrigger(NSString *cmd) {' "$1" > "$W/dt" && grep -qF 'MSBDOpensFree(app, gNewWindowsFill, DMOpensAtOwnPlace(b), NO)' "$W/dt" \
    && ! grep -q 'CFPreferencesSet\|writeToFile\|removeObject\|addObject:b\|DMAppSizeForget\|DMForgetSaved\|DMSaveWindowState\|setObject\|\] = ' "$W/dt"
}
c_rules() {
  grep -qxF "target appWindowSizes piece App Window Sizes|App Window Sizes" "$2" && grep -qxF 'sym MacStatusBarCore ^_*(DMAppSize|DMSMAppSize|DMForgetSavedLastFrame) appWindowSizes' "$2" \
    && order 'sym MacStatusBarCore ^_*(DMAppSize|DMSMAppSize|DMForgetSavedLastFrame) appWindowSizes' 'sym MacStatusBarCore ^_*DMSM[A-Z0-9] windowingEnabled' "$2" \
    && order 'file MacStatusBarCore ^AppWindowSize\.h$ appWindowSizes' 'file MacStatusBarCore ^(WindowCards|WindowMinSize|WindowSize|FitPlan|SBLaunchRule|AerialHeld)\.h$ windowingEnabled' "$2" \
    && for n in DMAppSizesSkipped DMAppSizeOf DMAppSizesLoad DMAppSizeForgetPlace DMAppSizeWriteSMPreZoom DMSMAppSizeForgetPlace DMForgetSavedLastFrame DMForgetSavedLastFrameIn; do grep -qE "^static [A-Za-z *]*\b$n\(.*\) \{" "$1" || return 1; done \
    && ! grep -qE '^static [A-Za-z *]*\bDM(AppSize|ForgetSavedLastFrame)[A-Za-z]*\(' <(grep -E '^static [A-Za-z *]*\b(DMOpeningWindowFrameFor|DMNewWindowFrameWindowAt|DMCascadeStage)\(' "$1") \
    && ! grep -q "$EM\\|$EN" <(grep appWindowSizes "$2")
}
# ---- C3 (design 5.1, 4.3): our Stage Manager engine, the iPad and the TV --------------------------------------------------------------------------
# The opening frame by the display a window joins (DMSMOpeningFrameIn: the app's own size, global per app, else that display's Open at Fill and
# Window Size through the per-display layer), the join (cascade, then free under Fit), the side question, the way back, the forget on change of
# Stage Manager's places (DMSMAppSizeForgetPlace, DMSMForgetPlacesOf shared with an app's quit). Functions that must not change are compared with
# the C2 tree (243bfb32, or its -reg twin d9ced6e8: the same tree).
for c in 243bfb32 d9ced6e8; do git -C .. show $c:statusbar/StatusBar.x > "$W/base-S" 2>/dev/null && break; done
sites+=(
"Stage Manager's opening frame: the app's own size first, else the display's Open at Fill, else its Window Size (both by the display it joins, the per-display layer); Fill the Fill layout, the rest DMSMNewWindowFrameAt|c3_opening"
"  ... the window: Default, Small and Large Window Size's (1.8.7's), iPhone the phone under our 24 pt bar with Stage Manager's minimum; DMSMNewWindowFrameIn (No Fit's place) that display's Window Size alone|c3_window"
"  ... built from StatusBar.x as it is and run on the iPad's and the TVs' desktops: 1.8.7's window with no entry on every display and input, each choice's window on each display (the TV's 393 x 876 and 320 x 432 phones), a wider minimum, no desktop|c3_behave"
"the join's fresh window asks DMSMOpeningFrameIn with its app (a second window of the app too) and the display it joins; cascaded, then marked free under Fit when it opens at Fill or the app's own size; the log names the app's size|c3_join"
"the way back with no place still joins as a new window (DMSMToggleZoom), the TV's Mac Switcher join through DMSMJoinAttributesOn|c3_wayback"
"no side question for an app with its own size on Stage Manager: DMSMFitAsksAbout asks MSBDOpensFree (the iPad's Open at Fill: Fit is the iPad's)|c3_side"
"the places before full screen of an app's windows go in one place (DMSMForgetPlacesOf: memory only, gSMPreZoom and gSMPreZoomPlaces); its app's quit writes the whole state as before (DMSMForgetApp's rest unchanged)|c3_forgetof"
"the forget on change on Stage Manager: DMSMForgetPlacesOf then the file's preZoom only, the tile for full screen (gSMFitWentFull, the arrangement only when the app's window left it); from DMAppSizeForgetPlace with every engine; nothing else (minimized and free marks, turn notes, Fit's open arrangement, stages)|c3_smforget"
"  ... and the behind-the-Dock mark of each window whose place before full screen it forgets (review R1: its keys read before DMSMForgetPlacesOf); DMSMForgetPlacesOf, which an app's quit shares, takes none (the quit hands its marks to the turn's forget with its windows' turn records, 1.8.8 H5: test-smturnclosed)|c3_behind"
"  ... built from StatusBar.x as it is and run: a full-screen window's mark goes with its place (in memory, or kept across a respring), a window still open behind the Dock keeps its, another app's stay, windows told apart by app too|c3_behindrun"
"what must not change: No Fit's place, a window's own attributes, the closed windows' turn notes, Fit's tick (but for F3's two blocks), the zoom, the side question's launches (the C2 tree's text)|c3_unchanged"
"the debug trigger: Stage Manager's frame by each display (DMSMOpeningFrameIn with its identity), Fit's answer by Stage Manager's own size; read only|c3_debug"
"the crash piece's sym rule takes Stage Manager's forget (DMSMAppSize*) and leaves the opening frame, the window and DMSMForgetPlacesOf to Stage Manager's window rule|c3_rules"
"  ... the piece's code DMLoadPrefs runs (the read, both engines' forgets, the saved states' writers) each its own range in the release map: declared noinline before it is defined|c3_noinline"
)
c3_opening() {
  f1 'static CGRect DMSMOpeningFrameIn(NSString *bundle, CGRect u, CGSize scr, id identity, BOOL *atFill) {' "$1" > "$W/so3" \
    && grep -qF 'int app = DMAppSizeOf(bundle), s = MSBDOpeningSize(app, DMWindowSizeChoiceFor(identity), DMNewWindowsFillFor(identity));' "$W/so3" \
    && grep -qF 'if (atFill) *atFill = s == kMSBDOpenFill;' "$W/so3" && grep -qxF '    if (s == kMSBDOpenFill) return DMSMLayoutFrameIn(@"fill", u, scr);' "$W/so3" \
    && grep -qxF '    return DMSMNewWindowFrameAt(s, u, scr);' "$W/so3" && [ "$(grep -c 'return' "$W/so3")" = 2 ] && ! grep -qE '\b(gWindowSizeChoice|gNewWindowsFill)\b' "$W/so3" \
    && grep -qF 'static CGRect DMSMOpeningFrameIn(NSString *bundle, CGRect u, CGSize scr, id identity, BOOL *atFill);' "$1" && [ "$(grep -c 'DMSMOpeningFrameIn(' "$1")" = 4 ]
}
c3_window() {
  f1 'static CGRect DMSMNewWindowFrameAt(int choice, CGRect u, CGSize scr) {' "$1" > "$W/sw3" && grep -qF 'if (CGRectIsNull(u) || CGRectIsEmpty(u) || scr.width < 1.0 || scr.height < 1.0) return CGRectNull;' "$W/sw3" \
    && order 'CGSize least = CGSizeMake(MAX(DMSMMinWindowWidth(scr), kMSBDWindowMinWidth), kMSBDWindowMinAppHeight + kSMBarH);' 'if (choice == kMSBDOpenIPhone) { DM_FEATURE_MARK("app-window-size-iphone-sm"); return MSBDWindowPhoneIn(u, kSMBarH, least); }' "$W/sw3" \
    && grep -qxF '    return MSBDWindowSizeFrameIn(choice, u, scr, DMCenterTopFor(scr), least);' "$W/sw3" && ! grep -q 'DMAppSizeOf\|gWindowSizeChoice\|identity' "$W/sw3" \
    && grep -qF 'static CGRect DMSMNewWindowFrameIn(CGRect u, CGSize scr, id identity) { return DMSMNewWindowFrameAt(DMWindowSizeChoiceFor(identity), u, scr); }' "$1"
}
c3_behave() {   # DMSMNewWindowFrameAt, DMSMNewWindowFrameIn and DMSMOpeningFrameIn as written in <StatusBar.x>, with stand-ins for what they read
  { f1 'static CGRect DMSMNewWindowFrameAt(int choice, CGRect u, CGSize scr) {' "$1"; grep -F 'static CGRect DMSMNewWindowFrameIn(CGRect u, CGSize scr, id identity) {' "$1"
    f1 'static CGRect DMSMOpeningFrameIn(NSString *bundle, CGRect u, CGSize scr, id identity, BOOL *atFill) {' "$1"; } > "$W/smof.h"
  local h; h=$(shasum "$W/smof.h" | cut -c1-16); local d="$W/smof-$h"
  if [ ! -f "$d.rc" ]; then
    mkdir -p "$d"; cp "$W/smof.h" "$d/smof.h"
    if clang -fobjc-arc -Wall -Werror -Wno-unused-function -I ../common -I ../statusbar -I "$d" -framework Foundation -framework CoreGraphics -o "$d/t" "$W/smof-main.m" > "$d/build" 2>&1; then
      "$d/t" > "$d/out" 2>&1; echo $? > "$d.rc"
    else echo 3 > "$d.rc"; fi
  fi
  return "$(cat "$d.rc")"
}
cat > "$W/smof-main.m" <<'EOF'
#import <Foundation/Foundation.h>
#include "AppWindowSize.h"
#include "WindowMinSize.h"
#define DM_FEATURE_MARK(name) do { } while (0)
static const CGFloat kSMBarH = 24.0;
static NSDictionary<NSString *, NSNumber *> *gTable;
static int gIPadWS = 0; static BOOL gIPadFill = NO;
static NSMutableDictionary *gWS, *gFill;
static CGFloat gSMMin = 320.0;
static int DMAppSizeOf(NSString *b) { NSNumber *n = [b isKindOfClass:[NSString class]] ? gTable[b] : nil; return n ? n.intValue : MSBDAppSizeNone; }
static int DMWindowSizeChoiceFor(id identity) { return identity && gWS[identity] ? [gWS[identity] intValue] : gIPadWS; }   // (the per-display layer: the iPad's until set)
static BOOL DMNewWindowsFillFor(id identity) { return identity && gFill[identity] ? [gFill[identity] boolValue] : gIPadFill; }
static CGFloat DMSMMinWindowWidth(CGSize s) { (void)s; return gSMMin; }
static CGFloat DMCenterTopFor(CGSize s) { (void)s; return 36.0; }
static CGRect DMSMLayoutFrameIn(NSString *name, CGRect u, CGSize scr) { (void)scr; return [name isEqualToString:@"fill"] ? u : CGRectNull; }   // (Fill: the desktop)
#include "smof.h"
static int fails = 0, n = 0;
static void Expect(BOOL ok, NSString *what) { n++; if (!ok) { fails++; printf("FAIL: %s\n", what.UTF8String); } }
static BOOL Same(CGRect a, CGRect b) { return (CGRectIsNull(a) && CGRectIsNull(b)) || CGRectEqualToRect(a, b); }
static CGSize Least(void) { return CGSizeMake(MAX(gSMMin, kMSBDWindowMinWidth), kMSBDWindowMinAppHeight + kSMBarH); }
static CGRect Want(int app, int ws, BOOL fill, CGRect u, CGSize scr, BOOL *atFill) {   // design 1.1 and 2, from the header alone
    int s = MSBDOpeningSize(app, ws, fill);
    *atFill = s == kMSBDOpenFill;
    if (s == kMSBDOpenFill) return u;
    if (s == kMSBDOpenIPhone) return MSBDWindowPhoneIn(u, kSMBarH, Least());
    return MSBDWindowSizeFrameIn(s, u, scr, 36.0, Least());
}
int main(void) { @autoreleasepool {
    CGSize ipad = {1366, 1024}, tv = {2560, 1440}, tv2 = {960, 540};
    CGRect uI = CGRectMake(0, 24, 1366, 914), uT = CGRectMake(0, 24, 2560, 1126), uT2 = CGRectMake(0, 24, 960, 450.5);
    NSString *TV = @"tv", *TV2 = @"tv2";
    gWS = [NSMutableDictionary dictionary]; gFill = [NSMutableDictionary dictionary];
    int apps[6] = { MSBDAppSizeNone, MSBDAppSizeSmall, MSBDAppSizeMedium, MSBDAppSizeLarge, MSBDAppSizeFill, MSBDAppSizeIPhone };
    for (int a = 0; a < 6; a++) for (int wi = 0; wi < 3; wi++) for (int fi = 0; fi < 2; fi++) for (int wt = 0; wt < 3; wt++) for (int ft = 0; ft < 2; ft++) {
        gTable = apps[a] == MSBDAppSizeNone ? @{} : @{ @"com.apple.mobilenotes": @(apps[a]) };
        gIPadWS = wi; gIPadFill = fi; gWS[TV] = @(wt); gFill[TV] = @(ft);
        for (int d = 0; d < 2; d++) {
            id ident = d ? TV : nil; CGRect u = d ? uT : uI; CGSize scr = d ? tv : ipad;
            BOOL got = NO, want = NO;
            CGRect f = DMSMOpeningFrameIn(@"com.apple.mobilenotes", u, scr, ident, &got);
            CGRect w = Want(apps[a], d ? wt : wi, d ? ft : fi, u, scr, &want);
            Expect(Same(f, w) && got == want, [NSString stringWithFormat:@"app %d on %@ (Window Size %d, Open at Fill %d; the other display's %d %d): %@ at Fill %d, want %@ at Fill %d",
                   apps[a], d ? @"the TV" : @"the iPad", d ? wt : wi, d ? ft : fi, d ? wi : wt, d ? fi : ft, NSStringFromRect(f), got, NSStringFromRect(w), want]);
            CGRect other = DMSMOpeningFrameIn(@"com.apple.Preferences", u, scr, ident, &got);   // (an app with no entry: 1.8.7's window, that display's own)
            BOOL fill = d ? ft : fi;
            CGRect old = fill ? u : MSBDWindowSizeFrameIn(d ? wt : wi, u, scr, 36.0, Least());
            Expect(Same(other, old) && got == fill, [NSString stringWithFormat:@"no entry on %@: %@, want 1.8.7's %@", d ? @"the TV" : @"the iPad", NSStringFromRect(other), NSStringFromRect(old)]);
            Expect(Same(DMSMNewWindowFrameIn(u, scr, ident), MSBDWindowSizeFrameIn(d ? wt : wi, u, scr, 36.0, Least())), @"DMSMNewWindowFrameIn: that display's Window Size alone");
            Expect(Same(DMSMOpeningFrameIn(@"com.apple.mobilenotes", u, scr, ident, NULL), f), @"atFill may be NULL");
        }
    }
    [gWS removeAllObjects]; [gFill removeAllObjects]; gIPadWS = MSBDWindowSizeLarge; gIPadFill = YES;
    gTable = @{ @"com.apple.mobilenotes": @(MSBDAppSizeIPhone) };
    BOOL af = YES;
    CGRect p = DMSMOpeningFrameIn(@"com.apple.mobilenotes", uT, tv, TV, &af);
    Expect(p.size.width == 393 && p.size.height == 876 && !af, [NSString stringWithFormat:@"iPhone on the A12Z's TV: 393 x 876, got %@", NSStringFromRect(p)]);
    p = DMSMOpeningFrameIn(@"com.apple.mobilenotes", uT2, tv2, TV2, &af);
    Expect(p.size.width == 320 && p.size.height == 432 && CGRectContainsRect(uT2, p), [NSString stringWithFormat:@"iPhone on the iPad 2's TV: 320 x 432 inside it, got %@", NSStringFromRect(p)]);
    gSMMin = 400.0;
    p = DMSMOpeningFrameIn(@"com.apple.mobilenotes", uI, ipad, nil, &af);
    Expect(p.size.width == 400, [NSString stringWithFormat:@"iPhone never under Stage Manager's minimum (400 here): got %@", NSStringFromRect(p)]);
    gSMMin = 320.0;
    gTable = @{ @"com.apple.mobilenotes": @(MSBDAppSizeMedium) };
    p = DMSMOpeningFrameIn(@"com.apple.mobilenotes", uI, ipad, nil, &af);
    Expect(Same(p, MSBDWindowSizeFrameIn(MSBDWindowSizeDefault, uI, ipad, 36.0, Least())) && !af, @"Medium: Window Size's Default window with Window Size Large and Open at Fill on");
    for (int a = 0; a < 6; a++) {
        gTable = apps[a] == MSBDAppSizeNone ? @{} : @{ @"com.apple.mobilenotes": @(apps[a]) };
        for (int fi = 0; fi < 2; fi++) { gIPadFill = fi;
            Expect(CGRectIsNull(DMSMOpeningFrameIn(@"com.apple.mobilenotes", CGRectNull, ipad, nil, &af)), @"no desktop: CGRectNull");
            Expect(CGRectIsNull(DMSMOpeningFrameIn(@"com.apple.mobilenotes", CGRectMake(0, 24, 0, 0), ipad, nil, &af)) || af, @"an empty desktop: CGRectNull (Fill: the empty desktop the caller refuses)");
        }
    }
    printf("smof: %d cases, %d failed\n", n, fails);
    return fails ? 1 : 0;
} }
EOF
c3_join() {
  f1 'static id DMSMJoinAttributesOn(NSString *key, id frontAttrs, BOOL windowed, long newest, id stage, id identity) {' "$1" > "$W/j3" \
    && grep -qF 'NSString *bundle = DMSMKeyBundle(key) ?: key;' "$W/j3" && [ "$(grep -c 'DMAppSizeOf(' "$W/j3")" = 1 ] && grep -qxF '                int app = DMAppSizeOf(bundle);' "$W/j3" \
    && grep -qF 'CGRect opening = DMSMOpeningFrameIn(bundle, u, scr, onDisplay, &atFill);' "$W/j3" && [ "$(grep -c 'DMSMOpeningFrameIn(' "$W/j3")" = 1 ] \
    && grep -qF 'BOOL opensFree = MSBDOpensFree(app, DMNewWindowsFillFor(onDisplay), false, false);' "$W/j3" \
    && order 'CGRect placed = atFill ? opening : MSBDWindowCascadeIn(opening, others, n, u, NO, &how);' 'if (opensFree && DMFitEnabled()) {' "$W/j3" \
    && order 'if (opensFree && DMFitEnabled()) {' 'CGRect card = MSBDWindowCardOf(placed, kSMBarH);' "$W/j3" && [ "$(grep -c 'gSMFreeWindows addObject:key' "$W/j3")" = 1 ] \
    && grep -qF 'if (opensFree && DMFitEnabled()) { if (!gSMFreeWindows) gSMFreeWindows = [NSMutableSet set]; [gSMFreeWindows addObject:key]; }' "$W/j3" \
    && ! grep -v '^ *//' "$W/j3" | grep -q 'DMSMNewWindowFrameIn\|DMSMNewWindowFrameAt\|MSBDNewWindowAtFill' && grep -qF 'MSBDAppSizeValid(app) ? [NSString stringWithFormat:@"App Window Sizes %s", MSBDAppSizeName(app)]' "$W/j3" \
    && grep -qF 'opensFree && DMFitEnabled() ? @"; Fit to Window leaves it out" : @""' "$W/j3"
}
c3_wayback() {
  f1 'static BOOL DMSMToggleZoom(NSString *key) {' "$1" | grep -qF 'back = DMSMJoinAttributes(wk, attrs, YES, t - 1, stage);' \
    && grep -qF 'return DMSMJoinAttributesOn(key, frontAttrs, windowed, newest, stage, DMSMStageDisplayIdentity(stage));' "$1" \
    && grep -qF 'id attrs = DMSMJoinAttributesOn(key, nil, windowed, 0, nil, tv ? identity : nil);' "$1"
}
c3_side() {
  f1 'static BOOL DMSMFitAsksAbout(NSString *bundle, NSArray<NSString *> *stageKeys, NSString **leftOut, NSString **rightOut) {' "$1" \
    | grep -qxF '    if (!MSBDFitTakesOpening(YES, MSBDOpensFree(DMAppSizeOf(DMSMKeyBundle(bundle)), gNewWindowsFill, DMSMOpensAtOwnSize(bundle), NO))) return NO;'
}
c3_forgetof() {
  f1 'static BOOL DMSMForgetPlacesOf(NSString *bundle) {' "$1" > "$W/fo3" \
    && grep -qxF '    for (NSString *k in [gSMPreZoom allKeys]) if ([DMSMKeyBundle(k) isEqualToString:bundle]) [gSMPreZoom removeObjectForKey:k];' "$W/fo3" \
    && grep -qxF '    for (NSString *k in [DMSMPreZoomPlaces() allKeys]) if ([DMSMKeyBundle(k) isEqualToString:bundle]) { [gSMPreZoomPlaces removeObjectForKey:k]; placesGone = YES; }' "$W/fo3" \
    && grep -qxF '    return placesGone;' "$W/fo3" && ! grep -q 'DMSMStateWrite\|dispatch_\|writeToFile\|Minimized\|gSMTurn\|DMSMTurn\|gSMFit\|gSMFree' "$W/fo3" \
    && f1 'static void DMSMForgetApp(NSString *bundle) {' "$1" > "$W/fa3" && awk 'NR == 4' "$W/fa3" | grep -qxF '    if (DMSMForgetPlacesOf(bundle)) DMSMStateWrite();' \
    && ! grep -q 'gSMPreZoom' "$W/fa3" && [ -s "$W/base-S" ] \
    && diff <(sed -n '/DMSMSetMinimized(bundle, NO);/,$p' "$W/fa3" | h5drop) <(f1 'static void DMSMForgetApp(NSString *bundle) {' "$W/base-S" | sed -n '/DMSMSetMinimized(bundle, NO);/,$p') > /dev/null \
    && [ "$(grep -c 'DMSMForgetPlacesOf(bundle)' "$1")" = 2 ]
}
c3_smforget() {
  f1 'static void DMSMAppSizeForgetPlace(NSString *bundle) {' "$1" > "$W/sf3" && grep -qxF '    if (DMSMForgetPlacesOf(bundle)) DMAppSizeWriteSMPreZoom();' "$W/sf3" \
    && grep -qF 'for (NSString *k in [gSMFitWentFull allObjects]) if ([DMSMKeyBundle(k) isEqualToString:bundle]) {' "$W/sf3" && grep -qxF '        [gSMFitWentFull removeObject:k]; full++;' "$W/sf3" \
    && grep -qxF '        if (gSMFitSlotsBeforeFull[k]) leftTile = YES;' "$W/sf3" && grep -qxF '    if (leftTile) gSMFitSlotsBeforeFull = nil;' "$W/sf3" && [ "$(grep -c 'gSMFitSlotsBeforeFull = ' "$W/sf3")" = 1 ] \
    && ! grep -qE 'DMSMStateWrite|Minimized|gSMTurn|DMSMTurn|gSMFreeWindows|gFreeWindows|gSMFitSlots([^B]|$)|gSMFitLoose|gSMFitByDesk|Stage\(|DMSMRequest|DMSMApply|removeAllObjects|\[gSMPreZoom(Places)? removeObject|\[places removeObject' "$W/sf3" \
    && [ "$(grep -c 'DMSMAppSizeForgetPlace(bundle)' "$1")" = 1 ] && f1 'static void DMAppSizeForgetPlace(NSString *bundle) {' "$1" | grep -qxF '    DMSMAppSizeForgetPlace(bundle);'
}
c3_behind() {   # (review R1: gSMBehindDock is by window; a full-screen window's mark is its place's before full screen, the way back joins fresh without it)
  f1 'static void DMSMAppSizeForgetPlace(NSString *bundle) {' "$1" > "$W/bd3" \
    && grep -qxF '    NSMutableSet<NSString *> *went = [NSMutableSet set];   // (the windows whose place before full screen goes)' "$W/bd3" \
    && grep -qxF '    for (NSString *k in gSMPreZoom) if ([DMSMKeyBundle(k) isEqualToString:bundle]) [went addObject:k];' "$W/bd3" \
    && grep -qxF '    for (NSString *k in DMSMPreZoomPlaces()) if ([DMSMKeyBundle(k) isEqualToString:bundle]) [went addObject:k];' "$W/bd3" \
    && grep -qxF '    for (NSString *k in went) if (DMSMKeySetRemove(gSMBehindDock, k)) marks++;' "$W/bd3" \
    && [ "$(awk 'index($0, "[went addObject:k];") {a=NR} index($0, "    if (DMSMForgetPlacesOf(bundle)) DMAppSizeWriteSMPreZoom();") {f=NR} index($0, "DMSMKeySetRemove(gSMBehindDock, k)") {r=NR} END {print (a && f && r && a < f && f < r) ? "ok" : "no"}' "$W/bd3")" = ok ] \
    && [ "$(grep -c 'gSMBehindDock' "$W/bd3")" = 1 ] && [ "$(grep -c 'DMSMKeySetRemove(gSMBehindDock, ' "$1")" = 4 ] \
    && ! f1 'static BOOL DMSMForgetPlacesOf(NSString *bundle) {' "$1" | grep -q 'BehindDock' \
    && { ! f1 'static void DMSMForgetApp(NSString *bundle) {' "$1" | grep -q 'BehindDock' \
         || [ "$(f1 'static void DMSMForgetApp(NSString *bundle) {' "$1" | grep 'BehindDock' | h5drop | wc -l | tr -d ' ')" = 0 ]; }
}
c3_behindrun() {   # DMSMForgetPlacesOf and DMSMAppSizeForgetPlace as written in <StatusBar.x>, with stand-ins for what they read
  { f1 'static BOOL DMSMForgetPlacesOf(NSString *bundle) {' "$1"; f1 'static void DMSMAppSizeForgetPlace(NSString *bundle) {' "$1"; } > "$W/smbd.h"
  local h; h=$(shasum "$W/smbd.h" | cut -c1-16); local d="$W/smbd-$h"
  if [ ! -f "$d.rc" ]; then
    mkdir -p "$d"; cp "$W/smbd.h" "$d/smbd.h"
    if clang -fobjc-arc -Wall -Werror -Wno-unused-function -I ../statusbar -I "$d" -framework Foundation -o "$d/t" "$W/smbd-main.m" > "$d/build" 2>&1; then
      "$d/t" > "$d/out" 2>&1; echo $? > "$d.rc"
    else echo 3 > "$d.rc"; fi
  fi
  return "$(cat "$d.rc")"
}
cat > "$W/smbd-main.m" <<'EOF'
#import <Foundation/Foundation.h>
#include "SMWindowKey.h"
static NSMutableDictionary<NSString *, id> *gSMPreZoom;
static NSMutableDictionary<NSString *, NSDictionary *> *gSMPreZoomPlaces;
static NSMutableDictionary<NSString *, NSDictionary *> *DMSMPreZoomPlaces(void) { if (!gSMPreZoomPlaces) gSMPreZoomPlaces = [NSMutableDictionary dictionary]; return gSMPreZoomPlaces; }
static NSMutableSet<NSString *> *gSMBehindDock, *gSMFitWentFull;
static NSDictionary<NSString *, NSString *> *gSMFitSlotsBeforeFull;
static int gWrites = 0;
static void DMAppSizeWriteSMPreZoom(void) { gWrites++; }
static NSMutableArray<NSString *> *gLog;
static void DMLog(NSString *s) { [gLog addObject:s]; }
#include "smbd.h"
static int fails = 0, n = 0;
static void Expect(BOOL ok, NSString *what) { n++; if (!ok) { fails++; printf("FAIL: %s\n", what.UTF8String); } }
static NSString *const kN = @"com.apple.mobilenotes", *const kC = @"com.apple.mobiletimer";
static NSString *const kN1 = @"com.apple.mobilenotes|sceneID:com.apple.mobilenotes-default", *const kN2 = @"com.apple.mobilenotes|sceneID:com.apple.mobilenotes-3E2F1A90";
static NSString *const kC1 = @"com.apple.mobiletimer|sceneID:com.apple.mobiletimer-default";
static void Reset(void) {
    gSMPreZoom = [NSMutableDictionary dictionary]; gSMPreZoomPlaces = [NSMutableDictionary dictionary]; gSMBehindDock = [NSMutableSet set];
    gSMFitWentFull = [NSMutableSet set]; gSMFitSlotsBeforeFull = nil; gWrites = 0; gLog = [NSMutableArray array];
}
static NSDictionary *Kept(void) { return @{@"f": @"{{376, 601}, {615, 423}}", @"s": @"{1366, 1024}"}; }
int main(void) { @autoreleasepool {
    // 1. Notes' window n1 full screen by our green, put behind the Dock before (its place before full screen in memory); its other window n2 open
    //    behind the Dock; Clock full screen, behind the Dock before. Notes' size changes.
    Reset(); gSMPreZoom[kN1] = @"attrs"; gSMPreZoom[kC1] = @"attrs"; [gSMBehindDock addObjectsFromArray:@[kN1, kN2, kC1]];
    DMSMAppSizeForgetPlace(kN);
    Expect(!gSMPreZoom[kN1] && gSMPreZoom[kC1], @"the places before full screen: Notes' gone, Clock's kept");
    Expect(![gSMBehindDock containsObject:kN1], @"the full-screen window's mark goes with its place (its way back joins as a new window, above the Dock)");
    Expect([gSMBehindDock containsObject:kN2], @"a window of the app still open behind the Dock keeps its mark");
    Expect([gSMBehindDock containsObject:kC1], @"another app's mark stays");
    Expect(gLog.count == 1 && [gLog[0] hasSuffix:@"behind-the-Dock marks with them 1"], [NSString stringWithFormat:@"the log names the marks taken: %@", gLog.lastObject]);
    // 2. the place kept across a respring only (the saved state's preZoom), the mark set since
    Reset(); gSMPreZoomPlaces[kN1] = Kept(); [gSMBehindDock addObject:kN1];
    DMSMAppSizeForgetPlace(kN);
    Expect(!gSMPreZoomPlaces[kN1] && gWrites == 1 && ![gSMBehindDock containsObject:kN1], @"a place kept across a respring: gone, written once, its window's mark with it");
    // 3. windows told apart by app (app keys, SMWindowKey.h)
    Reset(); gSMPreZoom[kN] = @"attrs"; [gSMBehindDock addObject:kN];
    DMSMAppSizeForgetPlace(kN);
    Expect(!gSMBehindDock.count, @"windows by app: the app's mark goes with the app's place before full screen");
    // 4. an app-wide mark (an older version's) and the full-screen window's own place: the app-wide entry no longer holds for that window (DMSMKeySetRemove)
    Reset(); gSMPreZoom[kN1] = @"attrs"; [gSMBehindDock addObjectsFromArray:@[kN, kN2]];
    DMSMAppSizeForgetPlace(kN);
    Expect(![gSMBehindDock containsObject:kN] && [gSMBehindDock containsObject:kN2], @"an app-wide mark goes with the window's place, another window's own mark stays");
    // 5. no place before full screen: a window open behind the Dock keeps its mark, nothing logged
    Reset(); [gSMBehindDock addObject:kN2];
    DMSMAppSizeForgetPlace(kN);
    Expect([gSMBehindDock containsObject:kN2] && !gLog.count && !gWrites, @"no place before full screen: the open window's mark kept, nothing logged or written");
    // 6. another app's forget leaves Notes as it is
    Reset(); gSMPreZoom[kN1] = @"attrs"; [gSMBehindDock addObject:kN1];
    DMSMAppSizeForgetPlace(kC);
    Expect(gSMPreZoom[kN1] && [gSMBehindDock containsObject:kN1], @"Clock's forget: Notes' place and mark kept");
    // 7. an app's quit (DMSMForgetPlacesOf, shared with it) leaves the marks as in 1.8.7.7
    Reset(); gSMPreZoom[kN1] = @"attrs"; [gSMBehindDock addObject:kN1];
    (void)DMSMForgetPlacesOf(kN);
    Expect(!gSMPreZoom[kN1] && [gSMBehindDock containsObject:kN1], @"DMSMForgetPlacesOf takes the places only (an app's quit unchanged)");
    printf("smbd: %d cases, %d failed\n", n, fails);
    return fails ? 1 : 0;
} }
EOF
f3drop() {   # (a function without F3's blocks: DMSMFitTick's two loops over the windows back from full screen that Fit does not tile, F3's own checks below)
  awk 'skip { if ($0 == ind "}") skip = 0; next } /^ +for \(NSString \*k in DMSMFitBackUntiled\(/ { match($0, /^ +/); ind = substr($0, 1, RLENGTH); skip = 1; next } {print}'
}
# (a function without G1's lines, 1.8.8 KT's decision b: DMSMFitTick's windows full screen out of sight -- the rule's call, the minimized rule's
#  condition and log, the "closed meanwhile" line -- each put back as it was; test-smfitfullaway runs them. A text not there is left as it is.)
cat > "$W/g1drop.py" <<'EOF'
import sys
s = sys.stdin.read()
for new, old in [
    ("    // So too while the windows missing are full screen out of sight (DMSMFitFullAway, 1.8.8 G1): with three tiles, the two on screen were tiled\n"
     "    // again as a pair, and the window back from full screen was asked about as a third window (KT's decision b, 19 Nov: as Aerial keeps them).\n"
     "    NSSet<NSString *> *fullAway = DMSMFitFullAway(onScreen);\n", ""),
    ("if (!there || !(DMSMIsMinimized(k) || DMSMKeySetHas(fullAway, k))) { onlyMinimizedOut = NO; break; }", "if (!there || !DMSMIsMinimized(k)) { onlyMinimizedOut = NO; break; }"),
    ("            NSUInteger full = 0;   // (of them, full screen out of sight and not minimized: G1)\n"
     "            for (NSString *k in gSMFitSlots) if (!plan[k] && !DMSMIsMinimized(k) && DMSMKeySetHas(fullAway, k)) full++;\n"
     "            if (full) DM_FEATURE_MARK(\"sm-fit-full-away-keep-tiles\");\n"
     "            if (!full) DMLog(", "            DMLog("),
    ("(unsigned long)bundles.count]);\n"
     "            else DMLog([NSString stringWithFormat:@\"[sm] Fit to Window: %lu window(s) full screen out of sight (%lu minimized besides) keep their tiles for their way back -- the %lu on screen keep theirs\",\n"
     "                        (unsigned long)full, (unsigned long)(gSMFitSlots.count - bundles.count - full), (unsigned long)bundles.count]);\n", "(unsigned long)bundles.count]);\n"),
    ("    // (a window that went full screen and is not on screen: closed, or a window again somewhere else -- but one that left a tile and is full screen\n"
     "    //  out of sight keeps its way back, as with Aerial: DMSMFitFullAway, 1.8.8 G1. It was dropped as soon as it was not on screen -- a window opened\n"
     "    //  on the desktop meanwhile, say -- and back on the desktop it was a new window to Fit, asked about as a third window)\n", ""),
    ("if (![onScreen containsObject:b] && !((gSMFitSlots[b] || gSMFitSlotsBeforeFull[b]) && [fullAway containsObject:b])) [gSMFitWentFull removeObject:b];", "if (![onScreen containsObject:b]) [gSMFitWentFull removeObject:b];"),
]:
    if s.count(new) == 1: s = s.replace(new, old)
sys.stdout.write(s)
EOF
g1drop() { python3 -I "$W/g1drop.py"; }
# (a function without H3's lines, 1.8.8: DMSMFitTick's two calls of DMSMFitBackInTile, in the minimized rule and the one-window rule, each one line;
#  test-smfitfullaway runs them and checks where they are)
h3drop() { /usr/bin/grep -vE '^ +DMSMFitBackInTile\(bundles\);   // \((one of them|the one) back from full screen: in its tile again, .* -- 1\.8\.8 H3\)$'; }
# (a function without H2's lines, 1.8.8 KT's decision A: DMSMFitTick plans with the arrangement's minimized windows -- DMSMFitKeptAway in the
#  windows that take part, the windows on screen laid out, the plan made for both -- each line put back as it was; test-fitminimized runs them)
cat > "$W/h2drop.py" <<'EOF'
import sys
s = sys.stdin.read()
for new, old in [
    ("    NSArray<NSString *> *keptAway = @[];   // (1.8.8 H2: the arrangement's minimized windows, in the plan with their tiles -- DMSMFitKeptAway)\n",
     ''),
    ("        keptAway = DMSMFitKeptAway(bundles, slotsForPart ?: gSMFitSlots);   // (1.8.8 H2: they count with their tiles, as Aerial's gFitGroup keeps them)\n        NSArray<NSString *> *part = DMSMFitTakingPart(keptAway.count ? [bundles arrayByAddingObjectsFromArray:keptAway] : bundles, slotsForPart ?: gSMFitSlots, gSMFitLoose, &looseNow);\n",
     '        NSArray<NSString *> *part = DMSMFitTakingPart(bundles, slotsForPart ?: gSMFitSlots, gSMFitLoose, &looseNow);\n'),
    ('        if (part.count - keptAway.count < bundles.count) DMLog([NSString stringWithFormat:@"[sm] Fit to Window: %lu regular window(s) over the tiles stay where they are", (unsigned long)(bundles.count + keptAway.count - part.count)]);\n',
     '        if (part.count < bundles.count) DMLog([NSString stringWithFormat:@"[sm] Fit to Window: %lu regular window(s) over the tiles stay where they are", (unsigned long)(bundles.count - part.count)]);\n'),
    ('        [bundles removeObjectsInArray:keptAway];   // (... on screen: the minimized ones are in the plan below, not laid out -- 1.8.8 H2)\n',
     ''),
    ('    NSArray<NSString *> *planned = keptAway.count ? [bundles arrayByAddingObjectsFromArray:keptAway] : bundles;   // (with the minimized windows: their tiles kept -- 1.8.8 H2)\n',
     ''),
    ('        if (old.count == planned.count && [[NSSet setWithArray:old.allKeys] isEqualToSet:[NSSet setWithArray:planned]]) gSMFitSlots = [old mutableCopy];\n        DMLog([NSString stringWithFormat:@"[sm] Fit to Window: %@ back from full screen -- %@", returning, gSMFitSlots.count == planned.count ? @"its tile again" : @"the default arrangement"]);\n',
     '        if (old.count == bundles.count && [[NSSet setWithArray:old.allKeys] isEqualToSet:[NSSet setWithArray:bundles]]) gSMFitSlots = [old mutableCopy];\n        DMLog([NSString stringWithFormat:@"[sm] Fit to Window: %@ back from full screen -- %@", returning, gSMFitSlots.count == bundles.count ? @"its tile again" : @"the default arrangement"]);\n'),
    ('    NSDictionary *slotsNow = DMSMFitSlotsFor(gSMFitSlots, gSMFitByDesk, planned);\n',
     '    NSDictionary *slotsNow = DMSMFitSlotsFor(gSMFitSlots, gSMFitByDesk, bundles);\n'),
    ('    NSDictionary *plan = DMSMFitPlanDecide(gSMFitSlots, planned, DMDefaultSlotNames(MIN((NSUInteger)4, planned.count)), &how);\n',
     '    NSDictionary *plan = DMSMFitPlanDecide(gSMFitSlots, bundles, DMDefaultSlotNames(MIN((NSUInteger)4, bundles.count)), &how);\n'),
    ('        NSString *key = DMSMFitDeskKey(planned);\n',
     '        NSString *key = DMSMFitDeskKey(bundles);\n'),
    ('    NSUInteger keep = 0;   // (laid out: the windows on screen; the minimized ones keep their tiles for their return -- 1.8.8 H2)\n    if (keptAway.count) { NSMutableDictionary *laid = [plan mutableCopy]; [laid removeObjectsForKeys:keptAway]; keep = plan.count - laid.count; plan = laid; }\n    DMLog([NSString stringWithFormat:@"[sm] Fit to Window: %lu windows tiled%@%@", (unsigned long)plan.count, how == DMSMFitKept ? @" (the chosen arrangement)" : @"", keep ? [NSString stringWithFormat:@" -- %lu minimized window(s) keep their tiles", (unsigned long)keep] : @""]);\n',
     '    DMLog([NSString stringWithFormat:@"[sm] Fit to Window: %lu windows tiled%@", (unsigned long)plan.count, how == DMSMFitKept ? @" (the chosen arrangement)" : @""]);\n'),
]:
    if s.count(new) == 1: s = s.replace(new, old)
sys.stdout.write(s)
EOF
h2drop() { python3 -I "$W/h2drop.py"; }
# (a function without H5's lines, 1.8.8: the turn's look for closed windows reads the stages through DMSMWindowKeysAfterStart and looks at the
#  behind-the-Dock marks too, and an app's quit hands its marks to DMSMTurnForget -- each line put back as it was; test-smturnclosed runs them)
cat > "$W/h5drop.py" <<'EOF'
import sys
s = sys.stdin.read()
for new, old in [
    ("    if (!gSMTurnStartSettled || (!DMSMTurnLayouts().count && !gSMTurnFrames.count && !gSMBehindDock.count)) return;\n",
     "    if (!gSMTurnStartSettled || (!DMSMTurnLayouts().count && !gSMTurnFrames.count)) return;\n"),
    ("    NSSet<NSString *> *present = DMSMWindowKeysAfterStart(stages);\n", "    NSSet<NSString *> *present = DMSMWindowKeysIn(stages);\n"),
    ("    if (gSMBehindDock.count) [keys unionSet:gSMBehindDock];   // (1.8.8 H5: the marks too, DMSMTurnForget)\n", ""),
    ("    for (NSString *k in gSMBehindDock) if ([DMSMKeyBundle(k) isEqualToString:bundle]) [mine addObject:k];   // (and their behind-the-Dock marks, as the other engines' at the app's exit: 1.8.8 H5)\n", ""),
]:
    if s.count(new) == 1: s = s.replace(new, old)
sys.stdout.write(s)
EOF
h5drop() { python3 -I "$W/h5drop.py"; }
c3_unchanged() {
  [ -s "$W/base-S" ] || return 1
  for h in 'static id DMSMNoFitPlace(id stage) {' 'static id DMSMOwnAttrsFor(NSString *key, BOOL windowed, id *ownItemOut) {' 'static void DMSMTurnForgetClosed(void) {' 'static void DMSMFitTick(BOOL force) {' \
           'static BOOL DMSMToggleZoom(NSString *key) {' 'static BOOL DMSMAttrsOwnSize(id attrs) {' 'static void DMLaunchIntoTile(NSString *bundleID, CGRect frame) {' \
           'static void DMPromptBeforeLaunch(NSString *newBundle, NSString *leftBundle, NSString *rightBundle, void (^launch)(CGRect frame)) {'; do
    f1 "$h" "$1" | h2drop | f3drop | g1drop | h3drop | h5drop > "$W/u1"; f1 "$h" "$W/base-S" > "$W/u0"; [ -s "$W/u0" ] && cmp -s "$W/u0" "$W/u1" || return 1
  done
}
c3_debug() {
  f1 'static void DMAppSizeDebugTrigger(NSString *cmd) {' "$1" > "$W/dt3" \
    && grep -qF 'if (DMSMEngine()) { CGSize scr = CGSizeZero; CGRect u = DMSMUsableAreaForIdentity(identity, &scr); frame = [NSString stringWithFormat:@" at %@", NSStringFromCGRect(DMSMOpeningFrameIn(b, u, scr, identity, NULL))]; }' "$W/dt3" \
    && grep -qF 'DMSMEngine() ? MSBDOpensFree(app, gNewWindowsFill, DMSMOpensAtOwnSize(b), NO) : MSBDOpensFree(app, gNewWindowsFill, DMOpensAtOwnPlace(b), NO)' "$W/dt3"
}
c3_noinline() {
  local n
  for n in 'DMForgetSavedLastFrame(NSString *bundle)' 'DMAppSizeForgetPlace(NSString *bundle)' 'DMAppSizesLoad(void)' 'DMAppSizeWriteSMPreZoom(void)' 'DMSMAppSizeForgetPlace(NSString *bundle)'; do
    [ "$(grep -cF "__attribute__((noinline)) static void $n;" "$1")" = 1 ] && order "__attribute__((noinline)) static void $n;" "static void $n {" "$1" || return 1
  done
}
c3_rules() {
  local r; r=$(awk '$1 == "sym" && $2 == "MacStatusBarCore" && $4 == "appWindowSizes" {print $3}' "$2"); [ -n "$r" ] || return 1
  local w; w=$(awk '$1 == "sym" && $2 == "MacStatusBarCore" && $3 == "^_*DMSM[A-Z0-9]" {print $3}' "$2"); [ -n "$w" ] || return 1
  python3 -I -c '
import re, sys
a, w = sys.argv[1], sys.argv[2]
piece = ["DMSMAppSizeForgetPlace", "DMAppSizeWriteSMPreZoom", "DMAppSizeForgetPlace"]
window = ["DMSMOpeningFrameIn", "DMSMNewWindowFrameAt", "DMSMNewWindowFrameIn", "DMSMForgetPlacesOf", "DMSMForgetApp", "DMSMJoinAttributesOn", "DMSMFitAsksAbout"]
ok = all(re.search(a, "_" + n) for n in piece) and not any(re.search(a, "_" + n) for n in window) and all(re.search(w, "_" + n) for n in window)
sys.exit(0 if ok else 1)' "$r" "$w"
}
run_sites() {   # run_sites <StatusBar.x> <rules> [quiet] [prefix]: every C2 and C3 site check (or those whose function starts with prefix); exit 0 when all pass
  local bad=0 e name fn
  for e in "${sites[@]}"; do
    name="${e%|*}"; fn="${e##*|}"
    [ -z "$4" ] || [ "${fn#$4}" != "$fn" ] || continue
    if ( $fn "$1" "$2" ) 2>/dev/null; then [ -n "$3" ] || echo "PASS  $name"; else [ -n "$3" ] && return 1; echo "FAIL  $name"; bad=1; fi   # (quiet: a copy fails at its first failing check)
  done
  return $bad
}
run_sites $S $C || fails=1
echo "-- made-to-fail copies of StatusBar.x and the rules (each must fail the site checks):"
smtf() {   # smtf <name> <file: S or C> <perl substitution>
  local d="$W/smtf$((++sn))"; mkdir -p "$d"; cp $S "$d/S"; cp $C "$d/C"; perl -0pi -e "$3" "$d/$2"
  if cmp -s "$d/$2" "$([ "$2" = S ] && echo $S || echo $C)"; then echo "FAIL  made-to-fail copy $1: the change did not apply"; fails=1; return; fi
  if run_sites "$d/S" "$d/C" quiet; then echo "FAIL  made-to-fail copy $1 PASSED (it must fail)"; fails=1; else echo "PASS  made-to-fail copy $1 fails, as it must"; fi
}
sn=0
smtf "MilkyWay4's new window left on Window Size (no app asked)" S 's/               : DMOpeningWindowFrameFor\(bundle\);/               : DMOpeningWindowFrameFor(nil);/'
smtf "the green light's way back left on Window Size (SB:8418, the old DMOpeningWindowFrame)" S 's/CGRectValue : DMOpeningWindowFrameFor\(bundleID\);\n    if \(DMActiveEngine\(\) == DMEngineZetsu\)/CGRectValue : DMOpeningWindowFrameFor(nil);\n    if (DMActiveEngine() == DMEngineZetsu)/'
smtf "Zetsu's adopt left on Window Size" S 's/lastPlace.CGRectValue : DMOpeningWindowFrameFor\(bundleID\)\)\);/lastPlace.CGRectValue : DMNewWindowFrame()));/'
smtf "Aerial's windowed launch left on Window Size" S 's/CGRect target = DMOpeningWindowFrameFor\(bundleID\);   \/\/ \(where a new window opens/CGRect target = DMNewWindowFrame();   \/\/ (where a new window opens/'
smtf "the opening frame with Open at Fill winning over the app's size" S 's/    if \(s == kMSBDOpenFill\) \{\n        DM_FEATURE_MARK\("new-windows-fill"\);/    if (s == kMSBDOpenFill || gNewWindowsFill) {\n        DM_FEATURE_MARK("new-windows-fill");/'
smtf "the iPhone window without the engines' minimum" S 's/MSBDWindowPhoneIn\(u, kMSBDWindowBarHeight, MSBDWindowMinSize\(\)\)/MSBDWindowPhoneIn(u, kMSBDWindowBarHeight, CGSizeZero)/'
smtf "Fit still tiling an app with its own size (no own-size branch)" S 's/    if \(ownSizeOpening\) goto regularWindow;\n//'
smtf "the free mark before the cascade (1.8.7's return: marked at once, never cascaded)" S 's/    if \(ownSizeOpening\) goto regularWindow;/    if (ownSizeOpening) { DMMarkFreeWindow(me); goto regularWindow; }/; s/    if \(\[gFreeWindows containsObject:me\] && !ownSizeOpening\) return;/    if ([gFreeWindows containsObject:me]) return;/'
smtf "the own-size window never marked free (Fit tiles it at the next window)" S 's/        DM_FEATURE_MARK\("app-window-size-free"\);\n        DMMarkFreeWindow\(me\);\n/        DM_FEATURE_MARK("app-window-size-free");\n/'
smtf "Aerial 3.0 taking an app at Medium for plain Default (its own frame kept)" S 's/!MSBDOpeningIsPlainDefault\(app, gWindowSizeChoice, gNewWindowsFill\)/(gWindowSizeChoice != MSBDWindowSizeDefault || gNewWindowsFill)/'
smtf "the Fill branch on the switch alone (an app at Fill not put there)" S 's/BOOL atFill = MSBDNewWindowAtFill\(MSBDOpeningSize\(app, gWindowSizeChoice, gNewWindowsFill\) == kMSBDOpenFill, own, preLaunched\);/BOOL atFill = MSBDNewWindowAtFill(gNewWindowsFill, own, preLaunched);/'
smtf "Aerial 5.x's way-back DMCascadeStage (SB:35282) dropped" S 's/if \(DMAerialGreenOpensNew\(bundle\)\) \{ DM_FEATURE_MARK\("aerial-green-new-window"\); DMCascadeStage\(stage\); \}/if (DMAerialGreenOpensNew(bundle)) { DM_FEATURE_MARK("aerial-green-new-window"); }/'
smtf "the side question still asked for an app with its own size" S 's/MSBDOpensFree\(DMAppSizeOf\(bundleID\), gNewWindowsFill, DMOpensAtOwnPlace\(bundleID\), NO\)/MSBDNewWindowAtFill(gNewWindowsFill, DMOpensAtOwnPlace(bundleID), NO)/'
smtf "Aerial's green without the record (A7 b's 1.8.7 hole)" S 's/    DMRememberStageFrame\(stage\);\n    objc_setAssociatedObject\(stage, kStageClosingKey/    objc_setAssociatedObject(stage, kStageClosingKey/'
smtf "Zetsu's green without the record" S 's/    DMRememberStageFrame\(\(UIView \*\)w\);\n//'
smtf "Aerial's record after the closing mark (DMRememberStageFrame refuses then)" S 's/    DMRememberStageFrame\(stage\);\n(    objc_setAssociatedObject\(stage, kStageClosingKey, \@YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC\);[^\n]*\n)/$1    DMRememberStageFrame(stage);\n/'
smtf "the record before the context menu's wait (not MilkyWay4's point, amendment 6)" S 's/(    if \(DMWaitForContextMenu\(\[NSString stringWithFormat:\@"full screen %p", stage\], \^\{ DMAerialToFullScreen\(stage\); \}\)\) return;\n)/    DMRememberStageFrame(stage);\n$1/; s/(    \/\/ \(where it was is where green on the full-screen app brings it back, whatever moved it last, as MilkyWay4.s DMExpandWindowToFullScreen records\n(?:    \/\/[^\n]*\n)*)    DMRememberStageFrame\(stage\);\n/$1/'
smtf "the read rule bypassed (the stored dictionary taken as it is)" S 's/NSDictionary \*now = CFBridgingRelease\(MSBDAppSizesRead\(v, &bad, &over, &wrong\)\);/NSDictionary *now = [(__bridge NSDictionary *)v copy];/'
smtf "DMLoadPrefs forgetting on the first read (an empty table as the baseline)" S 's/MSBDAppSizesToForget\(gAppSizesRead, \(__bridge CFDictionaryRef\)gAppSizes,/MSBDAppSizesChanged((__bridge CFDictionaryRef)(gAppSizes ?: \@{}),/'
smtf "the baseline flag set before the comparison (the first read compares)" S 's/    BOOL first = !gAppSizesRead,/    gAppSizesRead = YES;\n    BOOL first = !gAppSizesRead,/'
smtf "no forget on change" S 's/    for \(NSString \*b in forget\) DMAppSizeForgetPlace\(b\);\n//'
smtf "the forget calling DMSaveWindowState in place of DMForgetSavedLastFrame" S 's/    DMForgetSavedLastFrame\(bundle\);\n    DMSMAppSizeForgetPlace/    DMSaveWindowState();\n    DMSMAppSizeForgetPlace/'
smtf "the forget leaving Stage Manager's saved places (amendment 6)" S 's/    DMSMAppSizeForgetPlace\(bundle\);\n    if \(!gAppSizeForgotten\)/    if (!gAppSizeForgotten)/'
smtf "the forget clearing minimized marks" S 's/(static void DMSMAppSizeForgetPlace\(NSString \*bundle\) \{\n    bundle = DMSMKeyBundle\(bundle\);\n    if \(!bundle.length\) return;\n)/$1    DMSMSetMinimized(bundle, NO);\n/'
smtf "the forget clearing the app's free mark" S 's/    \[gLastWindowFrames removeObjectForKey:bundle\];\n    DMFitForgetFullScreenWayBack/    [gLastWindowFrames removeObjectForKey:bundle]; [gFreeWindows removeObject:bundle];\n    DMFitForgetFullScreenWayBack/'
smtf "the forget taking the whole Fit record (the review of F1-F4: a quit while full screen left the other window in its half)" S 's/    DMFitForgetFullScreenWayBack\(bundle, /    DMFitForgetFullScreenTile(bundle, /'
smtf "the saved state's forget on its own queue (out of order with DMSaveWindowState)" S 's/        dispatch_async\(DMWindowStateWriter\(\), \^\{ \[state writeToFile:path atomically:YES\]; \}\);\n        DMLog/        dispatch_async(dispatch_get_global_queue(0, 0), ^{ [state writeToFile:path atomically:YES]; });\n        DMLog/'
smtf "the saved state's forget dropping every lastFrames entry" S 's/    \[left removeObjectForKey:bundle\];\n    if \(left.count\) out\[\@"lastFrames"\] = \[left copy\]; else \[out removeObjectForKey:\@"lastFrames"\];/    [out removeObjectForKey:\@"lastFrames"]; [out removeObjectForKey:\@"windows"];/'
smtf "DMRestoreLastFrames not skipping a forgotten app" S 's/        if \(\[gAppSizeForgotten containsObject:b\]\) continue;[^\n]*\n//'
smtf "Stage Manager's file written whole by the forget (its minimized set and layouts from memory)" S 's/if \(DMSMForgetPlacesOf\(bundle\)\) DMAppSizeWriteSMPreZoom\(\);/if (DMSMForgetPlacesOf(bundle)) DMSMStateWrite();/'
smtf "DMAppSizeOf not reading the crash piece" S 's/ \|\| !gAppSizes.count \|\| DMAppSizesSkipped\(\)\) return MSBDAppSizeNone;/ || !gAppSizes.count) return MSBDAppSizeNone;/'
smtf "the load reading with the piece off" S 's/    if \(DMAppSizesSkipped\(\)\) return;\n    CFPropertyListRef v/    CFPropertyListRef v/'
smtf "a debug trigger that writes (the stored list)" S 's/(    if \(dict\) CFRelease\(dict\);\n)/$1    CFPreferencesSetValue(CFSTR(kMSBDAppWindowSizesKey), NULL, MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);\n/'
smtf "the crash piece's sym rule left out" C 's/sym MacStatusBarCore \^_\*\(DMAppSize\|DMSMAppSize\|DMForgetSavedLastFrame\) appWindowSizes\n//'
smtf "the crash piece's target left out" C 's/target appWindowSizes piece [^\n]*\n//'
smtf "AppWindowSize.h under WindowSize.h's file rule (the header's rule after it)" C 's/(file MacStatusBarCore \^AppWindowSize\\\.h\$ appWindowSizes\n)//; s/(file MacStatusBarCore \^\(WindowCards\|WindowMinSize\|WindowSize\|FitPlan\|SBLaunchRule\|AerialHeld\)\\\.h\$ windowingEnabled\n)/$1file MacStatusBarCore ^AppWindowSize\\.h\$ appWindowSizes\n/'
echo "-- C3's made-to-fail copies (Stage Manager, the iPad and the TV; each must fail the site checks):"
smtf "the TV's join at the iPad's Window Size (the per-display layer bypassed)" S 's/MSBDOpeningSize\(app, DMWindowSizeChoiceFor\(identity\), DMNewWindowsFillFor\(identity\)\)/MSBDOpeningSize(app, gWindowSizeChoice, DMNewWindowsFillFor(identity))/'
smtf "the TV's join at the iPad's Open at Fill" S 's/MSBDOpeningSize\(app, DMWindowSizeChoiceFor\(identity\), DMNewWindowsFillFor\(identity\)\)/MSBDOpeningSize(app, DMWindowSizeChoiceFor(identity), gNewWindowsFill)/'
smtf "Stage Manager's opening frame not asking the app (Window Size alone)" S 's/int app = DMAppSizeOf\(bundle\), s = MSBDOpeningSize\(app, DMWindowSizeChoiceFor/int app = MSBDAppSizeNone, s = MSBDOpeningSize(app, DMWindowSizeChoiceFor/'
smtf "Open at Fill winning over the app's size on Stage Manager" S 's/    if \(s == kMSBDOpenFill\) return DMSMLayoutFrameIn\(\@"fill", u, scr\);/    if (s == kMSBDOpenFill || DMNewWindowsFillFor(identity)) return DMSMLayoutFrameIn(\@"fill", u, scr);/'
smtf "the phone without Stage Manager's minimum" S 's/return MSBDWindowPhoneIn\(u, kSMBarH, least\);/return MSBDWindowPhoneIn(u, kSMBarH, CGSizeZero);/'
smtf "the phone not under our title bar" S 's/return MSBDWindowPhoneIn\(u, kSMBarH, least\);/return MSBDWindowPhoneIn(u, 0, least);/'
smtf "the join left on 1.8.7's window (Window Size and Open at Fill, no app)" S 's/CGRect opening = DMSMOpeningFrameIn\(bundle, u, scr, onDisplay, &atFill\);/atFill = MSBDNewWindowAtFill(DMNewWindowsFillFor(onDisplay), false, false); CGRect opening = atFill ? DMSMLayoutFrameIn(\@"fill", u, scr) : DMSMNewWindowFrameIn(u, scr, onDisplay);/'
smtf "the TV's join asked for no display (the iPad's)" S 's/DMSMOpeningFrameIn\(bundle, u, scr, onDisplay, &atFill\)/DMSMOpeningFrameIn(bundle, u, scr, nil, &atFill)/'
smtf "the join's app read from the window's key (a second window of the app at Window Size)" S 's/                int app = DMAppSizeOf\(bundle\);/                int app = DMAppSizeOf(key);/'
smtf "Fit still tiling a window at the app's own size on Stage Manager" S 's/BOOL opensFree = MSBDOpensFree\(app, DMNewWindowsFillFor\(onDisplay\), false, false\);/BOOL opensFree = atFill;/'
smtf "the free mark before the cascade on Stage Manager" S 's/(                if \(opensFree && DMFitEnabled\(\)\) \{[^\n]*\n)//; s/(                CGRect others\[32\]; int n = 0;\n)/                if (opensFree && DMFitEnabled()) { if (!gSMFreeWindows) gSMFreeWindows = [NSMutableSet set]; [gSMFreeWindows addObject:key]; }\n$1/'
smtf "the side question still asked for an app with its own size on Stage Manager" S 's/MSBDOpensFree\(DMAppSizeOf\(DMSMKeyBundle\(bundle\)\), gNewWindowsFill, DMSMOpensAtOwnSize\(bundle\), NO\)/MSBDNewWindowAtFill(gNewWindowsFill, DMSMOpensAtOwnSize(bundle), NO)/'
smtf "the way back with no place not joining as a new window" S 's/back = DMSMJoinAttributes\(wk, attrs, YES, t - 1, stage\);/back = nil;/'
smtf "No Fit's place at the app's size (Window Size's other use)" S 's/\? DMSMNewWindowFrameIn\(u, scr, identity\) : MSBDWindowNoFitIn/? DMSMOpeningFrameIn(nil, u, scr, identity, NULL) : MSBDWindowNoFitIn/'
smtf "the Stage Manager forget leaving gSMPreZoomPlaces" S 's/    for \(NSString \*k in \[DMSMPreZoomPlaces\(\) allKeys\]\) if \(\[DMSMKeyBundle\(k\) isEqualToString:bundle\]\) \{ \[gSMPreZoomPlaces removeObjectForKey:k\]; placesGone = YES; \}\n//'
smtf "the Stage Manager forget leaving gSMPreZoom" S 's/    for \(NSString \*k in \[gSMPreZoom allKeys\]\) if \(\[DMSMKeyBundle\(k\) isEqualToString:bundle\]\) \[gSMPreZoom removeObjectForKey:k\];\n//'
smtf "the forget leaving the tile for full screen (gSMFitWentFull)" S 's/        \[gSMFitWentFull removeObject:k\]; full\+\+;\n/        full++;\n/'
smtf "the forget dropping the arrangement another window left" S 's/    if \(leftTile\) gSMFitSlotsBeforeFull = nil;/    gSMFitSlotsBeforeFull = nil;/'
smtf "the forget clearing Stage Manager's free mark" S 's/(static void DMSMAppSizeForgetPlace\(NSString \*bundle\) \{\n    bundle = DMSMKeyBundle\(bundle\);\n    if \(!bundle.length\) return;\n)/$1    [gSMFreeWindows removeObject:bundle];\n/'
smtf "the forget dropping Fit's arrangement of the open windows" S 's/(static void DMSMAppSizeForgetPlace\(NSString \*bundle\) \{\n    bundle = DMSMKeyBundle\(bundle\);\n    if \(!bundle.length\) return;\n)/$1    gSMFitSlots = nil;\n/'
smtf "the forget clearing the turn notes" S 's/(static void DMSMAppSizeForgetPlace\(NSString \*bundle\) \{\n    bundle = DMSMKeyBundle\(bundle\);\n    if \(!bundle.length\) return;\n)/$1    DMSMTurnForget([NSSet setWithObject:bundle], \@"a new size");\n/'
smtf "an app's quit no longer writing the state (DMSMForgetApp's effect changed)" S 's/    if \(DMSMForgetPlacesOf\(bundle\)\) DMSMStateWrite\(\);/    (void)DMSMForgetPlacesOf(bundle);/'
smtf "DMSMForgetPlacesOf writing the whole state itself (every engine's forget would)" S 's/    return placesGone;\n/    if (placesGone) DMSMStateWrite();\n    return placesGone;\n/'
smtf "Stage Manager's forget only with Stage Manager running (a switch of engine keeps it stale)" S 's/    DMSMAppSizeForgetPlace\(bundle\);\n/    if (DMSMEngine()) DMSMAppSizeForgetPlace(bundle);\n/'
smtf "the debug trigger's Stage Manager frame the iPad's on every display" S 's/NSStringFromCGRect\(DMSMOpeningFrameIn\(b, u, scr, identity, NULL\)\)/NSStringFromCGRect(DMSMOpeningFrameIn(b, u, scr, nil, NULL))/'
smtf "the crash piece's sym rule without Stage Manager's forget (under the window rule)" C 's/\(DMAppSize\|DMSMAppSize\|DMForgetSavedLastFrame\) appWindowSizes/(DMAppSize|DMForgetSavedLastFrame) appWindowSizes/'
smtf "the opening frame under the piece (the shared opening path)" C 's/\(DMAppSize\|DMSMAppSize\|DMForgetSavedLastFrame\) appWindowSizes/(DMAppSize|DMSMAppSize|DMSMOpening|DMForgetSavedLastFrame) appWindowSizes/'
smtf "the read and forget inlined into DMLoadPrefs again (no noinline: another piece's range in the release map)" S 's/__attribute__\(\(noinline\)\) static void DMAppSizesLoad\(void\);/static void DMAppSizesLoad(void);/'
smtf "Stage Manager's forget inlined (no noinline)" S 's/__attribute__\(\(noinline\)\) static void DMSMAppSizeForgetPlace\(NSString \*bundle\);/static void DMSMAppSizeForgetPlace(NSString *bundle);/'
echo "-- review R1's made-to-fail copies (the behind-the-Dock mark and the forgotten place; each must fail the site checks):"
smtf "MilkyWay4's window with no place of its own keeping the mark" S 's/    if \(bundle && !gLastWindowFrames\[bundle\]\) DMBehindDockSet\(bundle, NO, [^\n]*\n//'
smtf "MilkyWay4's mark kept on the green light's way back (its pending frame)" S 's/    if \(bundle && !gLastWindowFrames\[bundle\]\) DMBehindDockSet\(bundle,/    if (bundle \&\& !pending \&\& !gLastWindowFrames[bundle]) DMBehindDockSet(bundle,/'
smtf "Zetsu's window with no place of its own keeping the mark" S 's/    if \(!lastPlace\) DMBehindDockSet\(bundleID, NO, [^\n]*\n//'
smtf "Zetsu's mark read after the move (the move has recorded the new place: never taken)" S 's/(    NSValue \*lastPlace = gLastWindowFrames\[bundleID\];\n)    if \(!lastPlace\) DMBehindDockSet[^\n]*\n/$1/; s/(    if \(!CGRectIsNull\(target\) && !gRestoringWindowsFlag\(\)\) DMZetsuMove\(w, target, NO, nil\);\n)/$1    if (!gLastWindowFrames[bundleID]) DMBehindDockSet(bundleID, NO, \@"its window opens with no place of its own kept (App Window Sizes)");\n/'
smtf "Zetsu's mark taken from a window back at its own place too" S 's/    if \(!lastPlace\) DMBehindDockSet\(bundleID,/    DMBehindDockSet(bundleID,/'
smtf "Aerial's window with no place of its own keeping the mark" S 's/    if \(DMActiveEngine\(\) == DMEngineAerial && !gLastWindowFrames\[me\]\) DMBehindDockSet\(me, NO, [^\n]*\n//'
smtf "Aerial's mark taken on Aerial 5.x only (Aerial 3.0's window keeps it)" S 's/    if \(DMActiveEngine\(\) == DMEngineAerial && !gLastWindowFrames\[me\]\) DMBehindDockSet/    if (gAerialFlavor == 5 \&\& DMActiveEngine() == DMEngineAerial \&\& !gLastWindowFrames[me]) DMBehindDockSet/'
smtf "the forget taking Aerial's, Zetsu's and MilkyWay4's mark (a window still open behind the Dock lifted at the next turn)" S 's/(    \[gLastWindowFrames removeObjectForKey:bundle\];\n)(    DMFitForgetFullScreenWayBack)/$1    DMBehindDockSet(bundle, NO, \@"its size changed");\n$2/'
smtf "the mark's forward declaration gone (read before its definition)" S 's/static void DMBehindDockSet\(NSString \*bundle, BOOL behind, NSString \*why\);[^\n]*\n//'
smtf "Stage Manager's forget leaving the marks" S 's/    for \(NSString \*k in went\) if \(DMSMKeySetRemove\(gSMBehindDock, k\)\) marks\+\+;\n//'
smtf "Stage Manager's forget taking every mark of the app (a window still open behind the Dock too)" S 's/    for \(NSString \*k in went\) if \(DMSMKeySetRemove\(gSMBehindDock, k\)\) marks\+\+;/    if (DMSMKeySetRemove(gSMBehindDock, bundle)) marks++;/'
smtf "Stage Manager's windows read after the forget (none left: no mark taken)" S 's/((?:    for \(NSString \*k in (?:gSMPreZoom|DMSMPreZoomPlaces\(\))\) [^\n]*\n){2})(    if \(DMSMForgetPlacesOf\(bundle\)\) DMAppSizeWriteSMPreZoom\(\);\n)/$2$1/'
smtf "Stage Manager's forget reading the places in memory only (a place kept across a respring keeps its mark)" S 's/    for \(NSString \*k in DMSMPreZoomPlaces\(\)\) if \(\[DMSMKeyBundle\(k\) isEqualToString:bundle\]\) \[went addObject:k\];\n//'
smtf "an app's quit taking the marks too (DMSMForgetPlacesOf, shared with it)" S 's/(    return placesGone;\n)/    DMSMKeySetRemove(gSMBehindDock, bundle);\n$1/'
echo "-- the files before C3 (243bfb32) fail C3's site checks:"
if [ -s "$W/base-S" ]; then
  git -C .. show 243bfb32:tools/crashmap-rules.txt > "$W/C-c2" 2>/dev/null || git -C .. show d9ced6e8:tools/crashmap-rules.txt > "$W/C-c2"
  if run_sites "$W/base-S" "$W/C-c2" quiet c3_; then echo "FAIL  the files before C3 PASS C3's site checks"; fails=1; else echo "PASS  the files before C3 fail them, as they must"; fi
else echo "SKIP  243bfb32 (d9ced6e8) not in this repository"; fi
echo "-- the files before C2 (7137b2f1) fail the site checks:"
if git -C .. cat-file -e 7137b2f1:statusbar/StatusBar.x 2>/dev/null; then
  git -C .. show 7137b2f1:statusbar/StatusBar.x > "$W/S-c1"; git -C .. show 7137b2f1:tools/crashmap-rules.txt > "$W/C-c1"
  if run_sites "$W/S-c1" "$W/C-c1" quiet; then echo "FAIL  the files before C2 PASS the site checks"; fails=1; else echo "PASS  the files before C2 fail them, as they must"; fi
else echo "SKIP  7137b2f1 not in this repository"; fi
echo "-- the files before review R1's fix (bf596d93, or its -reg twin 0a8cb43c: the same tree) fail each of R1's checks:"
for c in bf596d93 0a8cb43c; do git -C .. show $c:statusbar/StatusBar.x > "$W/S-l" 2>/dev/null && git -C .. show $c:tools/crashmap-rules.txt > "$W/C-l" 2>/dev/null && break; rm -f "$W/S-l"; done
if [ -s "$W/S-l" ]; then
  for r1 in c_behind c3_behind c3_behindrun; do
    if ( $r1 "$W/S-l" "$W/C-l" ) 2>/dev/null; then echo "FAIL  the files before R1's fix PASS $r1"; fails=1; else echo "PASS  the files before R1's fix fail $r1, as they must"; fi
  done
else echo "SKIP  bf596d93 (0a8cb43c) not in this repository"; fi
# ---- C4 (design 5.1, 3.2 and 4.4 with amendments 2-5): the Settings pages ---------------------------------------------------------------------
# The checks read a directory of the Settings files (c4set), so a copy with one thing broken runs the same checks: those made-to-fail copies must
# each fail, and so must the files before C4 (9ef0e161).
c4set() {   # c4set <dir> [tree]: the Settings files of the tree (default: this one) copied into dir under short names
  local t="${2:-..}"; mkdir -p "$1"
  cp "$t/statusbar/macstatusbarprefs/Resources/Windows.plist" "$1/PL"; cp "$t/statusbar/macstatusbarprefs/MSBRootListController.m" "$1/P"
  cp "$t/statusbar/macstatusbarprefs/Makefile" "$1/MK"; cp "$t/common/OwnPageRows.h" "$1/R"; cp "$t/common/DisplayRows.h" "$1/DR"
  cp "$t/statusbar/macstatusbarprefs/MSBAppSizesController.m" "$1/A" 2>/dev/null || : > "$1/A"
  cp "$t/statusbar/macstatusbarprefs/MSBAppSizesController.h" "$1/AH" 2>/dev/null || : > "$1/AH"
  cp "$t/statusbar/macstatusbarprefs/MSBSettingsStack.h" "$1/SS" 2>/dev/null || : > "$1/SS"
}
c4sites=(
"Windows.plist: App Window Sizes right under Window Size in the Windows group, a link to its own page with its count on the right (PSLinkListCell, the list's controller, a getter), no stored value of its own|c4_row"
"  ... the Windows & Multitasking page: the count from the stored list as SpringBoard reads it (\"2 Apps\", \"1 App\", none nothing), its row reloaded each time the page appears (amendment 4)|c4_count"
"  ... shown wherever Window Size is, on the page and in the search: the rules take the row as Window Size's (MSBDRowRuleKey at the rule's top and at both of the page's engine checks)|c4_rules"
"the texts: Window Size's page and the TV's Window Size row say apps in App Window Sizes open at their own size; New Windows Open at Fill's paragraph ends \"Apps with their own size open at that size.\", the plist's and the page's words the same|c4_texts"
"the list: the apps by name, each a link to its page with its size on the right and its icon; one not installed by its bundle id with \"Not Installed\" under it (amendment 5: the Go menu's place); the list's footer the two sentences, its group (header and footer) only with apps in it|c4_list"
"Add App: AltList's single-app picker by NSClassFromString only, as Custom Shortcuts' App row (Visible apps, the search bar, a getter that checks no app); no ATL class subclassed, named in an interface or category, or made at run time; no AltList in the Makefile|c4_altlist"
"  ... without the picker's class no Add App row and no footer of its own; 200 apps listed: the row greyed with \"You can add up to 200 apps.\"; an empty list: Add App's own line, \"Apps you add here open at their own size instead of Window Size.\"|c4_noaltlist"
"  ... the selection writes nothing: the app kept, once per opening of the picker (a second call ignored, amendment 3), and its page opened only from the list settled, never in the setter's turn (dispatch_async) nor from viewDidAppear itself (it queues the settled opener); the settled opener the only push, the pick cleared before it; a tap on any row of the list drops a waiting pick|c4_setter"
"  ... no page pushed from viewWillAppear: the list's only reloads; the page shown only through the list's own way (controllerForSpecifier, showController)|c4_appear"
"the app's page: the five sizes in order (Small, Medium, Large, Fill, iPhone; no Custom), the chosen one checked, nothing checked and nothing stored for an app opened from Add App; the footer by the choice; Remove App only once it has a size, in red|c4_page"
"  ... the writes: a tap on a size or Remove App only, through MSBDAppSizesWith (the key removed with the last app, never an empty dictionary), synchronized, SpringBoard told (prefsChanged); no other key; 200 listed: no other app added|c4_writes"
"  ... Remove App goes back to the App Window Sizes list (popToViewController to the list in the navigation stack)|c4_remove"
"the bundle: MSBAppSizesController.m in the prefs Makefile, its header for the row's value; no em or en dash in the Settings files|c4_files"
"Add App on Settings' navigation stack, 15 to 17 and 18 alike (F1, the A12Z's S1 on 18.5: the pick left the picker up, its page only after Back): every comparison with the stack through the page's entry (MSBSettingsStack.h); the list's methods as written, run on a stack of pages (15 to 17) and of hosting controllers each holding its page (18, and one level deeper): the picker closes with a slide, then the page (S1-F1, row E1 of p03 on 18.5: one change to the stack at a time, also on a stand-in of SwiftUI's own record of the stack): the pick's next turn closes the picker with Back's popTo and pushes nothing, the page is pushed a turn after the list's viewDidAppear from the list settled (its entry on top, in the window, nothing moving), a running transition is waited for to its end, a pick is dropped once the list is not in front; no push in the same turn as a pop; no setViewControllers; the open page not pushed again; Remove App back to the list's entry, unchanged; nothing stored|c4_stack"
)
c4_row() {
  python3 -I - "$1/PL" <<'PY'
import plistlib,sys
it=plistlib.load(open(sys.argv[1],'rb'))['items']
ids=[x.get('id') for x in it]
i=ids.index('WINDOW_SIZE'); r=it[i+1]
g=[x for x in it[:i+1] if x.get('cell')=='PSGroupCell'][-1]
ok = r.get('id')=='APP_WINDOW_SIZES' and r.get('cell')=='PSLinkListCell' and r.get('detail')=='MSBAppSizesController' and r.get('get')=='msb_appWindowSizesValue:' \
  and r.get('label')=='App Window Sizes' and not any(k in r for k in ('key','defaults','default','validValues','validTitles','set','PostNotification')) \
  and g.get('id')=='WINDOWS_GROUP' and ids.count('APP_WINDOW_SIZES')==1
sys.exit(0 if ok else 1)
PY
}
c4_count() {
  awk '/^@implementation MSBWindowsListController/{f=1} f{print} f&&/^@end/{exit}' "$1/P" > "$1/wl" \
    && grep -qxF -- '- (id)msb_appWindowSizesValue:(PSSpecifier *)spec { return MSBAppSizesRowValue(); }' "$1/wl" \
    && f1 '- (void)viewWillAppear:(BOOL)animated {' "$1/wl" > "$1/wa" && grep -qF 'PSSpecifier *sizes = [self specifierForID:@"APP_WINDOW_SIZES"];' "$1/wa" && grep -qxF '	if (sizes) [self reloadSpecifier:sizes animated:NO];' "$1/wa" \
    && grep -qF '#import "MSBAppSizesController.h"' "$1/P" && grep -qxF 'NSString *MSBAppSizesRowValue(void);' "$1/AH" \
    && f1 'NSString *MSBAppSizesRowValue(void) {' "$1/A" | grep -qF 'MSBDAppSizesCountText((CFIndex)MSBASListed().count, text, sizeof text);' \
    && grep -qF 'static NSDictionary<NSString *, NSNumber *> *MSBASListed(void) { return CFBridgingRelease(MSBDAppSizesRead((__bridge CFTypeRef)MSBASStored(), NULL, NULL, NULL)); }' "$1/A"
}
c4_rules() {
  grep -qF '#define kMSBDAppWindowSizesRowID @"APP_WINDOW_SIZES"' "$1/R" \
    && grep -qxF 'static inline NSString *MSBDRowRuleKey(NSString *key, NSString *ident) { return [ident isEqualToString:kMSBDAppWindowSizesRowID] ? kMSBDWindowSizeRowKey : key; }' "$1/R" \
    && awk '/^static inline BOOL MSBDOwnRowHidden\(/ {getline; print; exit}' "$1/R" | grep -qF '    key = MSBDRowRuleKey(key, ident);' \
    && grep -qF 'if (!hiding || windowsGroup || MSBDNoEngineKeepsRow(MSBDRowRuleKey([sp propertyForKey:@"key"], sp.identifier))) [kept addObject:sp];' "$1/P" \
    && grep -qF 'BOOL itsToo = MSBDStageManagerKeepsRow(MSBDRowRuleKey([sp propertyForKey:@"key"], sp.identifier));' "$1/P"
}
c4_texts() {
  python3 -I - "$1/PL" "$1/P" "$1/DR" <<'PY'
import plistlib,sys,re
it=plistlib.load(open(sys.argv[1],'rb'))['items']
ws=[x for x in it if x.get('id')=='WINDOW_SIZE'][0]
wb=[x for x in it if x.get('id')=='WINDOW_BEHAVIOR_GROUP'][0]
para="New Windows Open at Fill: new windows fill the desktop, and Fit to Window doesn't tile them. Apps with their own size open at that size."
code=open(sys.argv[2]).read()
ok = ws.get('staticTextMessage')=="The size an app's window opens at. A window that opens where it last was keeps its size. Apps in App Window Sizes open at their own size." \
  and wb.get('footerText','').split('\n\n')[0]==para and ('@"newWindowsFill": @"%s",' % para) in code \
  and '{ "WINDOW_SIZE", "Window Size", "The size a new window on this display opens at. Apps in App Window Sizes open at their own size.", kMSBDRowChoice,' in open(sys.argv[3]).read()
sys.exit(0 if ok else 1)
PY
}
c4_list() {
  f1 '- (NSMutableArray *)specifiers {' <(awk '/^@implementation MSBAppSizesController/{f=1} f' "$1/A") > "$1/ls" && [ -s "$1/ls" ] \
    && grep -qF 'NSDictionary *listed = MSBASListed(), *installed = MSBASInstalledApps();' "$1/ls" \
    && python3 -I -c 'import sys; sys.exit(0 if sys.argv[2] in open(sys.argv[1]).read() else 1)' "$1/ls" $'\t\tif (listed.count) {   // (the list\'s group only with apps in it: its footer points at them)\n\t\t\tPSSpecifier *g = [PSSpecifier groupSpecifierWithName:@"Apps"];\n\t\t\t[g setProperty:@"These apps open at their own size instead of Window Size. You can still resize them." forKey:@"footerText"];\n\t\t\t[s addObject:g];\n\t\t}\n' \
    && [ "$(grep -c 'footerText' "$1/ls")" = 3 ] && [ "$(grep -c 'groupSpecifierWithName' "$1/ls")" = 2 ] \
    && grep -qF 'return [(installed[x] ?: x) localizedCaseInsensitiveCompare:(installed[y] ?: y)];' "$1/ls" \
    && grep -qF 'PSSpecifier *r = [PSSpecifier preferenceSpecifierNamed:name ?: b target:self set:NULL get:@selector(msbAppValue:) detail:[MSBAppSizeController class] cell:PSLinkListCell edit:Nil];' "$1/ls" \
    && grep -qF '[r setProperty:b forKey:kMSBASBundleKey];' "$1/ls" && grep -qF 'if (!name) [r setProperty:[MSBAppSizeMissingCell class] forKey:@"cellClass"];' "$1/ls" \
    && grep -qF '[UIImage _applicationIconImageForBundleIdentifier:b format:0 scale:scale];' "$1/ls" \
    && f1 '- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {' "$1/A" | grep -qxF '	self.detailTextLabel.text = @"Not Installed";' \
    && f1 '- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid specifier:(PSSpecifier *)specifier {' "$1/A" | grep -qF 'initWithStyle:UITableViewCellStyleSubtitle' \
    && f1 '- (id)msbAppValue:(PSSpecifier *)spec {' "$1/A" > "$1/av" && order 'if ([spec propertyForKey:@"cellClass"]) return nil;' 'MSBDAppSizeTitle(MSBASChoiceIn(MSBASListed(), b))' "$1/av" \
    && f1 'static NSDictionary<NSString *, NSString *> *MSBASInstalledApps(void) {' "$1/A" | grep -qF 'SEL all = NSSelectorFromString(@"allInstalledApplications");'
}
c4_altlist() {
  local code; code=$(grep -v '^ *//' "$1/A" | sed 's|//.*||')
  [ "$(printf '%s\n' "$code" | grep -o 'ATL[A-Za-z]*' | wc -l | tr -d ' ')" = 1 ] \
    && printf '%s\n' "$code" | grep -qF 'return NSClassFromString(@"ATLApplicationListSelectionController");' \
    && ! grep -q 'objc_allocateClassPair\|class_addMethod\|objc_registerClassPair\|class_setSuperclass' "$1/A" \
    && ! grep -q '@interface[^(]*:[^<]*ATL\|@interface ATL\|@implementation ATL\|objc_getClass("ATL' "$1/A" \
    && f1 '- (NSMutableArray *)specifiers {' <(awk '/^@implementation MSBAppSizesController/{f=1} f' "$1/A") > "$1/ls" \
    && grep -qF 'PSSpecifier *a = [PSSpecifier preferenceSpecifierNamed:@"Add App…" target:self set:@selector(msbPickedApp:specifier:) get:@selector(msbPickerApp:) detail:picker cell:PSLinkListCell edit:Nil];' "$1/ls" \
    && grep -qF '[a setProperty:@[@{ @"sectionType": @"Visible" }] forKey:@"sections"];' "$1/ls" && grep -qF '[a setProperty:@YES forKey:@"useSearchBar"];' "$1/ls" \
    && grep -qF '[a setProperty:@YES forKey:@"hideSearchBarWhileScrolling"];' "$1/ls" && grep -qF '[a setIdentifier:@"APP_SIZES_ADD"];' "$1/ls" \
    && grep -qxF -- '- (id)msbPickerApp:(PSSpecifier *)spec { return nil; }   // (no app checked: the picker opens clean every time)' "$1/A" \
    && ! sed 's/#.*//' "$1/MK" | grep -qi 'altlist\|ATL' && grep -qF 'dlopen("/var/jb/Library/Frameworks/AltList.framework/AltList", RTLD_NOW);' "$1/P"
}
c4_noaltlist() {
  f1 '- (NSMutableArray *)specifiers {' <(awk '/^@implementation MSBAppSizesController/{f=1} f' "$1/A") > "$1/ls" \
    && awk '/^\t\tClass picker = MSBASPickerClass\(\);$/ {getline; if ($0 == "\t\tif (picker) {") p=NR; next} p && /^\t\t}$/ && !e {e=NR}
            /PSSpecifier \*ag = \[PSSpecifier groupSpecifierWithName:nil\];/ {g=NR} /Apps you add here open/ {m=NR} /You can add up to 200 apps\./ {y=NR} /\[s addObject:a\];/ {a=NR}
            END {exit !(p && g > p && m > g && y > m && a > y && e > a)}' "$1/ls" \
    && grep -qxF '			if (!listed.count) [ag setProperty:@"Apps you add here open at their own size instead of Window Size." forKey:@"footerText"];   // (an empty list: Add App'"'"'s own line)' "$1/ls" \
    && grep -qxF '			BOOL canAdd = MSBDAppSizesCanAdd((CFIndex)listed.count);' "$1/ls" \
    && grep -qxF '			if (!canAdd) [ag setProperty:@"You can add up to 200 apps." forKey:@"footerText"];' "$1/ls" && grep -qxF '			[a setProperty:@(canAdd) forKey:@"enabled"];' "$1/ls" \
    && [ "$(grep -c 'MSBASPickerClass()' "$1/A")" = 3 ] && ! grep -q 'needs AltList' "$1/A" \
    && f1 '- (void)msbOpenPickedNextTurn {' "$1/A" | grep -qxF '	UIViewController *picker = [self msbPickerOnTop] ? MSBSSPageIn(nav.topViewController, MSBASPickerClass()) : nil;'   # (S1-F1: the third read, nil-safe: MSBSSPageIn gives nil for Nil)
}
c4_setter() {
  f1 '- (void)msbPickedApp:(id)value specifier:(PSSpecifier *)spec {' "$1/A" > "$1/st" && [ -s "$1/st" ] \
    && ! grep -q 'CFPreferences\|MSBASWrite\|notify_post\|setPreferenceValue\|showController\|msbOpenAppPage\|pushViewController\|popViewController\|popToViewController' "$1/st" \
    && grep -qF 'if (![value isKindOfClass:[NSString class]] || ![value length]) return;' "$1/st" \
    && order 'if (!_pickOpen) {' '	_pickOpen = NO;' "$1/st" && order '	_pickOpen = NO;' '	_picked = [value copy];' "$1/st" \
    && awk 'END {exit !(prev ~ /dispatch_async\(dispatch_get_main_queue\(\), \^\{ \[weakSelf msbOpenPickedNextTurn\]; \}\);/)} /^}/ {exit} {if ($0 !~ /^}/) prev=$0}' "$1/st" \
    && f1 '- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {' <(awk '/^@implementation MSBAppSizesController/{f=1} f' "$1/A") > "$1/ds" \
    && grep -qF 'if (_picked) MSBASLog([NSString stringWithFormat:@"picker: the pick of %@ dropped, a row of the list tapped", _picked]);' "$1/ds" \
    && order '	_picked = nil;' '	_pickOpen = [[MSBASSpecAt(self, ip) identifier] isEqualToString:@"APP_SIZES_ADD"];' "$1/ds" \
    && order '	_pickOpen = [[MSBASSpecAt(self, ip) identifier]' '	[super tableView:tv didSelectRowAtIndexPath:ip];' "$1/ds" \
    && f1 '- (void)msbOpenPickedWhenSettled {' "$1/A" > "$1/ws" && [ "$(awk 'NR == 2' "$1/ws")" = '	if (!_picked) return;   // (two callers: one push)' ] \
    && order '	_picked = nil;   // (cleared before the push: one push only)' '	[self msbOpenAppPage:b];' "$1/ws" \
    && f1 '- (void)viewDidAppear:(BOOL)animated {' "$1/A" > "$1/da" && order 'if (!_picked) return;' '	dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf msbOpenPickedWhenSettled]; });' "$1/da" \
    && [ "$(grep -c '\[self msbOpenAppPage:' "$1/A")" = 1 ] && [ "$(grep -c '\[self msbOpenAppPage:' "$1/ws")" = 1 ] \
    && [ "$(grep -c 'msbOpenPickedNextTurn' "$1/A")" = 3 ] && [ "$(grep -c 'msbOpenPickedWhenSettled' "$1/A")" = 4 ] \
    && f1 '- (void)msbOpenAppPage:(NSString *)bundle {' "$1/A" > "$1/op" && order 'if ([open.msbBundle isEqualToString:bundle]) return;' '[self showController:(PSViewController *)page animate:YES];' "$1/op"
}
c4_appear() {
  awk '/^- \(void\)viewWillAppear:\(BOOL\)animated \{/{f=1} f{print} f&&/^}/{f=0}' "$1/A" > "$1/wa" && [ "$(grep -c 'viewWillAppear' "$1/wa")" = 2 ] \
    && ! grep -q 'msbOpenAppPage\|showController\|pushViewController\|_picked\|dispatch' "$1/wa" && grep -qxF '	_specifiers = nil; [self reloadSpecifiers];   // (back from an app'"'"'s page or the picker: the list as stored now; nothing is opened from here)' "$1/wa" \
    && [ "$(grep -c 'showController' "$1/A")" = 1 ] && f1 '- (void)msbOpenAppPage:(NSString *)bundle {' "$1/A" | grep -qF 'SEL make = NSSelectorFromString(@"controllerForSpecifier:");' \
    && ! grep -q 'pushViewController\|presentViewController' "$1/A"
}
c4_page() {
  f1 '- (NSMutableArray *)specifiers {' <(awk '/^@implementation MSBAppSizeController$/{f=1} f' "$1/A") > "$1/pg" && [ -s "$1/pg" ] \
    && grep -qF 'int now = b ? MSBASChoiceIn(MSBASListed(), b) : MSBDAppSizeNone;' "$1/pg" && grep -qF 'PSSpecifier *g = [PSSpecifier groupSpecifierWithName:@"Opens At"];' "$1/pg" \
    && grep -qF 'const char *footer = MSBDAppSizeFooter(now);' "$1/pg" && grep -qF 'for (int i = 0; MSBDAppSizeChoiceAt(i) != MSBDAppSizeNone; i++) {' "$1/pg" \
    && grep -qF 'preferenceSpecifierNamed:@(MSBDAppSizeTitle(c)) target:self set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];' "$1/pg" \
    && grep -qF 'if (c == now) [r setProperty:@YES forKey:@"msbChecked"];' "$1/pg" && order 'if (MSBDAppSizeValid(now)) {' 'PSSpecifier *d = [PSSpecifier preferenceSpecifierNamed:@"Remove App"' "$1/pg" \
    && ! grep -qi 'custom' "$1/pg" && grep -qF 'c.textLabel.textColor = [UIColor systemRedColor];' "$1/A" \
    && grep -qF 'c.accessoryType = [[sp propertyForKey:@"msbChecked"] boolValue] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;' "$1/A"
}
c4_writes() {
  [ "$(grep -c 'CFPreferencesSetValue' "$1/A")" = 1 ] && [ "$(grep -c 'MSBASWrite(' "$1/A")" = 3 ] \
    && f1 'static void MSBASWrite(NSString *bundle, int choice) {' "$1/A" > "$1/w" \
    && grep -qF 'CFDictionaryRef next = MSBDAppSizesWith((__bridge CFTypeRef)MSBASStored(), (__bridge CFStringRef)bundle, choice);' "$1/w" \
    && grep -qF 'CFPreferencesSetValue(CFSTR(kMSBDAppWindowSizesKey), next, kMSBASDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);' "$1/w" \
    && order 'CFPreferencesSetValue(' 'CFPreferencesSynchronize(kMSBASDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);' "$1/w" \
    && order 'CFPreferencesSynchronize(' 'notify_post("com.besiktasliseba.macstatusbar/prefsChanged");' "$1/w" \
    && grep -qF '#define kMSBASDomain CFSTR("com.besiktasliseba.macstatusbar")' "$1/A" \
    && f1 '- (void)msbPickSize:(PSSpecifier *)spec {' "$1/A" > "$1/ps" && order 'if (now == c) return;' '	MSBASWrite(b, c);' "$1/ps" \
    && order 'if (now == MSBDAppSizeNone && !MSBDAppSizesCanAdd((CFIndex)listed.count)) return;' '	MSBASWrite(b, c);' "$1/ps" \
    && f1 '- (void)msbRemoveApp:(PSSpecifier *)spec {' "$1/A" | grep -qF 'if (b) MSBASWrite(b, MSBDAppSizeNone);' \
    && ! grep -q 'setPreferenceValue\|NSUserDefaults\|writeToFile' "$1/A"
}
c4_remove() {
  f1 '- (void)msbRemoveApp:(PSSpecifier *)spec {' "$1/A" > "$1/rm" && grep -qF 'if (MSBSSPageIn(vc, [MSBAppSizesController class])) { list = vc; break; }' "$1/rm" \
    && order 'if (b) MSBASWrite(b, MSBDAppSizeNone);' '	if (list) [nav popToViewController:list animated:YES];' "$1/rm"
}
c4_files() {
  grep -q '^MacStatusBarPrefs_FILES = .* MSBAppSizesController\.m' "$1/MK" && [ -s "$1/A" ] && [ -s "$1/AH" ] \
    && grep -qF '#import "../../common/AppWindowSize.h"' "$1/A" && ! grep -q "$EM\\|$EN" "$1/A" "$1/AH" "$1/PL" "$1/DR" "$1/SS" test-appsizestack.m
}
# stackrun <c4 dir>: test-appsizestack.m on that dir's MSBAppSizesController.m (the list's tableView:didSelectRowAtIndexPath:, msbPickedApp:specifier:,
# msbPickerOnTop, msbOpenPickedNextTurn, msbOpenPickedWhenSettled, msbAfter:then:, msbOpenAppPage:, viewDidAppear: and the page's msbRemoveApp:,
# pasted as written; a method a file has not is left out) beside its MSBSettingsStack.h (this tree's when the dir has none: the files before F1); its
# exit code, 3 if it does not build
stackrun() {
  local d="$1/stack" h; mkdir -p "$d"; cp test-appsizestack.m "$d/"
  if [ -s "$1/SS" ]; then cp "$1/SS" "$d/MSBSettingsStack.h"; else cp ../statusbar/macstatusbarprefs/MSBSettingsStack.h "$d/"; fi
  awk '/^@implementation MSBAppSizesController/{f=1} f' "$1/A" > "$d/list.m"
  for h in '- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {' '- (void)msbPickedApp:(id)value specifier:(PSSpecifier *)spec {' \
           '- (BOOL)msbPickerOnTop {' '- (void)msbOpenPickedNextTurn {' '- (void)msbOpenPickedWhenSettled {' \
           '- (void)msbAfter:(id<UIViewControllerTransitionCoordinator>)moving then:(void (^)(MSBAppSizesController *me))step {' \
           '- (void)msbOpenAppPage:(NSString *)bundle {' '- (void)viewDidAppear:(BOOL)animated {'; do f1 "$h" "$d/list.m"; done > "$d/appsizestack-list.inc"
  f1 '- (void)msbRemoveApp:(PSSpecifier *)spec {' "$1/A" > "$d/appsizestack-page.inc"
  clang -O0 -fobjc-arc -Wall -Werror -Wno-unused-function -framework Foundation -o "$d/t" "$d/test-appsizestack.m" > "$d/build" 2>&1 || return 3
  "$d/t"
}
c4_stack() {
  stackrun "$1" > "$1/stack.out" 2>&1 && grep -qx 'test-appsizestack: 228 checks, 0 failed' "$1/stack.out" \
    && grep -qxF "KNOWN LIMIT (not a pass): 18 (SwiftUI's record, late): general, windows, list, empty host, empty host | empty hosts 2 | record 3 entries" "$1/stack.out" \
    && grep -qxF '#import "MSBSettingsStack.h"' "$1/A" \
    && f1 '- (BOOL)msbPickerOnTop {' "$1/A" | grep -qxF '	return vcs.count >= 2 && MSBSSPageIn(vcs.lastObject, MSBASPickerClass()) && vcs[vcs.count - 2] == MSBSSEntryOf(self, nav);' \
    && f1 '- (void)msbOpenPickedNextTurn {' "$1/A" > "$1/nt" && [ "$(grep -c 'popToViewController:MSBSSEntryOf(self, nav) animated:YES' "$1/nt")" = 1 ] \
    && ! grep -q 'msbOpenAppPage\|showController\|pushViewController\|popViewController\|setViewControllers' "$1/nt" \
    && order '	id<UIViewControllerTransitionCoordinator> moving = nav.transitionCoordinator ?: picker.transitionCoordinator;' '		[nav popToViewController:MSBSSEntryOf(self, nav) animated:YES];' "$1/nt" \
    && order '		[self msbAfter:moving then:^(MSBAppSizesController *me) { [me msbOpenPickedNextTurn]; }];' '		[nav popToViewController:MSBSSEntryOf(self, nav) animated:YES];' "$1/nt" \
    && f1 '- (void)msbOpenPickedWhenSettled {' "$1/A" > "$1/ws" \
    && order '	id<UIViewControllerTransitionCoordinator> moving = nav.transitionCoordinator;' '		[self msbAfter:moving then:^(MSBAppSizesController *me) { [me msbOpenPickedWhenSettled]; }];' "$1/ws" \
    && order '		[self msbAfter:moving then:^(MSBAppSizesController *me) { [me msbOpenPickedWhenSettled]; }];' '	if (!nav || !self.view.window || nav.topViewController != MSBSSEntryOf(self, nav)) {' "$1/ws" \
    && order '	if (!nav || !self.view.window || nav.topViewController != MSBSSEntryOf(self, nav)) {' '	[self msbOpenAppPage:b];' "$1/ws" \
    && order '		_picked = nil; _closedPicker = nil;' '	[self msbOpenAppPage:b];' "$1/ws" \
    && order '	MSBASLog([NSString stringWithFormat:@"picker parent %@", parent ? NSStringFromClass([parent class]) : @"none"]);' '	[self msbOpenAppPage:b];' "$1/ws" \
    && f1 '- (void)msbAfter:(id<UIViewControllerTransitionCoordinator>)moving then:(void (^)(MSBAppSizesController *me))step {' "$1/A" > "$1/af" \
    && grep -qF 'completion:^(id<UIViewControllerTransitionCoordinatorContext> ctx) { dispatch_async(dispatch_get_main_queue(), again); }]) {' "$1/af" \
    && grep -qF '		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), again);' "$1/af" \
    && f1 '- (void)viewDidAppear:(BOOL)animated {' "$1/A" > "$1/da2" && [ "$(grep -c 'msbOpenPickedWhenSettled\|msbOpenAppPage\|msbOpenPickedNextTurn' "$1/da2")" = 1 ] \
    && grep -qxF '	dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf msbOpenPickedWhenSettled]; });' "$1/da2" \
    && ! grep -q 'setViewControllers\|popViewControllerAnimated:NO' "$1/A" \
    && [ "$(f1 '- (void)msbRemoveApp:(PSSpecifier *)spec {' "$1/A" | cksum)" = '2270374027 453' ] \
    && f1 '- (void)msbOpenAppPage:(NSString *)bundle {' "$1/A" | grep -qF 'MSBAppSizeController *open = MSBSSPageIn(self.navigationController.topViewController, [MSBAppSizeController class]);' \
    && [ "$(grep -c 'MSBSSEntryOf(\|MSBSSPageIn(' "$1/A")" = 6 ] \
    && ! grep -qE 'topViewController [!=]= self|topViewController isKindOfClass|lastObject isKindOfClass|isKindOfClass:picker|vcs\[vcs\.count - 2\] == self|\[vc isKindOfClass:\[MSBAppSizesController|\[top isKindOfClass:' "$1/A"
}
run_c4() {   # run_c4 <dir> [quiet]: every C4 check on that directory's files; exit 0 when all pass
  local bad=0 e name fn
  for e in "${c4sites[@]}"; do
    name="${e%|*}"; fn="${e##*|}"
    if ( $fn "$1" ) 2>/dev/null; then [ -n "$2" ] || echo "PASS  $name"; else [ -n "$2" ] && return 1; echo "FAIL  $name"; bad=1; fi
  done
  return $bad
}
c4set "$W/c4"; run_c4 "$W/c4" || { fails=1; grep '^FAIL' "$W/c4/stack.out" 2>/dev/null | head -12; }
echo "-- C4's made-to-fail copies (the Settings pages; each must fail the checks):"
c4mtf() {   # c4mtf <name> <file: PL P A AH MK R DR SS> <perl substitution>
  local d="$W/c4mtf$((++cn))"; c4set "$d"; cp "$d/$2" "$d/$2.orig"; perl -0pi -e "$3" "$d/$2"
  if cmp -s "$d/$2" "$d/$2.orig"; then echo "FAIL  made-to-fail copy $1: the change did not apply"; fails=1; return; fi
  if run_c4 "$d" quiet; then echo "FAIL  made-to-fail copy $1 PASSED (it must fail)"; fails=1; else echo "PASS  made-to-fail copy $1 fails, as it must"; fi
}
cn=0
c4mtf "Settings writing from the picker (the selection stores a size)" A 's/(\t_picked = \[value copy\];\n)/$1\tMSBASWrite(value, MSBDAppSizeMedium);\n/'
c4mtf "the setter pushing the app's page in the same turn" A 's/\tdispatch_async\(dispatch_get_main_queue\(\), \^\{ \[weakSelf msbOpenPickedNextTurn\]; \}\);\n/\t[self msbOpenAppPage:value];\n/'
c4mtf "the app's page pushed from viewWillAppear" A 's/(\t_specifiers = nil; \[self reloadSpecifiers\];   \/\/ \(back from an app.s page or the picker[^\n]*\n)/$1\tif (_picked) [self msbOpenAppPage:_picked];\n/'
c4mtf "the setter followed twice for one opening (no guard: two pushes)" A 's/\tif \(!_pickOpen\) \{[^\n]*\n//'
c4mtf "the pick not cleared before the push (the list opens the page again)" A 's/\t_picked = nil;   \/\/ \(cleared before the push: one push only\)\n//'
c4mtf "an AltList class subclassed statically" A 's/(\@interface MSBAppSizesController : PSListController\n\@end\n)/$1\@interface MSBAppSizePicker : ATLApplicationListSelectionController\n\@end\n/'
c4mtf "the subclass made with objc_allocateClassPair" A 's/(\treturn NSClassFromString\(\@"ATLApplicationListSelectionController"\);\n)/\tClass sub = objc_allocateClassPair(NSClassFromString(\@"ATLApplicationListSelectionController"), "MSBAppSizePicker", 0); if (sub) objc_registerClassPair(sub);\n$1/'
c4mtf "AltList's picker named in a category" A 's/(\@interface MSBAppSizeController : PSListController\n)/\@interface ATLApplicationListSelectionController (MSBAppSizes)\n\@end\n$1/'
c4mtf "the Makefile linking AltList" MK 's/(MacStatusBarPrefs_PRIVATE_FRAMEWORKS = Preferences\n)/$1MacStatusBarPrefs_EXTRA_FRAMEWORKS = AltList\n/'
c4mtf "Add App shown without AltList's class" A 's/\t\tif \(picker\) \{\n/\t\t{\n/'
c4mtf "200 apps listed: Add App not greyed" A 's/\t\t\t\[a setProperty:\@\(canAdd\) forKey:\@"enabled"\];\n//'
c4mtf "200 apps listed: a tap on a size still adds the app" A 's/\tif \(now == MSBDAppSizeNone && !MSBDAppSizesCanAdd\(\(CFIndex\)listed.count\)\) return;[^\n]*\n//'
c4mtf "an empty dictionary written with the last app (the key kept)" A 's/CFPreferencesSetValue\(CFSTR\(kMSBDAppWindowSizesKey\), next, /CFPreferencesSetValue(CFSTR(kMSBDAppWindowSizesKey), next ?: (__bridge CFDictionaryRef)\@{}, /'
c4mtf "SpringBoard not told (no prefsChanged after a write)" A 's/(static void MSBASWrite\(NSString \*bundle, int choice\) \{\n(?:[^\n]*\n)*?)\tnotify_post\("com.besiktasliseba.macstatusbar\/prefsChanged"\);\n/$1/'
c4mtf "the page writing another key too" A 's/(\tMSBASWrite\(b, c\);\n)/$1\tCFPreferencesSetValue(CFSTR("windowSize"), CFSTR("large"), kMSBASDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);\n/'
c4mtf "Remove App not back to the list (one page back)" A 's/\tif \(list\) \[nav popToViewController:list animated:YES\];\n\telse \[nav popViewControllerAnimated:YES\];/\t[nav popViewControllerAnimated:YES];/'
c4mtf "Remove App shown before the app has a size" A 's/\t\tif \(MSBDAppSizeValid\(now\)\) \{   \/\/ \(only once the app has a size\)/\t\tif (1) {/'
c4mtf "a page opened from Add App with Medium checked (something shown as stored)" A 's/int now = b \? MSBASChoiceIn\(MSBASListed\(\), b\) : MSBDAppSizeNone;/int now = b \&\& MSBASChoiceIn(MSBASListed(), b) != MSBDAppSizeNone ? MSBASChoiceIn(MSBASListed(), b) : MSBDAppSizeMedium;/'
c4mtf "the uninstalled row's words changed (not the Go menu's)" A 's/self.detailTextLabel.text = \@"Not Installed";/self.detailTextLabel.text = \@"Missing";/'
c4mtf "\"Not Installed\" on the right (not under the name)" A 's/return \[super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:rid specifier:specifier\];/return [super initWithStyle:style reuseIdentifier:rid specifier:specifier];/'
c4mtf "the list's footer with no apps listed (the finding: \"These apps...\" over nothing)" A 's/\t\tif \(listed.count\) \{[^\n]*\n\t\t\tPSSpecifier \*g = \[PSSpecifier groupSpecifierWithName:\@"Apps"\];\n\t\t\t(\[g setProperty:[^\n]*\n)\t\t\t\[s addObject:g\];\n\t\t\}\n/\t\tPSSpecifier *g = [PSSpecifier groupSpecifierWithName:listed.count ? \@"Apps" : nil];\n\t\t$1\t\t[s addObject:g];\n/'
c4mtf "the list's footer set outside the apps check" A 's/(\t\t\t\[s addObject:g\];\n\t\t\}\n)/$1\t\t[g setProperty:\@"These apps open at their own size instead of Window Size. You can still resize them." forKey:\@"footerText"];\n/'
c4mtf "an empty list with no line under Add App" A 's/\t\t\tif \(!listed.count\) \[ag setProperty:[^\n]*\n//'
c4mtf "Add App's empty-list line shown with apps listed" A 's/if \(!listed.count\) \[ag setProperty:/[ag setProperty:/'
c4mtf "an em dash in Add App's empty-list line" A 's/Apps you add here open at their own size instead of Window Size\./Apps you add here open at their own size \xE2\x80\x94 not Window Size\'"'"'s./'
c4mtf "the list's footer one sentence" A 's/These apps open at their own size instead of Window Size. You can still resize them./These apps open at their own size instead of Window Size./'
c4mtf "the row not right under Window Size" PL 's/(\t\t<dict>\n\t\t\t<key>cell<\/key>\n\t\t\t<string>PSLinkListCell<\/string>\n\t\t\t<key>detail<\/key>\n\t\t\t<string>MSBAppSizesController<\/string>)/\t\t<dict>\n\t\t\t<key>cell<\/key>\n\t\t\t<string>PSSwitchCell<\/string>\n\t\t<\/dict>\n$1/'
c4mtf "the row a stored value of its own (a key)" PL 's/(\t\t\t<string>APP_WINDOW_SIZES<\/string>\n)/$1\t\t\t<key>key<\/key>\n\t\t\t<string>appWindowSizes<\/string>\n/'
c4mtf "the row's count not reloaded when the page appears" P 's/\tif \(sizes\) \[self reloadSpecifier:sizes animated:NO\];\n//'
c4mtf "the row left out with Stage Manager as the engine (the page's rule by its own key)" P 's/BOOL itsToo = MSBDStageManagerKeepsRow\(MSBDRowRuleKey\(\[sp propertyForKey:\@"key"\], sp.identifier\)\);/BOOL itsToo = MSBDStageManagerKeepsRow([sp propertyForKey:\@"key"]);/'
c4mtf "the search leaving the row out with Stage Manager (the rule by its own key)" R 's/    key = MSBDRowRuleKey\(key, ident\);[^\n]*\n//'
c4mtf "the Window Behavior footer's code words without the sentence (the plist's and the page's differ)" P 's/ Apps with their own size open at that size.",/",/'
c4mtf "Window Size's page without the sentence" PL 's/ Apps in App Window Sizes open at their own size.<\/string>/<\/string>/'
c4mtf "the TV's Window Size footer without the sentence" DR 's/ Apps in App Window Sizes open at their own size."/"/'
c4mtf "an em dash in the list's footer" A 's/instead of Window Size. You can/instead of Window Size \xE2\x80\x94 you can/'
echo "-- F1's made-to-fail copies (Add App on 18's stack, the A12Z's S1 on 18.5; each must fail the checks):"
c4mtf "18: the picker read as the stack's last entry itself" A 's/MSBSSPageIn\(vcs.lastObject, MSBASPickerClass\(\)\)/[vcs.lastObject isKindOfClass:MSBASPickerClass()]/'
c4mtf "18: the list read as its own entry under the picker" A 's/vcs\[vcs.count - 2\] == MSBSSEntryOf\(self, nav\)/vcs[vcs.count - 2] == (id)self/'
c4mtf "18: the list in front read as the stack's top itself" A 's/nav.topViewController != MSBSSEntryOf\(self, nav\)/nav.topViewController != (id)self/'
c4mtf "18: the app's page in front read as the stack's top itself (pushed again)" A 's/MSBSSPageIn\(self.navigationController.topViewController, \[MSBAppSizeController class\]\)/([self.navigationController.topViewController isKindOfClass:[MSBAppSizeController class]] ? (id)self.navigationController.topViewController : nil)/'
c4mtf "18: Remove App's list read as an entry itself (one page back)" A 's/if \(MSBSSPageIn\(vc, \[MSBAppSizesController class\]\)\) \{ list = vc; break; \}/if ([vc isKindOfClass:[MSBAppSizesController class]]) { list = vc; break; }/'
c4mtf "the entry rule stopping at the page (no hosting controller read)" SS 's/\twhile \(e.parentViewController && e.parentViewController != nav\) e = e.parentViewController;\n//'
c4mtf "the entry rule one level up only (a page two deep has no entry)" SS 's/\twhile \(e.parentViewController && e.parentViewController != nav\)/\tif (e.parentViewController \&\& e.parentViewController != nav)/'
c4mtf "the page rule not looking inside the entry (18's hosted page not found)" SS 's/\tfor \(UIViewController \*child in entry.childViewControllers\) \{\n\t\tid page = MSBSSPageIn\(child, cls\);\n\t\tif \(page\) return page;\n\t\}\n//'
c4mtf "the page rule one level in only (a page two deep not found)" SS 's/\t\tid page = MSBSSPageIn\(child, cls\);/\t\tid page = [child isKindOfClass:cls] ? child : nil;/'
c4mtf "the page rule never taking a controller itself (no page found, 15 to 17 included)" SS 's/\tif \(\[entry isKindOfClass:cls\]\) return entry;\n//'
echo "-- S1-F1's made-to-fail copies (Add App on SwiftUI's stack, row E1 of p03 on 18.5, and the skeptic's fixes; each must fail the checks):"
c4mtf "F1's way: the picker popped with no slide and the page pushed in the same turn (E1)" A 's/\t\t\[nav popToViewController:MSBSSEntryOf\(self, nav\) animated:YES\];\n/\t\tNSString *b = _picked; _picked = nil;\n\t\t[nav popViewControllerAnimated:NO];\n\t\t[self msbOpenAppPage:b];\n/'
c4mtf "B2: the picker closed with no slide, the page pushed in the list's viewDidAppear" A 's/(\[nav popToViewController:MSBSSEntryOf\(self, nav\)) animated:YES\]/$1 animated:NO]/; s/\t__weak MSBAppSizesController \*weakSelf = self;\n\tdispatch_async\(dispatch_get_main_queue\(\), \^\{ \[weakSelf msbOpenPickedWhenSettled\]; \}\);\n/\t[self msbOpenPickedWhenSettled];\n/'
c4mtf "a push in viewDidAppear with no settled guard" A 's/\t__weak MSBAppSizesController \*weakSelf = self;\n\tdispatch_async\(dispatch_get_main_queue\(\), \^\{ \[weakSelf msbOpenPickedWhenSettled\]; \}\);\n/\tNSString *b = _picked; _picked = nil; [self msbOpenAppPage:b];\n/'
c4mtf "D: setViewControllers in place of the close" A 's/\t\t\[nav popToViewController:MSBSSEntryOf\(self, nav\) animated:YES\];\n/\t\t[nav setViewControllers:[nav.viewControllers subarrayWithRange:NSMakeRange(0, nav.viewControllers.count - 1)] animated:YES];\n/'
c4mtf "E: the app's page pushed over the picker (Back lands on the picker)" A 's/\t\t\[nav popToViewController:MSBSSEntryOf\(self, nav\) animated:YES\];\n/\t\t[self msbOpenAppPage:_picked]; _picked = nil;\n/'
c4mtf "the picker closed with no slide (popTo animated:NO)" A 's/\[nav popToViewController:MSBSSEntryOf\(self, nav\) animated:YES\];/[nav popToViewController:MSBSSEntryOf(self, nav) animated:NO];/'
c4mtf "fix 3: a transition at the pick's next turn not waited for (the page waits for Back)" A 's/\t\t\[self msbAfter:moving then:\^\(MSBAppSizesController \*me\) \{ \[me msbOpenPickedNextTurn\]; \}\];\n//'
c4mtf "fix 3: the settled opener not waiting for a running transition" A 's/\t\t\[self msbAfter:moving then:\^\(MSBAppSizesController \*me\) \{ \[me msbOpenPickedWhenSettled\]; \}\];\n//'
c4mtf "fix 3: only the stack's own transition looked at (the picker's search closing not waited for)" A 's/ \?: picker.transitionCoordinator;/;/'
c4mtf "fix 3: a coordinator that takes no completion never looked at again" A 's/\t\tdispatch_after\(dispatch_time\(DISPATCH_TIME_NOW, \(int64_t\)\(0.1 \* NSEC_PER_SEC\)\), dispatch_get_main_queue\(\), again\);\n//'
c4mtf "fix 3: a pick kept once the list is not in front (a later Back opens its page)" A 's/\t\t_picked = nil; _closedPicker = nil;\n//'
c4mtf "fix 4: a tap on another row keeps a waiting pick (only Add App clears it)" A 's/\tif \(_picked\) MSBASLog[^\n]*\n\t_picked = nil;\n\t_pickOpen = \[\[MSBASSpecAt\(self, ip\) identifier\] isEqualToString:\@"APP_SIZES_ADD"\];\n/\tif ([[MSBASSpecAt(self, ip) identifier] isEqualToString:\@"APP_SIZES_ADD"]) { _pickOpen = YES; _picked = nil; }\n/'
c4mtf "fix 4: the settled opener with no navigation stack required" A 's/if \(!nav \|\| !self.view.window \|\| /if (!self.view.window || /'
c4mtf "fix 5: the settled opener without its guard (two callers)" A 's/\tif \(!_picked\) return;   \/\/ \(two callers: one push\)\n//'
c4mtf "fix 6: no log of the closed picker's parent at the push" A 's/\tMSBASLog\(\[NSString stringWithFormat:\@"picker parent %\@"[^\n]*\n/\t(void)parent;\n/'
echo "-- the files before F1's fix (5556a615, or its -reg twin 43fdb694: the same tree) fail the stack check as on the A12Z in s01 (18: the picker going, the picker left up, the page after Back; 15-17: the first five scenarios seen as before):"
for c in 5556a615 43fdb694; do git -C .. cat-file -e $c:statusbar/macstatusbarprefs/MSBAppSizesController.m 2>/dev/null && break; c=; done
if [ -n "$c" ]; then
  mkdir -p "$W/c4f1/tree"; git -C .. archive $c statusbar/macstatusbarprefs common | tar -x -C "$W/c4f1/tree"; c4set "$W/c4f1/set" "$W/c4f1/tree"
  o="$W/c4f1/set/stack.out"
  if ( c4_stack "$W/c4f1/set" ) 2>/dev/null; then echo "FAIL  the files before F1's fix PASS the stack check"; fails=1
  elif grep -qE "^FAIL: 15-17 \(plain\): seen: (the app's page over the list|Back from the page lands on the list|the page opens once the list is back|Remove App goes back to the list)" "$o" || ! grep -qxF "FAIL: 18 (hosted): the pick logs the picker in front (got: picker: com.apple.calculator picked, the picker going)" "$o" \
       || ! grep -qxF "FAIL: 18 (hosted): seen: the app's page over the list, no empty host, the record the stack (got: general, windows, list, picker | empty hosts 0 | record = stack)" "$o" \
       || ! grep -qxF "FAIL: 18 (hosted): seen: Back from the page lands on the list, nothing opened again (got: general, windows, list, page(com.apple.calculator) | empty hosts 0 | record = stack | pop animated picker; push page(com.apple.calculator))" "$o"
  then echo "FAIL  the files before F1's fix fail the stack check, but not as on the A12Z (18: the pick logged as the picker going, the picker left up, the page only after Back)"; fails=1
  else echo "PASS  the files before F1's fix fail it as on the A12Z: on 18 the picker going, the picker left up, the page after Back ($(grep -c '^FAIL:' "$o") checks)"; fi
else echo "SKIP  5556a615 (43fdb694) not in this repository"; fi
echo "-- F1 as committed (da581859, or its -reg twin cfe5a4c6: the same tree) fails the stack check as row E1 of p03 on 18.5, on SwiftUI's record only, and passes the first five scenarios as seen on the other three shapes (why F1's 94 checks missed E1):"
for c in da581859 cfe5a4c6; do git -C .. cat-file -e $c:statusbar/macstatusbarprefs/MSBAppSizesController.m 2>/dev/null && break; c=; done
if [ -n "$c" ]; then
  mkdir -p "$W/c4e1/tree"; git -C .. archive $c statusbar/macstatusbarprefs common | tar -x -C "$W/c4e1/tree"; c4set "$W/c4e1/set" "$W/c4e1/tree"
  o="$W/c4e1/set/stack.out"
  if ( c4_stack "$W/c4e1/set" ) 2>/dev/null; then echo "FAIL  F1 as committed PASSES the stack check"; fails=1
  elif grep -qE "^FAIL: (15-17 \(plain\)|18 \(hosted\)|18 \(hosted, two deep\)): seen: (the app's page over the list|Back from the page lands on the list|the page opens once the list is back|Remove App goes back to the list)" "$o" \
       || ! grep -qxF "FAIL: 18 (SwiftUI's record): seen: the app's page over the list, no empty host, the record the stack (got: general, windows, list, empty host, empty host | empty hosts 2 | record 3 entries)" "$o" \
       || ! grep -qxF "FAIL: 18 (SwiftUI's record): seen: Back from the page lands on the list, nothing opened again (got: general, windows, list, empty host | empty hosts 1 | record 3 entries | pop animated empty host)" "$o" \
       || ! grep -qxF "FAIL: 15-17 (plain): no push in the same turn as a pop (got: pop picker then push page(com.apple.calculator))" "$o"
  then echo "FAIL  F1 as committed fails the stack check, but not as row E1 (SwiftUI's record only: two empty hosts, Back onto one)"; fails=1
  else echo "PASS  F1 as committed fails it as row E1 of p03, on SwiftUI's record only: two empty hosts, Back onto one; a push in the same turn as a pop ($(grep -c '^FAIL:' "$o") checks)"; fi
else echo "SKIP  da581859 (cfe5a4c6) not in this repository"; fi
echo "-- F2's made-to-fail copies of WindowSize.h (the cascade over Fit's tiles, row A6 / A12b; each must fail the C test):"
f2mtf() {   # f2mtf <name> <perl substitution on WindowSize.h>
  local d="$W/f2mtf$((++fn2))"; mkdir -p "$d"; cp ../common/WindowSize.h "$d/WindowSize.h"; perl -0pi -e "$2" "$d/WindowSize.h"
  cmp -s ../common/WindowSize.h "$d/WindowSize.h" && { echo "FAIL  made-to-fail copy $1: the change did not apply"; fails=1; return; }
  rule $H "$d/tree" "$d/WindowSize.h" > "$d/out" 2>&1 && rc=0 || rc=$?
  if [ $rc = 3 ]; then echo "FAIL  made-to-fail copy $1 does not build (it must build and fail)"; head -5 "$d/tree/build"; fails=1
  elif [ $rc = 0 ]; then echo "FAIL  made-to-fail copy $1 PASSED (it must fail)"; fails=1
  elif ! grep -q "^FAIL: .*two iPhone windows over Fit's two tiles" "$d/out"; then echo "FAIL  made-to-fail copy $1 fails, but not on row A6"; fails=1
  else echo "PASS  made-to-fail copy $1 fails, as it must ($(grep -c "^FAIL: .*two iPhone windows over Fit's two tiles" "$d/out") of the A6 checks)"; fi
}
fn2=0
f2mtf "each step down and right, then up and left (the order until 1.8.8)" 's/for \(int sign = 1; sign >= -1; sign -= 2\) for \(int k = 1; k <= 8; k\+\+\) \{/for (int k = 1; k <= 8; k++) for (int sign = 1; sign >= -1; sign -= 2) {/'
f2mtf "every step up and left first" 's/for \(int sign = 1; sign >= -1; sign -= 2\) for/for (int sign = -1; sign <= 1; sign += 2) for/'
f2mtf "one step down and right only, then up and left" 's/for \(int sign = 1; sign >= -1; sign -= 2\) for \(int k = 1; k <= 8; k\+\+\) \{/for (int sign = 1; sign >= -1; sign -= 2) for (int k = 1; k <= (sign > 0 ? 1 : 8); k++) {/'
echo "-- the WindowSize.h before F2's fix (f7f634f7, or its -reg twin 9dfd76d9: the same tree) fails row A6 on every desktop, as the s01 passes saw it:"
for c in f7f634f7 9dfd76d9; do git -C .. show $c:common/WindowSize.h > "$W/ws-f2base" 2>/dev/null && break; rm -f "$W/ws-f2base"; done
if [ -s "$W/ws-f2base" ]; then
  rule $H "$W/f2base" "$W/ws-f2base" > "$W/f2base.out" 2>&1 && rc=0 || rc=$?
  na=$(grep -c "^FAIL: .*two iPhone windows over Fit's two tiles" "$W/f2base.out")
  if [ $rc = 0 ] || [ $rc = 3 ]; then echo "FAIL  the WindowSize.h before F2 passes or does not build (rc $rc)"; fails=1
  elif [ "$na" != 44 ] || ! grep -qxF "FAIL: the iPad 2's s01 row A6: {402, 47.07} then {452, 47.07}, not {302, 20} ({402.00, 47.07, 320.00, 650.00}, {302.00, 20.00, 320.00, 650.00})" "$W/f2base.out"; then
    echo "FAIL  the WindowSize.h before F2 fails, but not on row A6 everywhere ($na of 44) or not as the iPad 2 showed it"; fails=1
  else echo "PASS  the WindowSize.h before F2 fails row A6 on all 44 desktops and minimums, the iPad 2's as on the device ({302, 20}; $(grep -c '^FAIL:' "$W/f2base.out") checks)"; fi
else echo "SKIP  f7f634f7 (9dfd76d9) not in this repository"; fi
echo "-- the files before C4 (9ef0e161) fail C4's checks:"
if git -C .. cat-file -e 9ef0e161:statusbar/StatusBar.x 2>/dev/null; then
  mkdir -p "$W/c4base/tree"; git -C .. archive 9ef0e161 statusbar/macstatusbarprefs common | tar -x -C "$W/c4base/tree"; c4set "$W/c4base/set" "$W/c4base/tree"
  if run_c4 "$W/c4base/set" quiet; then echo "FAIL  the files before C4 PASS C4's checks"; fails=1; else echo "PASS  the files before C4 fail them, as they must"; fi
else echo "SKIP  9ef0e161 not in this repository"; fi
# ---- F3 (the A12Z's G1 and the iPad 2's A12b in s01) ----------------------------------------------------------------------------------------
# (1) A stored appWindowSizes that is not a dictionary (G1's number) was read as no app with nothing to log: the read rule counted bad entries and
# entries past 200 for the caller's log, and returned the empty table for a value of another type without a word (AppWindowSize.h
# MSBDAppSizesRead). It now reports the type, DMAppSizesLoad logs it once. (2) The smfit trigger listed the green light's windows under "full
# screen" after they became windows: DMSMFitTick saw a window coming back from full screen only among the windows that take part in the tiles, so
# one back as a free window (opened again at its app's own size: Fit leaves it out) or as a regular window over the tiles stayed in gSMFitWentFull
# until it closed. SMFitPlan.h DMSMFitBackUntiled names them, the tick drops them at its first look. Each check takes <StatusBar.x> <root>: root
# holds common/ and statusbar/ (the headers of the same tree: this one, a made-to-fail copy, or the files before the fix).
cat > "$W/f3load-main.m" <<'EOF'
#import <Foundation/Foundation.h>
#include "AppWindowSize.h"
// (stand-ins for what DMAppSizesLoad reads: the stored value the test sets, the crash guard's piece on, the log and the forget recorded)
#define MSB_DOMAIN CFSTR("com.besiktasliseba.macstatusbar.test")
static CFPropertyListRef gStored;
#define CFPreferencesCopyValue(key, domain, user, host) (gStored ? CFRetain(gStored) : NULL)
static BOOL DMAppSizesSkipped(void) { return NO; }
static NSDictionary *gAppSizes = nil;
static BOOL gAppSizesRead = NO;
static NSMutableArray<NSString *> *gLog, *gForgot;
static void DMLog(NSString *s) { [gLog addObject:s]; }
static void DMAppSizeForgetPlace(NSString *b) { [gForgot addObject:b]; }
#include "f3load.inc"
static int fails = 0, n = 0;
static void Expect(BOOL ok, NSString *what, NSArray *log) { n++; if (!ok) { fails++; printf("FAIL: %s (log: %s)\n", what.UTF8String, [log componentsJoinedByString:@" | "].UTF8String); } }
static NSArray<NSString *> *Read(id stored) { gStored = (__bridge CFPropertyListRef)stored; gLog = [NSMutableArray array]; DMAppSizesLoad(); gStored = NULL; return gLog; }
static BOOL Says(NSArray<NSString *> *log, NSString *part) { for (NSString *l in log) if ([l containsString:part]) return YES; return NO; }
int main(void) { @autoreleasepool {
    gForgot = [NSMutableArray array];
    // G1 as on the A12Z (debug trigger: a number as the whole value), the first read since the start
    NSArray *log = Read(@5);
    Expect(Says(log, @"is a CFNumber, not a dictionary") && log.count == 1 && gAppSizes.count == 0 && gAppSizesRead, @"a number at the start: no app, logged once, naming its type", log);
    log = Read(@5);
    Expect(log.count == 0, @"the same number read again (every prefsChanged): nothing logged", log);
    log = Read(@[ @{ @"com.apple.mobilenotes": @"iphone" } ]);
    Expect(Says(log, @"is a CFArray, not a dictionary") && log.count == 1, @"an array: logged, its type", log);
    log = Read(@"iphone");
    Expect(Says(log, @"is a CFString, not a dictionary") && log.count == 1, @"a text as the whole value: logged, its type", log);
    log = Read(@{ @"com.apple.mobilenotes": @"iphone" });
    Expect(!Says(log, @"not a dictionary") && Says(log, @"1 app with a size of their own") && [gForgot isEqualToArray:@[ @"com.apple.mobilenotes" ]], @"a dictionary: read, no word about the type", log);
    [gForgot removeAllObjects];
    log = Read(@"large");
    Expect(Says(log, @"is a CFString, not a dictionary") && Says(log, @"0 apps with a size of their own") && [gForgot isEqualToArray:@[ @"com.apple.mobilenotes" ]],
           @"a text again after a dictionary: logged again (the same type as before it), the app forgotten as for a removed entry", log);
    log = Read(nil);
    Expect(log.count == 0, @"absent (the key removed): nothing logged", log);
    log = Read(@{ @"x.bad": @"huge", @"com.apple.mobiletimer": @"small" });
    Expect(Says(log, @"1 entry read as none") && !Says(log, @"not a dictionary"), @"a dictionary with a bad entry: the entry's line as before, none about the type", log);
    log = Read(@YES);
    Expect(Says(log, @"is a CFBoolean, not a dictionary"), @"a boolean: logged, its type", log);
    printf("f3load: %d cases, %d failed\n", n, fails);
    return fails ? 1 : 0;
} }
EOF
cat > "$W/f3back-main.m" <<'EOF'
#import <Foundation/Foundation.h>
#include "SMFitPlan.h"
// (stand-ins: Fit's memory as DMSMFitTick keeps it, the front stage's items -- a key each, full screen or not --, the log)
#define DM_FEATURE_MARK(name) do { } while (0)
static NSMutableDictionary<NSString *, NSString *> *gSMFitSlots;
static NSMutableSet<NSString *> *gSMFreeWindows, *gSMFitLoose, *gSMFitWentFull;
static NSDictionary<NSString *, NSString *> *gSMFitSlotsBeforeFull;
static NSMutableArray<NSString *> *gLog;
static void DMLog(NSString *s) { [gLog addObject:s]; }
static NSDictionary *gFront;
static id DMSMFrontStage(void) { return nil; }
static NSDictionary *DMSMStageItemsMap(id stage) { (void)stage; return gFront; }
static BOOL DMSMAttrsFullScreen(id attrs) { return [attrs boolValue]; }
static NSString *DMSMItemKey(id item) { return item; }
static NSArray<NSString *> *DMSMFitKeptAway(NSArray<NSString *> *keys, NSDictionary<NSString *, NSString *> *slots) { return @[]; }   // (1.8.8 H2: the arrangement's minimized windows -- none in these stories)
// Fit's look with an app full screen in front (the tick's own block, as written): it is noted with the tiles it left.
static void FullLook(NSString *key) {
    NSMutableDictionary *m = [NSMutableDictionary dictionaryWithObject:@YES forKey:key]; gFront = m;
#include "f3full.inc"
}
// Fit's look at the desktop with its set changed, past the tick's waits: keysNow, the desktop's windows on screen and not full screen, newest
// first; shown, every window on screen (DMSMWindowKeys). The tick's statements as written: the windows taking part, the regular ones, then back
// from full screen. What the tick does in between (the respring's adopt, an unchanged set, minimized tiles, the layout) is left out.
static void Look(NSArray<NSString *> *keysNow, NSArray<NSString *> *shown) {
    NSSet *onScreen = [NSSet setWithArray:shown ?: keysNow];
    NSMutableSet *fullAway = [NSMutableSet set];   // (the windows full screen out of sight, StatusBar.x DMSMFitFullAway, 1.8.8 G1: the front stage's full-screen one, not on screen)
    for (NSString *k in gFront) if ([gFront[k] boolValue] && ![onScreen containsObject:k]) [fullAway addObject:k];
    (void)fullAway;
    NSArray<NSString *> *keptAway = @[]; (void)keptAway;   // (1.8.8 H2: declared ahead of the windows taking part, as in the tick)
#include "f3bundles.inc"
    {
#include "f3part.inc"
    }
    if (bundles.count < 2) return;   // (one window: the tick's one-window rule returns before "back from full screen")
#include "f3back.inc"
}
static int fails = 0, n = 0;
static void Expect(BOOL ok, NSString *what) { n++; if (!ok) { fails++; printf("FAIL: %s (full screen: %s; tiles: %s; log: %s)\n", what.UTF8String,
    [[gSMFitWentFull.allObjects sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@", "].UTF8String, gSMFitSlots.description.UTF8String, [gLog componentsJoinedByString:@" | "].UTF8String); } }
static void Reset(NSDictionary *slots) {
    gSMFitSlots = [slots mutableCopy]; gSMFreeWindows = [NSMutableSet set]; gSMFitLoose = [NSMutableSet set]; gSMFitWentFull = nil; gSMFitSlotsBeforeFull = nil; gLog = [NSMutableArray array];
}
static BOOL Says(NSString *part) { for (NSString *l in gLog) if ([l containsString:part]) return YES; return NO; }
#define K(app) @"com.apple." app "|sceneID:com.apple." app "-default"
int main(void) { @autoreleasepool {
    NSString *as = K("AppStore"), *set = K("Preferences"), *saf = K("mobilesafari"), *rem = K("reminders"), *clk = K("mobiletimer"), *notes = K("mobilenotes");
    NSString *notes2 = @"com.apple.mobilenotes|sceneID:com.apple.mobilenotes-3E2F1A90", *maps = K("Maps"), *tips = K("tips");
    // 1. A12b, iPad 2: three tiled; Reminders, then Clock, opened full screen (Open Apps as Windows off), each made a window by our green at its own
    //    size (iPhone): free (the join's "Fit to Window leaves it out")
    Reset(@{ as: @"left", set: @"topright", saf: @"bottomright" });
    FullLook(rem);
    Expect([gSMFitWentFull isEqualToSet:[NSSet setWithObject:rem]], @"A12b: Reminders full screen is noted");
    [gSMFreeWindows addObject:rem]; Look(@[ rem, as, set, saf ], nil);
    Expect(![gSMFitWentFull containsObject:rem], @"A12b: Reminders back as a free window is no longer full screen's");
    FullLook(clk); [gSMFreeWindows addObject:clk]; Look(@[ clk, rem, as, set, saf ], nil);
    Expect(gSMFitWentFull.count == 0, @"A12b: Clock too: the smfit trigger lists no window as full screen");
    Expect([gSMFitSlots isEqualToDictionary:(@{ as: @"left", set: @"topright", saf: @"bottomright" })] && !Says(@"back from full screen -- "), @"A12b: the tiles untouched, neither taken for a tiled window back");
    Expect(Says(@"Fit to Window: com.apple.reminders/default back from full screen as a free window -- no tile to take"), @"A12b: the log says Reminders is back, free");
    // 2. A12b, A12Z: two tiled, the same two iPhone windows
    Reset(@{ set: @"left", saf: @"right" });
    FullLook(rem); [gSMFreeWindows addObject:rem]; Look(@[ rem, set, saf ], nil);
    FullLook(clk); [gSMFreeWindows addObject:clk]; Look(@[ clk, rem, set, saf ], nil);
    Expect(gSMFitWentFull.count == 0 && [gSMFitSlots isEqualToDictionary:(@{ set: @"left", saf: @"right" })], @"A12b on two tiles: none listed as full screen, the tiles untouched");
    // 3. A7 b': a tiled window to full screen and back takes its tile again (the tick's own way back, unchanged)
    Reset(@{ notes: @"left", saf: @"right" });
    FullLook(notes);
    Expect([gSMFitWentFull containsObject:notes] && [gSMFitSlotsBeforeFull[notes] isEqualToString:@"left"], @"A7 b': Notes full screen noted with the tiles it left");
    Look(@[ saf ], nil);
    Expect([gSMFitWentFull containsObject:notes], @"A7 b': on the desktop while Notes is still full screen: Notes stays full screen's");
    Look(@[ notes, saf ], nil);
    Expect(!gSMFitWentFull.count && Says(@"back from full screen -- its tile again") && [gSMFitSlots isEqualToDictionary:(@{ notes: @"left", saf: @"right" })], @"A7 b': Notes back takes its tile again");
    Expect(!Says(@"no tile to take"), @"A7 b': a tiled window back is not taken for an untiled one");
    // 4. a No Fit window full screen stays full screen's while it is, and is back when it is on the desktop again (beside one tiled window: the
    //    tick's one-window rule returns before its own "back from full screen", F3's look is before it)
    Reset(@{ maps: @"fill" }); [gSMFreeWindows addObject:clk];
    FullLook(clk); Look(@[ maps ], nil);
    Expect([gSMFitWentFull containsObject:clk], @"No Fit full screen: still full screen's while it is");
    Look(@[ clk, maps ], nil);
    Expect(!gSMFitWentFull.count && Says(@"com.apple.mobiletimer/default back from full screen as a free window"), @"No Fit back from full screen beside one window: no longer full screen's");
    // 5. a regular window over four tiles to full screen and back: a regular window again, no longer full screen's
    Reset(@{ as: @"topleft", set: @"bottomleft", saf: @"topright", maps: @"bottomright" }); [gSMFitLoose addObject:tips];
    FullLook(tips); Look(@[ tips, as, set, saf, maps ], nil);
    Expect(!gSMFitWentFull.count && [gSMFitLoose containsObject:tips] && Says(@"back from full screen as a regular window over the tiles"), @"a regular window back: no longer full screen's, still regular");
    Expect(gSMFitSlots.count == 4 && !Says(@"back from full screen -- "), @"  ... the four tiles kept, no tiled way back");
    // 6. windows by window: Notes' window full screen, its other window free on the desktop
    Reset(@{ maps: @"fill" }); [gSMFreeWindows addObjectsFromArray:@[ notes, notes2 ]];
    FullLook(notes); Look(@[ notes2, maps ], nil);
    Expect([gSMFitWentFull isEqualToSet:[NSSet setWithObject:notes]], @"two windows of Notes: the one still full screen stays, its other window on the desktop does not take it out");
    printf("f3back: %d cases, %d failed\n", n, fails);
    return fails ? 1 : 0;
} }
EOF
f3build() {   # f3build <name> <dir with the .inc files> <include dir> <main>: built once per input (cached by its hash); its exit code, 3 if it does not build
  local h; h=$(cat "$2"/*.inc "$3"/*.h "$4" | shasum | cut -c1-16); local d="$W/$1-$h"
  if [ ! -f "$d.rc" ]; then
    mkdir -p "$d"; cp "$2"/*.inc "$d/"
    if clang -fobjc-arc -Wall -Werror -Wno-unused-function -Wno-unused-but-set-variable -I "$d" -I "$3" -framework Foundation -framework CoreGraphics -o "$d/t" "$4" > "$d/build" 2>&1; then "$d/t" > "$d/out" 2>&1; echo $? > "$d.rc"
    else echo 3 > "$d.rc"; cp "$d/build" "$d/out"; fi
  fi
  cp "$d/out" "$W/$1.out"; return "$(cat "$d.rc")"
}
f3_loadrun() {   # DMAppSizesLoad as written in <StatusBar.x>, on the AppWindowSize.h of <root>
  local d="$W/f3l-in"; rm -rf "$d"; mkdir -p "$d"
  f1 'static void DMAppSizesLoad(void) {' "$1" > "$d/f3load.inc"; [ -s "$d/f3load.inc" ] || return 1
  f3build f3load "$d" "$2/common" "$W/f3load-main.m"
}
f3_backrun() {   # DMSMFitTick's statements on the windows that went full screen as written in <StatusBar.x>, on the SMFitPlan.h of <root>
  local d="$W/f3b-in"; rm -rf "$d"; mkdir -p "$d"
  f1 'static void DMSMFitTick(BOOL force) {' "$1" > "$d/tick"
  awk 'index($0, "    {   // (which windows are full screen now") == 1 {f=1; next} f && $0 == "    }" {exit} f' "$d/tick" > "$d/f3full.inc"
  awk 'index($0, "    NSMutableArray *bundles = [NSMutableArray array];") == 1 {f=1} index($0, "    // (a No Fit window is forgotten once it has closed") == 1 {exit} f' "$d/tick" > "$d/f3bundles.inc"
  awk 'index($0, "        NSMutableDictionary<NSString *, NSString *> *slotsForPart = nil;") == 1 {f=1} f {print} f && index($0, "        bundles = [part mutableCopy];") == 1 {exit}' "$d/tick" > "$d/f3part.inc"
  awk 'index($0, "    NSArray<NSString *> *planned = ") == 1 || index($0, "    NSString *returning = nil;") == 1 {f=1} f {print} f && index($0, "(closed meanwhile)") {exit}' "$d/tick" > "$d/f3back.inc"   # (from 1.8.8 H2's planned, when the file has it)
  local i; for i in full bundles part back; do [ -s "$d/f3$i.inc" ] || return 1; done
  f3build f3back "$d" "$2/statusbar" "$W/f3back-main.m"
}
f3_sites() {   # the read asked for the type, the log once; the tick's two calls where the windows are known, before any wait returns; the rule in SMFitPlan.h
  f1 'static void DMAppSizesLoad(void) {' "$1" > "$W/f3al" && grep -qF 'NSDictionary *now = CFBridgingRelease(MSBDAppSizesRead(v, &bad, &over, &wrong));' "$W/f3al" \
    && order 'MSBDAppSizesRead(v, &bad, &over, &wrong)' 'if (wrong && wrong != loggedWrong)' "$W/f3al" && grep -qxF '    loggedWrong = wrong;' "$W/f3al" \
    && [ "$(grep -c 'MSBDAppSizesRead(' "$1")" = 1 ] \
    && f1 'static void DMSMFitTick(BOOL force) {' "$1" > "$W/f3t" && [ "$(grep -c 'DMSMFitBackUntiled(' "$W/f3t")" = 2 ] && [ "$(grep -c 'DMSMFitBackUntiled(' "$1")" = 2 ] \
    && awk 'index($0, "    for (NSString *k in keysNow) if (![gSMFreeWindows containsObject:k]) [bundles addObject:k];") == 1 {b=NR}
            index($0, "    for (NSString *k in DMSMFitBackUntiled(gSMFitWentFull, keysNow, bundles)) {") == 1 {s=NR}
            index($0, "    if (gSMFitAdopt && !force) {") == 1 {a=NR} index($0, "    if (!force && !gSMFitLookAgain && [set isEqualToArray:lastSet ?: @[]]) return;") == 1 {l=NR}
            index($0, "        gSMFitLoose = looseNow.count ? [looseNow mutableCopy] : nil;") == 1 {g=NR}
            index($0, "        for (NSString *k in DMSMFitBackUntiled(gSMFitWentFull, bundles, part)) {") == 1 {t=NR}
            index($0, "        bundles = [part mutableCopy];") == 1 {p=NR}
            END {exit !(b && s == b + 1 && a > s && l > s && g && t == g + 1 && p > t)}' "$W/f3t" \
    && [ "$(grep -c 'DMSMFitBackUntiled(gSMFitWentFull, .*) {   // (back from full screen as a' "$W/f3t")" = 2 ] && [ "$(grep -cE '^ +\[gSMFitWentFull removeObject:k\];$' "$W/f3t")" = 2 ] \
    && grep -qF 'static inline NSArray<NSString *> *DMSMFitBackUntiled(NSSet<NSString *> *wentFull, NSArray<NSString *> *onScreen, NSArray<NSString *> *tiled) {' "$2/statusbar/SMFitPlan.h"
}
f3checks=(
"a stored value that is not a dictionary: DMAppSizesLoad asks the read rule for its type and logs it once (Settings asks nothing: c4's count check)|f3_sites"
"  ... built from StatusBar.x as it is and run on G1's reads (a number at the start, again, a text, an array, a dictionary, a number after it, absent, a bad entry, a boolean)|f3_loadrun"
"the green light's windows back from full screen as free windows, and regular windows over the tiles, are no longer full screen's: the tick's bookkeeping as written, run on A12b (iPad 2, A12Z), A7 b', No Fit, a regular window, two windows of an app|f3_backrun"
)
run_f3() {   # run_f3 <StatusBar.x> <root> [quiet]: every F3 check; exit 0 when all pass
  local bad=0 e name fn
  for e in "${f3checks[@]}"; do
    name="${e%|*}"; fn="${e##*|}"
    if ( $fn "$1" "$2" ) 2>/dev/null; then [ -n "$3" ] || echo "PASS  $name"; else [ -n "$3" ] && return 1; echo "FAIL  $name"; [ -s "$W/${fn#f3_}.out" ] || true; bad=1; fi
  done
  return $bad
}
run_f3 $S .. || { fails=1; for o in "$W"/f3load.out "$W"/f3back.out; do [ -s "$o" ] && grep '^FAIL\|error' "$o" | head -10; done; }
echo "-- F3's made-to-fail copies (each must fail the checks):"
f3mtf() {   # f3mtf <name> <file: S (StatusBar.x), AH (common/AppWindowSize.h) or SP (statusbar/SMFitPlan.h)> <perl substitution>
  local d="$W/f3mtf$((++f3n))"; mkdir -p "$d/common" "$d/statusbar"
  cp ../common/AppWindowSize.h ../common/WindowSize.h "$d/common/"; cp ../statusbar/WindowMinSize.h ../statusbar/SMFitPlan.h ../statusbar/SMWindowKey.h ../statusbar/FitPlan.h "$d/statusbar/"; cp $S "$d/S"
  local f o; case $2 in S) f="$d/S"; o=$S;; AH) f="$d/common/AppWindowSize.h"; o=../common/AppWindowSize.h;; SP) f="$d/statusbar/SMFitPlan.h"; o=../statusbar/SMFitPlan.h;; esac
  perl -0pi -e "$3" "$f"
  if cmp -s "$f" "$o"; then echo "FAIL  made-to-fail copy $1: the change did not apply"; fails=1; return; fi
  if run_f3 "$d/S" "$d" quiet; then echo "FAIL  made-to-fail copy $1 PASSED (it must fail)"; fails=1; else echo "PASS  made-to-fail copy $1 fails, as it must"; fi
}
f3n=0
f3mtf "the read's type not asked (DMAppSizesLoad passes NULL)" S 's/MSBDAppSizesRead\(v, &bad, &over, &wrong\)/MSBDAppSizesRead(v, \&bad, \&over, NULL)/'
f3mtf "the type never logged" S 's/    if \(wrong && wrong != loggedWrong\)\n        DMLog\([^\n]*\n//'
f3mtf "the type logged at every read (not once)" S 's/if \(wrong && wrong != loggedWrong\)/if (wrong)/'
f3mtf "the type logged once only, ever (a number after a dictionary not logged again)" S 's/    loggedWrong = wrong;\n/    if (wrong) loggedWrong = wrong;\n/'
f3mtf "the read rule not reporting the type (AppWindowSize.h)" AH 's/\*wrongType = stored && CFGetTypeID\(stored\) != CFDictionaryGetTypeID\(\) \? CFGetTypeID\(stored\) : 0;/*wrongType = 0;/'
f3mtf "a free window back from full screen left as full screen's (the tick's first call gone)" S 's/    for \(NSString \*k in DMSMFitBackUntiled\(gSMFitWentFull, keysNow, bundles\)\) \{[^\n]*\n(?:[^\n]*\n){2}    \}\n//'
f3mtf "a regular window back left as full screen's (the tick's second call gone)" S 's/        for \(NSString \*k in DMSMFitBackUntiled\(gSMFitWentFull, bundles, part\)\) \{[^\n]*\n(?:[^\n]*\n){2}        \}\n//'
f3mtf "the first call after the respring's adopt and the unchanged set (a free window back to an unchanged set of tiles never seen)" S 's/(    for \(NSString \*k in DMSMFitBackUntiled\(gSMFitWentFull, keysNow, bundles\)\) \{[^\n]*\n(?:[^\n]*\n){2}    \}\n)(.*?)(    gSMFitLookAgain = NO;)/$2$1$3/s'
f3mtf "the rule taking a tiled window back too (its tile lost: the default arrangement or the third window's question)" SP 's/&& !\[tiled containsObject:k\] //'
f3mtf "the rule taking every window that went full screen (one still full screen loses its way back)" SP 's/for \(NSString \*k in onScreen\) if \(\[k isKindOfClass:\[NSString class\]\] && \[wentFull containsObject:k\]/for (NSString *k in wentFull) if ([k isKindOfClass:[NSString class]] \&\& [wentFull containsObject:k]/'
f3mtf "the rule by app (another window of the app on the desktop takes the full-screen one out)" SP 's/    for \(NSString \*k in onScreen\) if \(\[k isKindOfClass:\[NSString class\]\] && \[wentFull containsObject:k\] && !\[tiled containsObject:k\] && !\[back containsObject:k\]\) \[back addObject:k\];/    for (NSString *w in wentFull) for (NSString *k in onScreen) if ([DMSMKeyBundle(w) isEqualToString:DMSMKeyBundle(k)] \&\& ![tiled containsObject:k] \&\& ![back containsObject:w]) [back addObject:w];/'
echo "-- the files before F3's fix (51b85da4, or its -reg twin ffb167e4: the same tree) fail F3's run checks, as the s01 passes saw it:"
for c in 51b85da4 ffb167e4; do git -C .. cat-file -e $c:statusbar/StatusBar.x 2>/dev/null && break; c=; done
if [ -n "$c" ]; then
  mkdir -p "$W/f3base"; git -C .. archive $c common statusbar/WindowMinSize.h statusbar/SMFitPlan.h statusbar/SMWindowKey.h statusbar/FitPlan.h | tar -x -C "$W/f3base"
  git -C .. show $c:statusbar/StatusBar.x > "$W/f3base/S"
  f3_loadrun "$W/f3base/S" "$W/f3base" && rc=0 || rc=$?
  if [ $rc = 0 ] || [ $rc = 3 ]; then echo "FAIL  the files before F3 pass the G1 reads or do not build (rc $rc)"; fails=1
  elif ! grep -q '^FAIL: a number at the start: no app, logged once, naming its type (log: )$' "$W/f3load.out"; then echo "FAIL  the files before F3 fail the G1 reads, but not as on the A12Z (a number with nothing logged)"; fails=1
  else echo "PASS  the files before F3 fail the G1 reads as on the A12Z: a number at the start logs nothing ($(grep -c '^FAIL:' "$W/f3load.out") of the cases)"; fi
  f3_backrun "$W/f3base/S" "$W/f3base" && rc=0 || rc=$?
  if [ $rc = 0 ] || [ $rc = 3 ]; then echo "FAIL  the files before F3 pass the stories or do not build (rc $rc)"; fails=1
  elif ! grep -q '^FAIL: A12b: Clock too: the smfit trigger lists no window as full screen (full screen: com.apple.mobiletimer|sceneID:com.apple.mobiletimer-default, com.apple.reminders|sceneID:com.apple.reminders-default;' "$W/f3back.out" \
       || grep -q "^FAIL: A7 b'" "$W/f3back.out"; then echo "FAIL  the files before F3 fail the stories, but not as on the iPad 2 (A12b: both windows listed as full screen; A7 b' as before)"; fails=1
  else echo "PASS  the files before F3 fail A12b as on the iPad 2 (Reminders and Clock still full screen's), A7 b' passing as before ($(grep -c '^FAIL:' "$W/f3back.out") of the cases)"; fi
else echo "SKIP  51b85da4 (ffb167e4) not in this repository"; fi
[ $fails = 0 ] && echo "test-appwindowsize: all pass" || { echo "test-appwindowsize: FAILED"; exit 1; }
