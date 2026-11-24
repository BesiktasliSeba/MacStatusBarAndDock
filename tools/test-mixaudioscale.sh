#!/bin/bash
# test-mixaudioscale.sh: Mix Audio's per-app level on an app's own output unit (1.8.8.3, GitHub #18: a 16-bit game got LOUDER, full-scale noise,
# when its level was turned down). The render notification of a RemoteIO unit gets the unit's output side (32-bit float, non-interleaved on
# iPadOS), not the app's own format; the samples are now read in that format, checked against the buffer list, and anything not proven is left
# untouched (common/MixAudioScale.h). The real MARenderNotify and its helpers are cut out of mixaudio/MixAudio.x (MA_X: another copy, e.g. the
# code before the fix) and run on the Mac with test-mixaudioscale.c's model of the unit; then site checks on MixAudio.x; then made-to-fail copies:
# each takes one part of the fix out and must fail.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${MA_X:-../mixaudio/MixAudio.x}
H0=${MA_H:-../common/MixAudioScale.h}

run() {   # $1 MixAudio.x, $2 MixAudioScale.h (may be missing), $3 work dir, $4 quiet; the number of failed checks
  local X=$1 H=$2 d=$3 q=$4 n=0 out have=0
  mkdir -p "$d/common"
  awk '/^#define MA_MAX_UNITS /{on=1} on{print} on && /^static OSStatus MARenderNotify\(/{inn=1} inn && /^}$/{exit}' "$X" > "$d/notify.inc"
  grep -q '^static OSStatus MARenderNotify(' "$d/notify.inc" || { echo "FAIL  $X: no MARenderNotify after #define MA_MAX_UNITS"; return 99; }
  if [ -f "$H" ]; then cp "$H" "$d/common/MixAudioScale.h"; have=1; fi
  clang -O1 -Wall -Wno-unused-function -Wno-unused-variable -Werror=implicit-function-declaration -DHAVE_SCALE_H=$have -I"$d" \
        -o "$d/t" test-mixaudioscale.c 2> "$d/cc.txt" \
    || { [ -n "$q" ] || cat "$d/cc.txt"; echo "FAIL  the real code did not build"; return 99; }
  out=$("$d/t"); n=$?
  [ -n "$q" ] || echo "$out"
  if [ $n -ge 128 ]; then [ -n "$q" ] || echo "FAIL  the model ended on signal $((n - 128)) (buffers written past their end)"; n=1; fi
  sc() { if eval "$2"; then [ -n "$q" ] || echo "PASS  $1"; else [ -n "$q" ] || echo "FAIL  $1"; n=$((n + 1)); fi; }
  # (site checks) the header is MixAudio's; the notification reads the output side only; the app's format is read only by the DEBUG trace
  sc "MixAudio.x includes common/MixAudioScale.h" "grep -q '^#include \"../common/MixAudioScale.h\"' $X"
  sc "the notification scales through MSBDMixScaleRender with the output-side reader, nothing else writes samples there" \
     "grep -q 'int done = MSBDMixScaleRender(&st->scale, target, frames, io, MAReadOutputFormat, st->unit);' $X && ! grep -q 'x\\[i\\] \\*=' $X"
  sc "  ... MAReadOutputFormat reads kAudioUnitScope_Output, element 0" \
     "awk '/^static int MAReadOutputFormat\\(void \\*unit, AudioStreamBasicDescription \\*out\\) \\{/,/^}/' $X | grep -q 'kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, out, &size) == noErr'"
  sc "  ... with its release marker (mixaudio-output-format: verify-release-features finds the fix in the release build)" \
     "grep -A1 '^static int MAReadOutputFormat(void \\*unit, AudioStreamBasicDescription \\*out) {' $X | grep -q 'DM_FEATURE_MARK(\"mixaudio-output-format\");'"
  sc "  ... in a release build no stream format is read on the input scope (the app's format): only the DEBUG trace reads it" \
     "! clang -E -P -x c -DDEBUG=0 $d/notify.inc 2>/dev/null | grep -q 'kAudioUnitScope_Input' && clang -E -P -x c -DDEBUG=1 $d/notify.inc 2>/dev/null | grep -q 'kAudioUnitScope_Input' && [ \$(grep -c 'kAudioUnitScope_Input' $X) = 1 ]"
  sc "the app's own AudioUnitSetProperty of a stream format makes the unit's format be read again" \
     "grep -q 'if (prop == kAudioUnitProperty_StreamFormat) { MAUnitState \\*st = MAStateFor(unit); if (st) MSBDMixScaleForget(&st->scale); }' $X"
  sc "a route change makes every unit's format be read again (an observer in the start, not in excluded processes)" \
     "grep -B1 'addObserverForName:AVAudioSessionRouteChangeNotification object:nil queue:nil usingBlock:^(NSNotification \\*n) { MAForgetUnitFormats(); }];' $X | grep -q 'if (!MAExcludedProcess())' && awk '/^%ctor \\{/,/^}/' $X | grep -q 'MAForgetUnitFormats'"
  sc "a new unit starts at full level with no format read (MSBD_MIX_SCALE_STATE_INIT); voice-processing units still never get the notification" \
     "grep -q 'gMAUnits\\[i\\] = (MAUnitState){ \\*outInstance, MSBD_MIX_SCALE_STATE_INIT, voice, NO };' $X && grep -q 'else AudioUnitAddRenderNotify(\\*outInstance, MARenderNotify, &gMAUnits\\[i\\]);' $X"
  sc "the header has no Objective-C and nothing that can block the render thread (no lock, no allocation, no call but the reader)" \
     "[ -f $d/common/MixAudioScale.h ] && ! grep -Eq '@|objc|pthread|malloc|calloc|free\\(|dispatch|printf|NSLog' $d/common/MixAudioScale.h"
  return $n
}

run "$X0" "$H0" "$W/real"; rc=$?
if [ -z "$MA_X" ] && [ -z "$MA_H" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 file to change (x or h), $3 perl expression (whole file)
    local d="$W/m$((++k))" x="$X0" h="$H0" c
    mkdir -p "$d"
    if [ "$2" = x ]; then c="$d/MixAudio.x"; perl -0pe "$3" "$X0" > "$c"; x=$c; cmp -s "$c" "$X0"; else c="$d/MixAudioScale.h"; perl -0pe "$3" "$H0" > "$c"; h=$c; cmp -s "$c" "$H0"; fi \
      && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    run "$x" "$h" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1 ($n)"; rc=1; fi
  }
  k=0
  mtf "the format read on the input scope again (the app's format: the bug of GitHub #18)" x 's/kAudioUnitScope_Output, 0, out, &size\) == noErr/kAudioUnitScope_Input, 0, out, &size) == noErr/'
  mtf "no shape check (any buffer list taken as the format's)" h 's/(static inline int MSBDMixLayoutMatches\([^{]*\{)/$1 return 1;/'
  mtf "big endian not left out" h 's/if \(flags & kAudioFormatFlagIsBigEndian\) return MSBDMixSampleUnknown;//'
  mtf "unsigned integers taken as signed" h 's/if \(!\(flags & kAudioFormatFlagIsSignedInteger\)\) return MSBDMixSampleUnknown;//'
  mtf "the level not clamped to 0...1" h 's/if \(!\(target >= 0.0f\)\) target = 0.0f; else if \(target > 1.0f\) target = 1.0f;//'
  mtf "no read at once when a format that matched stops matching (that buffer at the app's own level)" h 's/        s->known = 0;          \/\/ it matched the buffers before[^\n]*\n/        break;\n/'
  mtf "no read for the next buffer after a read that does not match (only every 256 buffers)" h 's/if \(s->misses == 1 \|\| s->misses % MSBD_MIX_SCALE_REREAD == 0\)/if (s->misses % MSBD_MIX_SCALE_REREAD == 0)/'
  mtf "an untouched buffer keeps the last gain (the next one jumps down)" h 's/        s->lastGain = 1.0f;   \/\/ \(this buffer/        \/\/ (this buffer/'
  mtf "the ramp per sample, not per frame (interleaved channels apart)" h 's/x\[c\] \*= g;/x[c] *= g + step * (float)c \/ (float)channels;/'
  mtf "no route-change observer" x 's/\n    if \(!MAExcludedProcess\(\)\)   \/\/ \(the output units.*?MAForgetUnitFormats\(\); \}\];//s'
  mtf "the format not read again after the app sets one" x 's/if \(st\) MSBDMixScaleForget\(&st->scale\); \}/if (st) (void)st; }/'
fi
[ $rc = 0 ] && echo "test-mixaudioscale: all checks pass" || { echo "test-mixaudioscale: checks FAILED"; exit 1; }
