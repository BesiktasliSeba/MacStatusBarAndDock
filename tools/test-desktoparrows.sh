#!/bin/bash
# Mac test of the arrow keys and Space on the desktop (1.8.4.2, KT 9 Nov): the rule (common/DesktopArrows.h, test-desktoparrows.c) and the wiring in
# statusbar/Desktop.h and Finder.h: the arrows, no modifier, move the selection; Command-Down still opens; Quick Look opened with Space follows it and
# Space closes it; a key that closes Quick Look gives the desktop its keys back.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
clang -O0 -Wall -o "$W/t" test-desktoparrows.c && "$W/t" || fails=1
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
D=../statusbar/Desktop.h; F=../statusbar/Finder.h
check "the desktop includes the rule and is Quick Look's browser" "grep -qF '#include \"../common/DesktopArrows.h\"' $D && grep -qF 'UIContextMenuInteractionDelegate, DMQuickLookBrowser>' $D"
check "the four arrows, no modifier, move the selection; Command-Down still opens" \
  "grep -qF 'case UIKeyboardHIDUsageKeyboardDownArrow: if (cmd && sel.count) { [self dm_openItems:sel]; return YES; } if (none) return [self dm_arrow:MSBD_STEP_DOWN]; break;' $D \
   && grep -qF 'if (none) return [self dm_arrow:MSBD_STEP_UP];' $D && grep -qF 'if (none) return [self dm_arrow:MSBD_STEP_LEFT];' $D && grep -qF 'if (none) return [self dm_arrow:MSBD_STEP_RIGHT];' $D"
check "a name being edited keeps the arrows, before any of this" "awk '/^- \(BOOL\)dm_handleKey:\(UIKey \*\)key \{/{f=1} f&&/if \(_renameField\) \{/{a=NR} f&&/UIKeyboardHIDUsageKeyboardUpArrow/{b=NR; exit} END{exit !(a&&b&&a<b)}' $D"
check "a step selects that icon alone and an open Quick Look follows it" "grep -qF '[self dm_select:@[p]];' $D && grep -qF '[[self dm_quickLookWindow] dm_follow:p];' $D"
check "Space opens Quick Look with the desktop as its browser; Space again closes it" \
  "grep -qF '[self dm_quickLookSelected:sel]' $D && grep -qF 'if (it) DMQuickLookOpenFrom(it.path, self);' $D && grep -qF 'if (q) { [q close]; return; }' $D"
check "Quick Look never takes the desktop for a window it can activate; the keys go back to it" \
  "grep -qF '[(id)b isKindOfClass:[DMNativeWindow class]] ? (DMNativeWindow *)b : b ? nil : (DMNativeWindow *)DMFinderFront()' $F && grep -qF '[b dm_previewClosed];' $F && grep -qF -- '- (void)dm_previewClosed { [self dm_setHasKeys:YES]; }' $D"
exit $fails
