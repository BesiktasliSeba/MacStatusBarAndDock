#!/bin/bash
# Mac test of the menu bar's Audio title (common/AudioTitle.h, test-audiotitle.c; 1.7.8): the system's "audio is playing somewhere" flag decides,
# the sessions list only where the flag gives no answer -- then the wiring in StatusBar.x.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -o "$W/tat" test-audiotitle.c
"$W/tat"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
S=../statusbar/StatusBar.x
check "the title follows the shared rule, fed the flag as the controller gave it (1 / 0, -1 for no boolean) and the count of listed apps" \
  "grep -q 'int flag = \[v isKindOfClass:\[NSNumber class\]\] ? (\[v boolValue\] ? 1 : 0) : -1;' $S && grep -q 'playing = MSBDAudioTitlePlaying(flag, listed);' $S && grep -q 'listed = (long)ids.count;' $S"
check "  ... a listed session no longer forces the title on by itself (the A12Z's muted Spotify preview)" \
  "! grep -q 'if (ids.count) playing = YES;' $S"
check "  ... the sessions list still names the apps in the menu and feeds the one-audible-app rule" \
  "grep -q 'DMAudioSingleSourceUpdate(ids, NO);' $S && grep -q 'gAudioPlayingBundleIDs = ids;' $S"
check "  ... no controller at all: the title stays shown, as before" \
  "grep -q 'if (!controller) { DMAudioPlayingAnswer(nil, nil, nil); return; }' $S && grep -q 'BOOL playing = YES;' $S"
check "  ... no new polling: the same once-a-second question to the media server" \
  "grep -q 'if ((now - lastCheck < 1.0 && !gDMAudioCheckNow) || asking) return;' $S"
[ $fails = 0 ] && echo "test-audiotitle: site checks pass" || { echo "test-audiotitle: site checks FAILED"; exit 1; }
