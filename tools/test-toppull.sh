#!/bin/bash
# Site checks (1.7.5 items 12 and 16): a pull from the top edge (Notification Center, Control Center) is never the Home Screen's swipe down, in either
# order; and with the Stage Manager engine an app opened while the App Library shows closes it, however it was opened.
set -e
cd "$(dirname "$0")"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
K=../dock/Dock.x
S=../statusbar/StatusBar.x
check "items 12 / 16: the start of a top-edge pull is noted (SBGrabberTongue -_pullGestureBegan:, the top edge only: -screenEdge, or the _screenEdge ivar on 15)" \
  "grep -q '^- (void)_pullGestureBegan:(id)gesture {' $K && grep -q 'if (!DMTongueOnTopEdge(self)) return;' $K && grep -q 'gTongueEdgeIvar = e && !strcmp(e, \"Q\") ? ivar_getOffset(iv) : -1;' $K"
check "  ... a swipe down within half a second of it is the pull's: no App Library (and no Spotlight pull)" \
  "awk '/^%hook SBSearchScrollView/{f=1} f&&/if \(CACurrentMediaTime\(\) - gTopPullAt < 0.5\) \{/{a=1} f&&a&&/return NO;/{b=1} f&&b&&/if \(DMPresentAppLibrary\(\)\) \{ gSwipeLibraryAt = CACurrentMediaTime\(\);/{print \"ok\"; exit}' $K | grep -q ok"
check "  ... the other order: an App Library the swipe down opened just before the pull began is closed again" \
  "grep -q 'if (now - gSwipeLibraryAt < 0.5) {' $K && grep -q 'DMDismissAppLibraryIfShowing()' $K"
check "  ... hooked only where the pull start has the known type" \
  "grep -q 'if (enc && !strcmp(enc, \"v24@0:8@16\")) %init(TopPullYield);' $K"
check "item 12: Stage Manager engine: an app activated while the App Library shows (our menus, Spotlight, a link) closes the App Library, as an icon tap does" \
  "grep -q 'if (DMLibraryVisible()) { NSString \*b = \[bundle copy\]; dispatch_async(dispatch_get_main_queue(), ^{ DMSMLibraryLaunched(b); }); }' $S"
[ $fails = 0 ] && echo "test-toppull: site checks pass" || { echo "test-toppull: site checks FAILED"; exit 1; }
