#!/bin/bash
# Mac test of the volume and backlight chords beside Window Tiling Keys (1.8.3 item 3; common/ModifierTap.h, test-modifiertap.c), then the sites: VolumeGlobe
# and BrightnessKey follow the rule in SpringBoard -- at the press with the keys off, as before; at the release with them on, dropped when another key
# went down or a window key ran.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -o "$W/tmt" test-modifiertap.c
"$W/tmt"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
V=../volumeglobe/VolumeGlobe.x; B=../brightnesskey/BrightnessKey.x
check "VolumeGlobe: every press through the rule (another key ends a waiting chord), the chord's release acts, the window keys' word heard" \
  "grep -q 'int tap = MSBDModTapDown(&gTap, key ? (int)key.keyCode : 0, chord, key && MSBDModTapOtherHeld((int)key.keyCode, (unsigned long long)key.modifierFlags), gDefer);' $V && grep -q 'if (tap == kMSBDModTapWait) {' $V \
   && grep -q 'if (!key || MSBDModTapUp(&gTap, (int)key.keyCode) != kMSBDModTapActOnRelease) return;' $V && grep -q '^- (void)pressesEnded:' $V \
   && grep -q 'notify_register_dispatch(kMSBDModTapUsedNote, &usedToken, dispatch_get_main_queue(), ^(int t) { MSBDModTapUsed(&gTap); });' $V"
check "VolumeGlobe: the volume steps only for a chord that acts now (the keys not offered: at its key's press, as in 1.8.2.2); the other chord key going down while one waits (an Option-Shift arrangement) steps nothing (1.8.3 regression F1)" \
  "awk '/^static BOOL DMGlobeVolumePress\\(UIPress \\*p\\) \\{/{f=1} f{print} f && /^}/{exit}' $V > \$W/vg && grep -q 'if (tap != kMSBDModTapActNow) {' \$W/vg \
   && awk '/if \\(tap != kMSBDModTapActNow\\) \\{/{a=NR} /DMGlobeVolumeStep\\(step\\);/{b=NR} END{exit !(a && b && a < b)}' \$W/vg"
check "  ... waiting only while SpringBoard offers the window keys (their switch on and a window engine of ours: review 1.8.3 F8), not from the switch alone" \
  "grep -q 'BOOL offered = token && notify_get_state(token, &st) == NOTIFY_STATUS_OK && MSBDWindowKeysOfferedIn(st, getpid());' $V && grep -q 'gOffered = offered;' $V && grep -q 'gDefer = gOffered || gYoursWait;' $V \
   && grep -q 'notify_register_dispatch(kMSBDWindowKeysOfferedNote, &offeredToken, dispatch_get_main_queue(), ^(int t) { ReadOffered(t); })' $V \
   && ! grep -q 'kMSBDWindowKeysKey\|kMSBDWindowKeysChanged' $V \
   && grep -q 'BOOL on = token && notify_get_state(token, &st) == NOTIFY_STATUS_OK && MSBDWindowKeysOfferedIn(st, getpid());' $B && grep -q 'gKeysOffered = on;' $B && grep -q 'gDeferChords = gKeysOffered || gYoursWait;' $B \
   && grep -q 'notify_register_dispatch(kMSBDWindowKeysOfferedNote, &keysToken, dispatch_get_main_queue(), ^(int t) { ReadWindowKeysOffered(t); })' $B \
   && ! grep -q 'kMSBDWindowKeysKey\|kMSBDWindowKeysChanged' $B"
check "  ... with the keys off the press acts at once, as before (the same press twice still one step)" \
  "grep -q 'BOOL again = p.timestamp == lastTime && (long)key.keyCode == lastCode;' $V && ! grep -q 'lastPress' $V && grep -q 'DMGlobeVolumeStep(step);' $V"
check "BrightnessKey: with the keys on the chord waits at its key's down and acts at its release; the old path untouched otherwise; the window keys' word heard" \
  "grep -q 'if (MSBDModTapDown(&gChordTap, code, chord, MSBDModTapOtherHeld(code, flags), YES) == kMSBDModTapWait)' $B && grep -q '} else if (MSBDModTapUp(&gChordTap, code) == kMSBDModTapActOnRelease) {' $B \
   && grep -q 'if (!isDuplicate && (flags & SHIFT_FLAG) && \[key _isKeyDown\]) {' $B \
   && grep -q 'notify_register_dispatch(kMSBDModTapUsedNote, &usedToken, dispatch_get_main_queue(), ^(int t) { MSBDModTapUsed(&gChordTap); });' $B"
check "both chord keys held (Globe-Control-Option) is no tap at either site, told by the press's own modifier flags, so a press handed over twice (the M1) cannot wait again (1.8.3 regression F1, M1)" \
  "grep -q 'MSBDModTapOtherHeld((int)key.keyCode, (unsigned long long)key.modifierFlags)' $V && grep -q 'MSBDModTapOtherHeld(code, flags)' $B \
   && grep -q 'static inline int MSBDModTapDown(MSBDModTap \*t, int key, bool chord, bool otherHeld, bool defer) {' ../common/ModifierTap.h"
check "the window keys tell them, each time one runs" "grep -q 'notify_post(kMSBDModTapUsedNote);' ../statusbar/WindowKeys.h"
exit $fails
