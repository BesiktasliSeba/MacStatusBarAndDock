#!/bin/bash
# Mac test of green's hand-over to the full-screen app (Aerial, StatusBar.x DMAerialToFullScreen; 1.7.8, the 1.7.7 leftover C5): the zoom ends
# where the live app is, so the cover goes in one cut once the app has laid itself out -- its last picture (the window's own layout, grown) faded
# over the live app's full-screen layout, a ghost for about a tenth of a second (M1 15.6.1, 1.7.7 RC). Without the app's word, and with Reduce
# Motion, it fades as before. As built.
set -e
cd "$(dirname "$0")"
S=../statusbar/StatusBar.x
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fns() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$S"; }
G='static void DMAerialToFullScreen(UIView *stage) {'
check "the cut: the zoomed picture and the still go at once, one frame after the app's word, the windows back with it -- before the fade's code" \
  "fns '$G' | awk '/if \\(zoom && !rm && laidOut\\) \\{/{a=NR} a&&/dispatch_after\\(dispatch_time\\(DISPATCH_TIME_NOW, \\(int64_t\\)\\(0.017 \\* NSEC_PER_SEC\\)\\)/&&!b{b=NR} b&&/if \\(gStageCover == cover\\) DMStageCoverRemove\\(\\);/&&!c{c=NR} c&&/return;/&&!d{d=NR} /animateWithDuration:rm \\? kMSBRMDuration : 0.2/{e=NR} END{exit !(a && b > a && c > b && d > c && e > d)}'"
check "  ... only with the app's word (laid out for the whole screen): the deadline without it fades, as before" \
  "fns '$G' | grep -q 'BOOL laidOut = \\[gResetLaidOut containsObject:@(mySeq)\\];' && fns '$G' | grep -q 'if (zoom && !rm && laidOut) {'"
check "  ... Reduce Motion keeps its cross-fade (the still, the window in it)" \
  "fns '$G' | grep -q 'if (zoom && !rm) gCoverSnap.hidden = YES; else zoom.hidden = YES;' && fns '$G' | grep -q 'animations:^{ cover.alpha = 0.0;'"
[ $fails = 0 ] && echo "test-greenhandover: all checks pass" || { echo "test-greenhandover: checks FAILED"; exit 1; }
