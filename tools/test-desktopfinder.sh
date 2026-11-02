#!/bin/bash
# Mac test of the desktop as Finder's (1.7.8, the 1.7.7 regression's bug 4): a touch on the desktop keeps the native windows (Finder, Activity
# Monitor) active and in front of the app windows -- it sent them behind them, so a desktop icon dragged to a Finder window that had been in front
# of an app window found it gone (17.5) --, and the keys follow what was clicked last: the desktop while it has them (an icon, a selection, a name
# edited on it), the native window once it is touched again. As built: statusbar/NativeWindow.h, Desktop.h, StatusBar.x.
set -e
cd "$(dirname "$0")"
N=../statusbar/NativeWindow.h; D=../statusbar/Desktop.h; S=../statusbar/StatusBar.x
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fnn() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$N"; }
fnd() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$D"; }
TB='__attribute__((noinline)) static void DMNativeTouchBegan(UITouch *t) {'
check "a touch on the desktop (it shows there, no app window over it) leaves the native windows active: it returns before they are made inactive" \
  "fnn '$TB' | awk '/if \\(DMDesktopShownAtScreen\\(p\\) && !DMNativeWindowTaking\\(p, DMDesktopWindowLevel\\(\\)\\)\\) \\{/{a=NR} a&&/return;/&&!b{b=NR} /DMNativeSetActive\\(nil\\);/{c=NR} END{exit !(a && b > a && c > b)}'"
check "  ... only after the Dock, our menus and the windows over the layer had their say (they keep Finder active already)" \
  "fnn '$TB' | awk '/if \\(taker\\) \\{ DMLog/{a=NR} /if \\(DMDesktopShownAtScreen\\(p\\)/{b=NR} END{exit !(a && b > a)}'"
check "  ... a native window's field stops typing (a click elsewhere ends it), the key view takes over again" \
  "fnn '$TB' | grep -q 'if (\\[gNativeLayer isKeyWindow\\]) { \\[gNativeLayer endEditing:YES\\];'"
check "  ... the desktop's tests are its own (where it shows, its window's level), declared for NativeWindow.h and defined with the desktop" \
  "grep -q '^static BOOL DMDesktopShownAtScreen(CGPoint sp) { return gDesktop && \\[gDesktop dm_shownAt:sp\\]; }' $D && grep -q '^static CGFloat DMDesktopWindowLevel(void) {' $D"
check "the keys: SpringBoard's press handling asks the desktop first while it has them, and what it does not take is never the native window's" \
  "awk '/^- \\(void\\)pressesBegan:\\(NSSet<UIPress \\*> \\*\\)presses withEvent:\\(UIPressesEvent \\*\\)event \\{/{f=1} f&&/if \\(gDesktop && \\[gDesktop dm_hasKeys\\]\\) \\{/{a=NR} f&&a&&!h&&/for \\(UIPress \\*p in presses\\) if \\(p.key && \\[gDesktop dm_handleKey:p.key\\]\\) return;/{h=NR} f&&h&&!o&&/%orig;/{o=NR} f&&o&&!r&&/return;/{r=NR} f&&/if \\(gNativeActive\\) for \\(UIPress \\*p in presses\\) if \\(DMNativeHandlePress\\(p\\)\\) return;/{b=NR} f&&/^}/{exit} END{exit !(a && h == a+1 && o == h+1 && r == o+1 && b > r)}' $S"
check "  ... a native window's shortcuts are offered to UIKit only while the desktop does not have the keys (Command-Delete would trash the window's own selection)" \
  "awk '/^- \\(NSArray<UIKeyCommand \\*> \\*\\)keyCommands \\{/{f=1} f&&/if \\(DMDesktopHasKeysNow\\(\\)\\) return @\\[\\];/{print \"ok\"; exit} f&&/^}/{exit}' $N | grep -q ok"
check "  ... a native window made active (touched, opened, brought forward) takes the keys back from the desktop, also the one already active" \
  "fnn 'static void DMNativeSetActive(DMNativeWindow *w) {' | awk '/if \\(w\\) DMDesktopYieldKeys\\(\\);/{a=NR} /if \\(w == gNativeActive\\) \\{ if \\(w\\) DMNativeTakeKeys\\(w\\); DMNativeApplyLevel\\(\\); return; \\}/{b=NR} END{exit !(a && b > a)}' \
   && grep -q '^static void DMDesktopYieldKeys(void) { if (gDesktop && \\[gDesktop dm_ownsKeys\\]) \\[gDesktop dm_setHasKeys:NO\\]; }' $D"
check "a name edited on the desktop no longer makes the native windows inactive; its own window is key, and the desktop's keys (Return, Esc) come first" \
  "! fnd '- (void)dm_beginRename:(NSString *)path {' | grep -q 'DMNativeSetActive(nil)' && fnd '- (void)dm_beginRename:(NSString *)path {' | grep -q 'if (!typeIn.isKeyWindow) \\[typeIn makeKeyWindow\\];' \
   && grep -q '^- (BOOL)dm_hasKeys { return (_hasKeys || _renameField || (!gNativeActive && !DMActiveApp()))' $D \
   && fnd '- (BOOL)dm_handleKey:(UIKey *)key {' | grep -q 'if (c == UIKeyboardHIDUsageKeyboardReturnOrEnter && none) { \\[self dm_endRename:YES\\]; return YES; }'"
[ $fails = 0 ] && echo "test-desktopfinder: all checks pass" || { echo "test-desktopfinder: checks FAILED"; exit 1; }
