#!/bin/bash
# Mac test of B71 (1.8.8.2): a switcher opening closes every menu of ours. Before, only iPadOS's system UI closed one (the tick: the App Switcher,
# Control Center, the Lock Screen, Spotlight, Notification Center), so the Mac Switcher, opened by keys or the Home button without a touch, left the
# open menu drawn over its view and still open after Esc or Home closed it, and the Dock's Downloads stack panel under it and after it.
# The real code is cut out of the source and run on the Mac against a model (test-switchermenus.m): DMMSWOpenNow (the Mac Switcher's one open
# point), DMCloseMenusForSwitcher (the switchers' one close), the tick's close for iPadOS's system UI, and the Dock part's export that closes its
# stack panel; each against 1.8.8.1's own DMMSWOpenNow and tick block, kept in the .m and compared here with 56d9461b when the history has it.
# The B71 review: the hold's picture from the gesture's start is not kept for the view when a menu of ours was on the screen at that start
# (DMMSWStartPicture and the tracker mark it from DMMenusOfOursShown; the Dock part's MSBDDownloadsPanelShown), closed since or not.
# Then site checks and made-to-fail copies. A file a check reads can be given as a copy (MSB_<NAME>=<path>): that is how the made-to-fail copies
# run, each of which must fail.
set -u
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"   # (the made-to-fail copies run this script again, from its own folder)
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
rc=0
SB0=../statusbar/StatusBar.x; MS0=../statusbar/MacSwitcher.h; D0=../dock/Downloads.m
fnf() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$2"; }
# the tick's block that closes a menu for iPadOS's system UI: from the "{" before its counter to its "}"
tickblock() { awk '/^        static int systemUITicks = 0;$/ {f=1; print prev} f {print} f && /^    }$/ {exit} {prev=$0}' "$1"; }
# build <dir> <StatusBar.x> <MacSwitcher.h> <Downloads.m>: the cut code into <dir>, the model built there (0: built)
build() {
    local d=$1; mkdir -p "$d"
    fnf 'static void DMMSWOpenNow(NSString *why) {' "$3" > "$d/open.inc"
    fnf '__attribute__((noinline)) static BOOL DMCloseMenusForSwitcher(NSString *which) {' "$2" > "$d/close.inc"
    tickblock "$2" > "$d/tick.inc"
    fnf '__attribute__((visibility("default"))) BOOL MSBDDownloadsPanelSwitcherClose(const char *which) {' "$4" > "$d/stack.inc"
    fnf '__attribute__((noinline)) static BOOL DMMenusOfOursShown(void) {' "$2" > "$d/shown.inc"
    fnf '__attribute__((visibility("default"))) BOOL MSBDDownloadsPanelShown(void) {' "$4" > "$d/dlshown.inc"
    fnf 'static void DMMSWStartPicture(id gesture) {' "$3" > "$d/start.inc"
    [ -s "$d/open.inc" ] && [ -s "$d/tick.inc" ] && [ -s "$d/start.inc" ] || { echo "      (the open, the tick's block or the gesture's start picture is not in the source as one piece)"; return 1; }
    local hs=; [ -s "$d/shown.inc" ] && hs=-DHAVE_SHOWN=1
    clang -fobjc-arc -DDEBUG=1 $hs -Wall -Wno-unused-function -Wno-unused-variable -I"$d" -I../statusbar -framework Foundation -o "$d/tsm" test-switchermenus.m > "$d/build.txt" 2>&1
}
# sites <StatusBar.x> <MacSwitcher.h> <Downloads.m> [quiet]: the site checks; returns how many failed
sites() {
    local SB=$1 MS=$2 D=$3 q=${4:-} n=0
    ck() { if eval "$2"; then [ -z "$q" ] && echo "PASS  $1"; else [ -z "$q" ] && echo "FAIL  $1"; n=$((n+1)); fi; }
    ck "DMCloseMenusForSwitcher is defined once, out of line, right after DMCloseOverlay and before DMCloseOverlaysForScreenOff (the close's section: its crash map answer)" \
       "[ \$(grep -c '^__attribute__((noinline)) static BOOL DMCloseMenusForSwitcher(NSString \\*which) {' $SB) = 1 ] \
        && awk '/^static void DMCloseOverlay\\(void\\) \\{/{a=1} a && /^}/{a=0; b=NR} /^__attribute__\\(\\(noinline\\)\\) static BOOL DMCloseMenusForSwitcher\\(/{c=NR} /^static void DMCloseOverlaysForScreenOff\\(void\\) \\{/{d=NR} END{exit !(b && c > b && c - b < 12 && d > c)}' $SB \
        && ! awk '/^static void DMCloseOverlay\\(void\\) \\{/{f=1} /^static void DMCloseOverlaysForScreenOff\\(void\\) \\{/{f=0} f' $SB | grep -qE '^// (====|----)'"
    ck "  ... it closes the menu with DMCloseOverlay, the one close (never DMRemoveOverlayNow), and the stack's panel by the Dock part's export" \
       "fnf '__attribute__((noinline)) static BOOL DMCloseMenusForSwitcher(' $SB > $W/c && [ \$(grep -c 'DMCloseOverlay();' $W/c) = 1 ] && ! grep -q 'DMRemoveOverlayNow' $W/c \
        && grep -qF 'stack = (BOOL (*)(const char *))dlsym(RTLD_DEFAULT, \"MSBDDownloadsPanelSwitcherClose\");' $W/c && grep -qF 'BOOL panel = stack && stack(which.UTF8String);' $W/c && grep -qF 'return menu || panel;' $W/c"
    ck "the Mac Switcher has one open point: the view is marked open only in DMMSWOpenNow, which DMMSWOpenOn (every way of opening) ends in" \
       "[ \$(cat ../statusbar/*.h ../statusbar/*.x | grep -c 'gMSWOpen = YES') = 1 ] && fnf 'static void DMMSWOpenNow(NSString *why) {' $MS | grep -q '^    gMSWOpen = YES;' \
        && fnf 'static void DMMSWOpenOn(UIScreen *s, NSString *why) {' $MS | grep -q '^    DMMSWOpenNow(why);' && grep -q '^static void DMMSWOpen(NSString \\*why) { DMMSWOpenOn(nil, why); }' $MS"
    ck "  ... DMMSWOpenNow closes them after its refusals and the typing, before the view shows and takes the keys" \
       "fnf 'static void DMMSWOpenNow(NSString *why) {' $MS | awk '/if \\(!w\\) return;/{a=NR} /DMDesktopTypingEnd\\(@\"the Mac Switcher opens\"\\);/{b=NR} /BOOL menuOut = DMCloseMenusForSwitcher\\(@\"the Mac Switcher\"\\);/{c=NR} /^    w.hidden = NO;/{d=NR} /^    DMMSWFocus\\(YES\\);/{e=NR} END{exit !(a && b > a && c > b && d > c && e > d)}'"
    ck "  ... and keeps no picture of the desktop when something was open (the strip's rule: no lift, no screen picture)" \
       "fnf 'static void DMMSWOpenNow(NSString *why) {' $MS > $W/o && grep -qF 'noPicture = stripOut || menuOut || liftMenu;' $W/o && grep -qF 'BOOL lift = !noPicture && liftable;' $W/o && grep -qF '    else if (!noPicture) {' $W/o && ! grep -qF '!stripOut' $W/o"
    ck "  ... nor the gesture's start picture when a menu of ours was on the screen at that start (B71 review)" \
       "grep -qF 'BOOL liftable = byGesture && gMSWLiftPic && gMSWLiftPicId == DMMSWCurId() && (CACurrentMediaTime() - gMSWLiftPicAt < 2.0 || (DMMSWGestureGrace() && gMSWLiftPicGen == gMSWTrackPicGen));' $W/o \
        && grep -qF 'BOOL liftMenu = liftable && gMSWLiftPicMenu;' $W/o && [ \$(grep -c 'gMSWLiftPicMenu' $W/o) = 1 ]"
    ck "every place the gesture's start picture is kept marks it, from DMMenusOfOursShown read before that picture is asked for (B71 review)" \
       "[ \$(grep -cE 'gMSWLiftPic = (pic|gMSWTrackPic);' $MS) = 3 ] && [ \$(grep -E 'gMSWLiftPic = (pic|gMSWTrackPic);' $MS | grep -c 'gMSWLiftPicMenu = ours;') = 3 ] \
        && [ \$(grep -c 'gMSWLiftPicMenu = ' $MS) = 4 ] && grep -q '^static BOOL gMSWLiftPicMenu = NO; ' $MS \
        && fnf 'static void DMMSWStartPicture(id gesture) {' $MS | awk '/^    BOOL ours = DMMenusOfOursShown\(\);/{a=NR} /DMMSWScreenPictureAsync\(/{b=NR} END{exit !(a && b > a)}' \
        && fnf 'static void DMMSWTrackBegin(id gesture) {' $MS | awk '/^    BOOL ours = DMMenusOfOursShown\(\);/{a=NR} /^    BOOL asked = /{b=NR} /gMSWLiftPic = gMSWTrackPic;/{c=NR} END{exit !(a && b > a && c > b)}' \
        && [ \$(cat ../statusbar/*.h ../statusbar/*.x | grep -c 'DMMenusOfOursShown()') = 2 ]"
    ck "DMMenusOfOursShown: out of line in the close's section, gOverlay and the Dock part's MSBDDownloadsPanelShown by dlsym; the Dock part exports it (showDownloads)" \
       "fnf '__attribute__((noinline)) static BOOL DMMenusOfOursShown(void) {' $SB > $W/s && [ \$(grep -c '^__attribute__((noinline)) static BOOL DMMenusOfOursShown(void) {' $SB) = 1 ] \
        && awk '/^__attribute__\(\(noinline\)\) static BOOL DMCloseMenusForSwitcher\(/{c=NR} /^__attribute__\(\(noinline\)\) static BOOL DMMenusOfOursShown\(/{s=NR} /^static void DMCloseOverlaysForScreenOff\(void\) \{/{d=NR} END{exit !(c && s > c && d > s)}' $SB \
        && grep -qF 'if (gOverlay) return YES;' $W/s && grep -qF 'shown = (BOOL (*)(void))dlsym(RTLD_DEFAULT, \"MSBDDownloadsPanelShown\");' $W/s && grep -qF 'return shown && shown();' $W/s \
        && fnf '__attribute__((visibility(\"default\"))) BOOL MSBDDownloadsPanelShown(void) {' $D | grep -qF 'return [[DMDownloadsPanel shared] isOpen];'"
    ck "the tick: iPadOS's App Switcher closes with the same close (DMCloseMenusForSwitcher), every other system UI with DMCloseOverlay as before" \
       "tickblock $SB > $W/t && grep -qF 'if (DMSwitcherVisible()) { systemUI = @\"the App Switcher\"; appSwitcher = YES; }' $W/t && [ \$(grep -c 'appSwitcher = YES' $W/t) = 1 ] \
        && grep -qF 'if (appSwitcher) DMCloseMenusForSwitcher(systemUI);' $W/t && [ \$(grep -c 'DMCloseOverlay();' $W/t) = 1 ]"
    ck "the Dock part exports its stack panel's close (default visibility, in Downloads.m: the crash map's showDownloads), its own animated close" \
       "fnf '__attribute__((visibility(\"default\"))) BOOL MSBDDownloadsPanelSwitcherClose(const char *which) {' $D > $W/d && grep -qF 'if (![p isOpen]) return NO;' $W/d && grep -qF '[p dismissAnimated:YES];' $W/d \
        && grep -q '^file DockMagnification \\^Downloads\\\\.m\\$ showDownloads$' crashmap-rules.txt"
    ck "the release markers: switcher-closes-menus and switcher-closes-stack in the code that closes" \
       "grep -qF 'DM_FEATURE_MARK(\"switcher-closes-menus\");' $W/c && grep -qF 'DM_FEATURE_MARK(\"switcher-closes-stack\");' $W/d"
    return $n
}
SB=${MSB_SB:-$SB0}; MS=${MSB_MS:-$MS0}; D=${MSB_D:-$D0}
if [ -n "${MSB_QUIET:-}" ]; then   # (a made-to-fail copy's run: the scenarios and the sites, quietly; 0 when everything passes, 3 and why when caught)
    if build "$W/q" "$SB" "$MS" "$D"; then "$W/q/tsm" > "$W/q/out.txt" 2>&1; s=$?; why="$(grep -c '^FAIL' "$W/q/out.txt") scenario check(s)"; else s=1; why="the model's build"; fi
    sites "$SB" "$MS" "$D" quiet; f=$?
    [ $s = 0 ] && [ $f = 0 ] && exit 0
    echo "$([ $s != 0 ] && echo "$why")$([ $s != 0 ] && [ $f != 0 ] && echo " and ")$([ $f != 0 ] && echo "$f site check(s)")"
    exit 3
fi
if build "$W/m" "$SB" "$MS" "$D"; then
    "$W/m/tsm" || rc=1
else
    echo "FAIL  the model does not build with this tree's code (a tree before 1.8.8.2 has no DMCloseMenusForSwitcher to build in):"; sed 's/^/        /' "$W/m/build.txt" | head -12; rc=1
fi
# 1.8.8.1's own code kept in the .m: exactly 56d9461b's (when the history has it)
if git -C .. cat-file -e 56d9461b:statusbar/MacSwitcher.h 2>/dev/null; then
    git -C .. show 56d9461b:statusbar/MacSwitcher.h > "$W/ms1881"; git -C .. show 56d9461b:statusbar/StatusBar.x > "$W/sb1881"
    if fnf 'static void DMMSWOpenNow(NSString *why) {' "$W/ms1881" | cmp -s - <(awk '/^#define DMMSWOpenNow DMMSWOpenNow1881$/{f=1; next} /^#undef DMMSWOpenNow$/{f=0} f' test-switchermenus.m) \
       && tickblock "$W/sb1881" | cmp -s - <(awk '/^static void DMTickClose1881\(BOOL ccActive\) \{$/{f=1; n=0} f {n++; if (n > 3) print} f && /^}$/ {exit}' test-switchermenus.m | sed '$d'); then
        echo "PASS  1.8.8.1's DMMSWOpenNow and tick block in the model are 56d9461b's, byte for byte"
    else echo "FAIL  1.8.8.1's DMMSWOpenNow or tick block in the model differs from 56d9461b's"; rc=1; fi
else echo "PASS  (56d9461b is not in this tree's history: the kept copies are not compared)"; fi
sites "$SB" "$MS" "$D" || rc=1
# made-to-fail copies: one part of the fix taken out each; each must fail
if [ -z "${MSB_NOMTF:-}" ]; then
    mtf() {   # $1 what, $2 which file (sb|ms|d), $3 perl expression (the whole file at once)
        local m=$W/mtf$RANDOM$RANDOM src; mkdir -p "$m"
        case $2 in sb) src=$SB0;; ms) src=$MS0;; d) src=$D0;; esac
        cp "$src" "$m/f"; perl -0pi -e "$3" "$m/f"
        if cmp -s "$m/f" "$src"; then echo "FAIL  made-to-fail ($1): the copy did not change"; rc=1; return; fi
        local e; case $2 in sb) e="MSB_SB=$m/f";; ms) e="MSB_MS=$m/f";; d) e="MSB_D=$m/f";; esac
        local by x; by=$(env $e MSB_QUIET=1 MSB_NOMTF=1 bash "$SELF" 2> /dev/null); x=$?
        if [ $x = 0 ]; then echo "FAIL  made-to-fail ($1): still passes"; rc=1
        elif [ $x = 3 ] && [ -n "$by" ]; then echo "PASS  made-to-fail ($1): caught by $by"
        else echo "FAIL  made-to-fail ($1): the copy's run ended without a verdict (exit $x)"; rc=1; fi
    }
    mtf "the Mac Switcher's open without the close" ms 's/BOOL menuOut = DMCloseMenusForSwitcher\(@"the Mac Switcher"\);/BOOL menuOut = NO;/'
    mtf "the close at the top of the open, before its refusals" ms 's/(    DM_FEATURE_MARK\("mac-switcher"\);\n)/$1    (void)DMCloseMenusForSwitcher(\@"the Mac Switcher");\n/'
    mtf "the close after the view shows" ms 's/    BOOL menuOut = DMCloseMenusForSwitcher\(\@"the Mac Switcher"\);\n/    BOOL menuOut = NO;\n/; s/(    DMMSWFocus\(YES\);\n)/$1    menuOut = DMCloseMenusForSwitcher(\@"the Mac Switcher");\n/'
    mtf "the picture kept with a menu open" ms 's/noPicture = stripOut \|\| menuOut \|\| liftMenu;/noPicture = stripOut || liftMenu;/'
    mtf "the lift picture kept with a menu open" ms 's/BOOL lift = !noPicture && liftable;/BOOL lift = !stripOut \&\& liftable;/'
    mtf "the open not reading the mark on the gesture's picture" ms 's/BOOL liftMenu = liftable && gMSWLiftPicMenu;/BOOL liftMenu = NO;/'
    mtf "the marked gesture's picture refused, the screen now taken" ms 's/BOOL noPicture = stripOut \|\| menuOut \|\| liftMenu;/BOOL noPicture = stripOut || menuOut;/; s/BOOL lift = !noPicture && liftable;/BOOL lift = !noPicture \&\& !liftMenu \&\& liftable;/'
    mtf "the hold's start picture not marked" ms 's/gMSWLiftPicGesture = g; gMSWLiftPicMenu = ours;/gMSWLiftPicGesture = g;/'
    mtf "the hold's start picture marked as it comes in, not as it is asked for" ms 's/gMSWLiftPicGesture = g; gMSWLiftPicMenu = ours;/gMSWLiftPicGesture = g; gMSWLiftPicMenu = DMMenusOfOursShown();/'
    mtf "the tracker's picture not marked" ms 's/gMSWLiftPicGesture = gesture; gMSWLiftPicMenu = ours; \}/gMSWLiftPicGesture = gesture; }/'
    mtf "the tracker's waiting picture not marked" ms 's/(gMSWLiftPic = gMSWTrackPic;.*?gMSWLiftPicGesture = gesture;) gMSWLiftPicMenu = ours;/$1/'
    mtf "something of ours on the screen without the stack's panel" sb 's/    return shown && shown\(\);\n/    return NO;\n/'
    mtf "something of ours on the screen not honouring the debug keep" sb 's/(static BOOL DMMenusOfOursShown\(void\) \{\n)    if \(DMTestFlag\("\/tmp\/msb-overlay-keep"\)\) return NO;\n/$1/'
    mtf "the Dock part saying its panel is never on the screen" d 's/    return \[\[DMDownloadsPanel shared\] isOpen\];\n/    return NO;\n/'
    mtf "the stack's panel left open" sb 's/BOOL panel = stack && stack\(which.UTF8String\);/BOOL panel = NO;/'
    mtf "the Dock part's export asked for by another name" sb 's/dlsym\(RTLD_DEFAULT, "MSBDDownloadsPanelSwitcherClose"\)/dlsym(RTLD_DEFAULT, "MSBDDownloadsPanelClose")/'
    mtf "the menu removed at once instead of the one close" sb 's/(BOOL menu = gOverlay != nil;\n    if \(menu\) \{\n.*?\n.*?\n)        DMCloseOverlay\(\);/$1        gOverlay = nil;/s'
    mtf "the debug keep not honoured" sb 's/    if \(DMTestFlag\("\/tmp\/msb-overlay-keep"\)\) return NO;   \/\/[^\n]*\n//'
    mtf "the tick's App Switcher close left as DMCloseOverlay alone" sb 's/if \(appSwitcher\) DMCloseMenusForSwitcher\(systemUI\);/if (NO) DMCloseMenusForSwitcher(systemUI);/'
    mtf "the tick closing every system UI with the switchers' close" sb 's/if \(appSwitcher\) DMCloseMenusForSwitcher\(systemUI\);/if (YES) DMCloseMenusForSwitcher(systemUI);/'
    mtf "the Dock part's close without its animation" d 's/(DM_FEATURE_MARK\("switcher-closes-stack"\);\n.*?\n)    \[p dismissAnimated:YES\];/$1    [p dismissAnimated:NO];/s'
    mtf "the Dock part's close saying it closed a closed panel" d 's/(BOOL MSBDDownloadsPanelSwitcherClose\(const char \*which\) \{\n.*?\n)    if \(!\[p isOpen\]\) return NO;/$1    if (![p isOpen]) return YES;/s'
fi
[ $rc = 0 ] && echo "test-switchermenus: all pass" || echo "test-switchermenus: FAILED"
exit $rc
