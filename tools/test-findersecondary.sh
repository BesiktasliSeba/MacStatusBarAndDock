#!/bin/bash
# test-findersecondary.sh: a pointer's secondary click in Finder's windows (1.8.8.1, B63) -- a mouse's right button, a trackpad's two-finger click or
# its two-finger tap with Tap to Click opens the menu a hold opens there, at the pointer: on a file or folder in the list and in the icons, on the
# folder's empty space, on a drive in the sidebar; a finger's press, a primary click and a hold as before. See test-findersecondary.m: the real
# code is cut out of statusbar/NativeWindow.h and Finder.h (FS_NATIVE_H / FS_FINDER_H: other copies, e.g. the code before the fix, where the press
# note does not exist yet) and run on the Mac (Mac Catalyst). The wiring is read from Finder.h's init, StatusBar.x's -[SpringBoard sendEvent:]
# hook (FS_SB_X) and the crash map's rules. Then made-to-fail copies: each takes one part of the fix out and must fail.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
N0=${FS_NATIVE_H:-../statusbar/NativeWindow.h}; F0=${FS_FINDER_H:-../statusbar/Finder.h}; X0=${FS_SB_X:-../statusbar/StatusBar.x}; R0=crashmap-rules.txt
fn() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }   # one function or method of a file, from its first line
line() { awk -v h="$2" 'index($0, h) == 1 {print; exit}' "$1"; }                    # one line of a file (a global)

N_LINES=('static __weak UITouch *gNativePressTouch;' 'static NSInteger gNativePressButtons;' 'static BOOL gNativePressTaken;')
N_NOTE='__attribute__((noinline)) static void DMNativeNotePress(UIEvent *e) {'; N_TAKE='static BOOL DMNativeTakeSecondaryPress(UIView *in) {'
N_NOTE_ANY='static void DMNativeNotePress(UIEvent *e) {'   # (the same function without its noinline: it still runs here, the wiring check below fails)
F_FN=('- (DMFinderItem *)itemAt:(CGPoint)p in:(UIView *)v {' '- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)cmi configurationForMenuAtLocation:(CGPoint)loc {'
      '- (void)dm_sideMenuForDrive:(NSString *)root at:(CGPoint)sp {' '- (UIMenu *)dm_menuIn:(UIView *)v at:(CGPoint)loc {' '- (void)dm_menuByHoldIn:(UIView *)v at:(CGPoint)loc {')
F_NEW='- (void)dm_secondaryClickIn:(UIView *)v at:(CGPoint)loc {'
F_INIT='- (instancetype)initWithTitle:(NSString *)title frame:(CGRect)frame {'

run() {   # $1 NativeWindow.h, $2 Finder.h, $3 StatusBar.x, $4 work dir, $5 quiet; the number of failed checks (99: not built)
  local N=$1 F=$2 X=$3 d=$4 q=$5 h out n=0 s=0 init hook
  mkdir -p "$d"
  for h in "${F_FN[@]}"; do [ -n "$(fn "$F" "$h")" ] || { echo "FAIL  $F: no method \"$h\""; return 99; }; done
  [ -n "$(fn "$F" "$F_INIT")" ] || { echo "FAIL  $F: no Finder window init"; return 99; }
  local note; note=$(fn "$N" "$N_NOTE"); [ -n "$note" ] || note=$(fn "$N" "$N_NOTE_ANY")
  {
    if [ -n "$note" ]; then
      for h in "${N_LINES[@]}"; do line "$N" "$h"; done
      printf '%s\n' "$note"; fn "$N" "$N_TAKE"
    else
      echo 'static void DMNativeNotePress(UIEvent *e) { (void)e; }   // (this code notes no press)'
    fi
  } > "$d/fs-native.inc"
  { for h in "${F_FN[@]}"; do fn "$F" "$h"; done; fn "$F" "$F_NEW"; } > "$d/fs-finder.inc"
  # the wiring
  ck() { if eval "$2"; then [ -n "$q" ] || echo "PASS  $1"; else [ -n "$q" ] || echo "FAIL  $1"; s=$((s + 1)); fi; }
  init=$(fn "$F" "$F_INIT")
  ck "Finder.h's init: the list and the icons each have a context menu interaction with the window as its delegate" \
     "printf '%s\n' \"\$init\" | awk '/for \\(UIView \\*v in @\\[_list, _grid\\]\\)/{l=NR} l&&NR<=l+1&&/addInteraction:\\[\\[UIContextMenuInteraction alloc\\] initWithDelegate:self\\]/{print \"ok\"; exit}' | grep -q ok"
  ck "  ... and so has the sidebar (a drive's menu on a secondary click comes through it)" \
     "printf '%s\n' \"\$init\" | grep -qF '[_sidebar addInteraction:[[UIContextMenuInteraction alloc] initWithDelegate:self]];'"
  ck "Finder.h: no tap set to the secondary button is left (UIKit never offers it that click) and no menu action of one" \
     "! grep -q 'buttonMaskRequired = UIEventButtonMaskSecondary' \"$F\" && ! grep -q 'dm_secondaryClick:\\|dm_sideSecondaryClick:' \"$F\""
  hook=$(awk '/^%group DMNativeHooks/{g=1} g&&/^- \(void\)sendEvent:\(UIEvent \*\)event \{/{f=1} f{print} f&&/^}/{exit}' "$X")
  ck "StatusBar.x: SpringBoard's -sendEvent: (the native windows' hooks) notes each press on the layer, with its buttons, before UIKit handles it" \
     "printf '%s\n' \"\$hook\" | awk '/^    if \\(event.type == UIEventTypeTouches && gNativeLayer && !gNativeLayer.hidden\\) DMNativeNotePress\\(event\\);/{a=NR} /^    %orig;/{b=NR} END{exit !(a && b > a)}'"
  ck "NativeWindow.h: the press note is a function of its own (noinline), so a crash in it is Finder's, not the transparent hook's" \
     "grep -qF '$N_NOTE' \"$N\""
  local re; re=$(awk '$1 == "sym" && $2 == "MacStatusBarCore" && $4 == "finder" && index($3, "DM(Finder|Native") {print $3; exit}' "$R0")
  ck "crashmap-rules.txt: DMNativeNotePress and DMNativeTakeSecondaryPress fall under Finder's rule (${re:-none found})" \
     "[ -n \"\$re\" ] && echo _DMNativeNotePress | grep -qE \"\$re\" && echo _DMNativeTakeSecondaryPress | grep -qE \"\$re\""
  clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
        -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Wno-objc-method-access -Werror=implicit-function-declaration -I"$d" \
        -framework UIKit -framework CoreGraphics -o "$d/t" test-findersecondary.m 2> "$d/cc.txt" || { [ -n "$q" ] || cat "$d/cc.txt"; echo "FAIL  the real code did not build"; return 99; }
  out=$("$d/t"); n=$?
  [ -n "$q" ] || echo "$out"
  return $((n + s))
}

run "$N0" "$F0" "$X0" "$W/real"; rc=$?
[ $rc = 0 ] && echo "test-findersecondary: all checks pass" || echo "test-findersecondary: $rc check(s) FAILED"
if [ -z "$FS_NATIVE_H$FS_FINDER_H$FS_SB_X" ]; then
  echo "-- made-to-fail copies (each must fail)"
  k=0; bad=0
  mtf() {   # $1 what, $2 file (nw|fh|sbx), $3 perl expression (whole file)
    local d="$W/m$((++k))" N=$N0 F=$F0 X=$X0 c src
    mkdir -p "$d"
    case $2 in nw) src=$N0; c="$d/NativeWindow.h"; N=$c;; fh) src=$F0; c="$d/Finder.h"; F=$c;; sbx) src=$X0; c="$d/StatusBar.x"; X=$c;; esac
    perl -0pe "$3" "$src" > "$c"
    cmp -s "$c" "$src" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; bad=1; return; }
    run "$N" "$F" "$X" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1"; bad=1; fi
  }
  mtf "UIKit's ask for a secondary click answered with nothing again (not handed to -dm_secondaryClickIn:at:)" fh 's/if \(!_menuByHold\) \{ \[self dm_secondaryClickIn:cmi\.view at:loc\]; return nil; \}/if (!_menuByHold) return nil;/'
  mtf "the sidebar without its context menu interaction" fh 's/\n        \[_sidebar addInteraction:\[\[UIContextMenuInteraction alloc\] initWithDelegate:self\]\];//'
  mtf "SpringBoard's -sendEvent: no longer notes the press" sbx 's/\n    if \(event\.type == UIEventTypeTouches && gNativeLayer && !gNativeLayer\.hidden\) DMNativeNotePress\(event\);[^\n]*//'
  mtf "the press note inlined into the hook (no symbol of its own for the crash map)" nw 's/__attribute__\(\(noinline\)\) static void DMNativeNotePress/static void DMNativeNotePress/'
  mtf "a press taken whatever its buttons (a finger, a primary click)" nw 's/ \|\| !\(gNativePressButtons & UIEventButtonMaskSecondary\)\) return NO;/) return NO;/'
  mtf "a press taken again at every ask" nw 's/\n    gNativePressTaken = YES;\n/\n/'
  mtf "a new press keeps the last one's take" nw 's/ gNativePressButtons = b; gNativePressTaken = NO;/ gNativePressButtons = b;/'
  mtf "a press that is over still taken" nw 's/\n    if \(t\.phase == UITouchPhaseEnded \|\| t\.phase == UITouchPhaseCancelled\) return NO;//'
  mtf "a press in another view taken" nw 's/    if \(!inside\) return NO;\n/    (void)inside;\n/'
  mtf "a touch in another window (the system gestures' copy) noted as the layer's press" nw 's/ \|\| !gNativeLayer \|\| t\.window != gNativeLayer\) continue;/) continue;/'
  mtf "the clicked item not selected first" fh 's/\n    if \(it && !\[self dm_isSelected:it\]\) \[self dm_setSelection:\@\[it\.path\] anchor:it\.path\];//'
  mtf "the drive's menu not opened from the sidebar" fh 's/\[s dm_sideMenuForDrive:root at:sp\]; \}\);/(void)root; });/'
  mtf "a click in the name being edited taken as Finder's" fh 's/\n    if \(_renameField && CGRectContainsPoint\(_renameField\.frame, loc\)\) return;[^\n]*//'
  mtf "the rename not ended by a secondary click elsewhere" fh 's/\n    \[self dm_endRename:YES\];   \/\/ \(elsewhere:[^\n]*//'
  # (two guards keep a place's click from a drive's menu: the row's drive flag here, and -dm_sideMenuForDrive:at:'s own drive check; both go)
  mtf "the menu opened even for a place in the sidebar that has none" fh 's/if \(!\[row\[\@"drive"\] boolValue\]\) return;   \/\/ \(the other places have no menu of their own, as with a hold\)\n        //; s/(NSDictionary \*d = DMFinderDriveInfo\(root\);)\n    if \(!d\) return;/$1/'
  [ $bad = 0 ] || rc=1
fi
exit $rc
