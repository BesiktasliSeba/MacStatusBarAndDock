#!/bin/bash
# test-crashcause.sh (1.8.7.7, GitHub #14): our death record, common/CrashCause.h -- when SpringBoard dies of an uncaught exception, one line that
# names it (iPadOS 15/16 reports carry no reason: #14's four had none). Child processes (test-crashcause.m) install it as SpringBoard's loader
# does, with another tweak's handler installed before it, and throw: on the main thread (#14's crash 4: an unknown selector), on another thread
# with a long reason full of tabs and line breaks, UTF-8 cut in the middle, a thrown string (no record, no harm), a nil reason (Apple's own crash,
# before any handler), the same exception handed back by a handler that calls "the current handler" (no loop), no earlier handler, two installs.
# Each must die as before (SIGABRT), the earlier handler called exactly once with NO frame of ours on its stack (the tail call), the line one line of
# six fields. Built at -O0 (debug builds) and -Os (release). Then arm64 and arm64e (Theos' iPhoneOS SDK): the handler ends in a branch to prev,
# not a call. Then made-to-fail copies. The children run with ulimit -c 0; their crash reports (~/Library/Logs/DiagnosticReports) are removed.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
STAMP="$W/stamp"; touch "$STAMP"
CHILD=msbd-crashcause-child
build() {   # $1 the header dir (CrashCause.h), $2 opt, $3 out
  mkdir -p "$W/inc/common" && cp "$1/CrashCause.h" "$W/inc/common/CrashCause.h" && sed 's#"../common/CrashCause.h"#"common/CrashCause.h"#' test-crashcause.m > "$W/inc/t.m" &&
  clang -fobjc-arc -Wall -Werror=implicit-function-declaration "$2" -framework Foundation -I"$W/inc" -DMSBD_CAUSE_FILE="\"$W/rec.txt\"" -o "$3" "$W/inc/t.m"
}
child() {   # $1 program, $2 mode [$3 noinstall]: runs it; prints its end ("sig <n>" or "exit <n>")
  rm -f "$W/rec.txt" "$W/rec.txt.prev"
  ( ulimit -c 0; exec "$1" "$W/rec.txt" "$2" $3 ) >/dev/null 2>&1; local rc=$?
  [ $rc -gt 128 ] && echo "sig $((rc - 128))" || echo "exit $rc"
}
fields() { awk -F'\t' '{print NF}' "$W/rec.txt" 2>/dev/null | sort -u | tr '\n' ' '; }
lines() { [ -e "$W/rec.txt" ] && wc -l < "$W/rec.txt" | tr -d ' ' || echo 0; }
prevline() { cat "$W/rec.txt.prev" 2>/dev/null | tr '\n' ';'; }
scenarios() {   # $1 program, $2 quiet: the number of failed checks
  local P=$1 q=$2 n=0 end
  c() { if eval "$2" 2>/dev/null; then [ -n "$q" ] || echo "PASS  $1"; else [ -n "$q" ] || echo "FAIL  $1 ($3)"; n=$((n + 1)); fi; }
  end=$(child "$P" main)
  c "main thread, unknown selector: dies as before (SIGABRT)" '[ "$end" = "sig 6" ]' "$end"
  c "  one line, six fields: pid, time, main, name, reason, class" '[ "$(lines)" = 1 ] && [ "$(fields)" = "6 " ] && awk -F"\t" "{exit !(\$3 == \"main\" && \$4 == \"NSInvalidArgumentException\" && \$6 ~ /Exception/)}" "$W/rec.txt"' "$(cat "$W/rec.txt" 2>/dev/null)"
  c "  the reason names the selector (crash 4 of #14)" 'grep -q "stateService:didReceiveDoNotDisturbStateUpdate:\]: unrecognized selector sent to instance" "$W/rec.txt"' "$(cat "$W/rec.txt" 2>/dev/null)"
  c "  the pid is the child's own, the time now" 'awk -F"\t" -v now=$(date +%s) "{exit !(\$1 > 1 && now - \$2 < 30 && \$2 - now < 5)}" "$W/rec.txt"' "$(cut -f1,2 "$W/rec.txt" 2>/dev/null)"
  c "  the earlier handler called once, with no frame of ours on its stack" '[ "$(prevline)" = "prev 1 ours-frame 0;" ]' "$(prevline)"
  end=$(child "$P" thread)
  c "another thread, a 2000-character reason with tabs and line breaks: dies as before" '[ "$end" = "sig 6" ]' "$end"
  c "  one line, six fields, thread \"other\", the reason cut at 420 bytes" '[ "$(lines)" = 1 ] && [ "$(fields)" = "6 " ] && awk -F"\t" "{exit !(\$3 == \"other\" && length(\$5) <= 420 && length(\$5) >= 400)}" "$W/rec.txt"' "$(awk -F'\t' '{print $3, length($5)}' "$W/rec.txt" 2>/dev/null)"
  c "  the earlier handler called once, no frame of ours" '[ "$(prevline)" = "prev 1 ours-frame 0;" ]' "$(prevline)"
  end=$(child "$P" long)
  c "the main thread, the same long reason: one line" '[ "$end" = "sig 6" ] && [ "$(lines)" = 1 ] && [ "$(fields)" = "6 " ]' "$end $(lines) $(fields)"
  end=$(child "$P" utf8)
  c "a reason of 2-3 byte characters cut at 420 bytes: still valid UTF-8, one line" '[ "$end" = "sig 6" ] && [ "$(lines)" = 1 ] && python3 -I -c "import sys; open(sys.argv[1], \"rb\").read().decode(\"utf-8\")" "$W/rec.txt"' "$end $(lines)"
  end=$(child "$P" string)
  c "a thrown string (Foundation calls no handler): no line, dies as before" '[ "$end" = "sig 6" ] && [ "$(lines)" = 0 ]' "$end $(lines)"
  end=$(child "$P" nilreason)
  c "a nil reason (Apple's own crash before any handler): no line, dies as without us" '[ "${end#sig }" != "$end" ] && [ "$(lines)" = 0 ]' "$end $(lines)"
  end=$(child "$P" reentry)
  c "the same exception handed back by the earlier handler: no loop -- it is called once, dies as before" '[ "$end" = "sig 6" ] && [ "$(prevline)" = "prev 1 ours-frame 0;" ] && [ "$(lines)" = 1 ]' "$end $(prevline) $(lines)"
  end=$(child "$P" noprev)
  c "no earlier handler: the line, dies as before" '[ "$end" = "sig 6" ] && [ "$(lines)" = 1 ]' "$end $(lines)"
  end=$(child "$P" twice)
  c "installed twice: one link (the earlier handler once, one line)" '[ "$end" = "sig 6" ] && [ "$(prevline)" = "prev 1 ours-frame 0;" ] && [ "$(lines)" = 1 ]' "$end $(prevline) $(lines)"
  end=$(child "$P" main noinstall)
  c "without ours (control): no line, the earlier handler once" '[ "$end" = "sig 6" ] && [ "$(lines)" = 0 ] && [ "$(prevline)" = "prev 1 ours-frame 0;" ]' "$end $(lines) $(prevline)"
  return $n
}
rc=0
for o in -O0 -Os; do
  build ../common $o "$W/$CHILD" || { echo "FAIL  build $o"; exit 1; }
  echo "== $o"
  scenarios "$W/$CHILD" || rc=1
done
echo "== the iPad's architectures (Theos' iPhoneOS SDK): the handler hands over with a branch, not a call"
SDK=$(ls -d "$HOME"/theos/sdks/iPhoneOS16.5.sdk 2>/dev/null | head -1)
if [ -z "$SDK" ]; then echo "SKIP  no iPhoneOS16.5.sdk in ~/theos/sdks"; else
  printf '#include "common/CrashCause.h"\nint MSBDCauseTest(void) { return MSBDCauseInstall(); }\n' > "$W/inc/a.c"
  for a in arm64 arm64e; do for o in -O0 -Os; do
    clang -target $a-apple-ios15.0 -isysroot "$SDK" $o -Wall -c -I"$W/inc" -o "$W/a.o" "$W/inc/a.c" 2> "$W/cc.txt" || { echo "FAIL  $a $o: did not build"; cat "$W/cc.txt"; rc=1; continue; }
    [ -s "$W/cc.txt" ] && { echo "FAIL  $a $o: warnings"; cat "$W/cc.txt"; rc=1; }
    body=$(xcrun objdump -d --no-show-raw-insn "$W/a.o" | awk '/<_MSBDCauseHandler>:/ {f=1; next} f && /^[0-9a-f]+ </ {exit} f {print}' | sed 's/^ *//')
    # (prev is reached by an indirect branch WITHOUT link -- br / braaz on arm64e --, after the frame is popped; the other indirect calls in it,
    #  blr, are the runtime's functions it asks the exception through)
    tail=$(echo "$body" | /usr/bin/grep -E '^[0-9a-f]+:[[:space:]]+(br|braa|braaz|brab|brabz)[[:space:]]' | tail -1 | awk '{print $2, $3}')
    pop=$(echo "$body" | /usr/bin/grep -B10 -E '^[0-9a-f]+:[[:space:]]+(br|braa|braaz|brab|brabz)[[:space:]]' | /usr/bin/grep -cE 'ldp[[:space:]]+x29, x30|autibsp|retab')
    [ -n "$body" ] && [ -n "$tail" ] && [ "$pop" -ge 1 ] && echo "PASS  $a $o: MSBDCauseHandler pops its frame, then reaches prev by \"$tail\" (a branch, not a call)" || { echo "FAIL  $a $o: no branch to prev after its frame ('$tail', $pop)"; echo "$body" | tail -14; rc=1; }
  done; done
fi
echo "== made-to-fail copies (each takes one part out; the checks must fail)"
mtf() {   # $1 name, $2.. sed arguments on CrashCause.h
  local name=$1; shift
  rm -rf "$W/m"; mkdir -p "$W/m"; sed "$@" ../common/CrashCause.h > "$W/m/CrashCause.h"
  if cmp -s "$W/m/CrashCause.h" ../common/CrashCause.h; then echo "FAIL  made to fail ($name): the copy did not change"; rc=1; return; fi
  build "$W/m" -O0 "$W/m/$CHILD" 2>/dev/null || { echo "FAIL  made to fail ($name): did not build"; rc=1; return; }
  if scenarios "$W/m/$CHILD" quiet; then echo "FAIL  made to fail ($name): the checks still pass"; rc=1; else echo "PASS  made to fail ($name): caught"; fi
}
mtf "a call to prev instead of the tail call (our frame on its stack)" -e 's/__attribute__((musttail)) return prev(exc);/{ prev(exc); return; }/'
mtf "prev not called" -e 's/if (prev \&\& prev != MSBDCauseHandler) __attribute__((musttail)) return prev(exc);/(void)prev;/'
mtf "no check for the same exception handed back" -e 's/if (!exc || __atomic_exchange_n(&gMSBDCauseLast, exc, __ATOMIC_SEQ_CST) == exc) return;/if (!exc) return;/'
mtf "no check for an install already done" -e '/if (cur == MSBDCauseHandler) return 1;/d'
mtf "tabs and line breaks kept" -e "s/(\*in == '\\\\n' || \*in == '\\\\r' || \*in == '\\\\t') ? ' ' : \*in/*in/"
mtf "UTF-8 cut anywhere" -e '/(cut inside a character: back to its start/d' -e '/(...and that start too)/d'
mtf "nothing written" -e 's/MSBDCauseWrite(exc);$/;/'
# (the children's crash reports, written by the Mac's ReportCrash: removed)
find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 -name "$CHILD*" -newer "$STAMP" -delete 2>/dev/null
left=$(find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 -name "$CHILD*" -newer "$STAMP" 2>/dev/null | wc -l | tr -d ' ')
[ "$left" = 0 ] && echo "PASS  the children's crash reports removed" || { echo "FAIL  $left crash reports of the children left"; rc=1; }
[ $rc = 0 ] && echo "test-crashcause: all pass" || echo "test-crashcause: FAILED"
exit $rc
