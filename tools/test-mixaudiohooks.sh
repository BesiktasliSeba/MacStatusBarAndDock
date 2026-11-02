#!/bin/bash
# Mac test of when MixAudio's C function hooks go in (mixaudio/MixAudio.x): the output unit's three (AudioComponentInstanceNew, -Dispose,
# AudioUnitSetProperty) at the start with the app (the last two are called all the time, on every thread, by every audio stack: patched later
# the patch could land on a function another thread runs -- code review 2 Nov); the AudioQueue ones that act only on queues made through
# AudioQueueNewOutput (SetParameter, GetParameter, Dispose) at its first call, before it returns, once.
set -e
cd "$(dirname "$0")"
X=${1:-../mixaudio/MixAudio.x}
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
G() { awk "/^%group $1\$/,/^%end/" $X; }
check "at the start (group MAOutput): AudioComponentInstanceNew, AudioComponentInstanceDispose, AudioUnitSetProperty" \
  "G MAOutput | grep -q '^%hookf(OSStatus, AudioComponentInstanceNew,' && G MAOutput | grep -q '^%hookf(OSStatus, AudioComponentInstanceDispose,' && G MAOutput | grep -q '^%hookf(OSStatus, AudioUnitSetProperty,'"
check "  ... MAOutput and MAQueue put in by the start itself (%ctor), for every process MixAudio runs in" \
  "awk '/^%ctor \\{/,/^}/' $X | grep -q 'if (!MAExcludedProcess()) { %init(MAOutput); %init(MAQueue); }'"
check "later (group MAQueueRest): only AudioQueueSetParameter, AudioQueueGetParameter, AudioQueueDispose" \
  "[ \"\$(G MAQueueRest | grep '^%hookf' | sed 's/^%hookf([^,]*, \\([A-Za-z]*\\),.*/\\1/' | tr '\\n' ' ')\" = 'AudioQueueSetParameter AudioQueueGetParameter AudioQueueDispose ' ]"
check "  ... put in once (dispatch_once), from both AudioQueueNewOutput hooks before the queue is made" \
  "grep -q '^static void MAInstallQueueRest(void) { static dispatch_once_t once; dispatch_once(&once, ^{ %init(MAQueueRest); }); }' $X && [ \$(G MAQueue | awk '/MAInstallQueueRest\\(\\);/{n++; getline; if (\$0 ~ /OSStatus r = %orig;/) ok++} END{print ok+0 \"/\" n+0}') = 2/2 ]"
check "no other group put in later (the only lazy %init is MAQueueRest's)" \
  "[ \$(grep -c 'dispatch_once(&once, ^{ %init(' $X) = 1 ] && ! grep -q 'MAOutputRest' $X"
[ $fails = 0 ] && echo "test-mixaudiohooks: all checks pass" || { echo "test-mixaudiohooks: checks FAILED"; exit 1; }
