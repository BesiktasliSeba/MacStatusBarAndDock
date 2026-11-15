#!/bin/bash
# test-icleanstartover.sh: a cfprefsd restart during an iCleaner clean neither loses the clean's answer nor waits for the clean (1.8.7.5, audit L80
# of 1.8.7.2 and its review). sshtoggled starts over as a fresh process when cfprefsd restarted (an exec over itself, so mobile's settings are read
# anew). It ran the clean itself and skipped the start-over only while an eject ran: during a clean the process that was to answer was replaced
# (Finder ended with "iCleaner is still cleaning", a second tap ran a second root clean beside the first, which went on orphaned). Held back for the
# clean instead, it waited for a clean with no time limit: an eject asked meanwhile was not even seen, a switch made meanwhile applied from old
# settings, for good if iCleaner hung. Now the clean runs in a process of its own (--iclean-run), which answers by itself; the start-over does not
# wait for it and names it for the fresh process (--iclean-running), which waits for it: one clean at a time; a clean request asks for the
# start-over first and is read by the fresh process (--resume iclean); the timed run's pipe is close-on-exec (test-driveeject.sh).
# 1. test-icleanstartover.m on the real code cut out of main.m (IS_SSH_M: another copy, e.g. the code before the fix; what it lacks is stubbed);
# 2. site checks; 3. made-to-fail copies: each takes one part of the fix out and must fail.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
M0=${IS_SSH_M:-../macsettings/sshtoggled/main.m}
fn() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }   # one function of a file, from its first line
has() { awk -v h="$2" 'index($0, h) == 1 {f=1} END {exit !f}' "$1"; }   # the file has a line that starts so
SO='static void StartOverIfPrefsDaemonRestarted(unsigned work) {'
RUN='static int ICleanRun(const char *rid, const char *why) {'
WATCH='static void ICleanWatch(pid_t pid) {'
CARRY='static void ICleanCarriedOver(int argc, char **argv) {'
REQ='static void ICleanRequest(NSString *why) {'
code() {   # $1 main.m: the start-over with its state, the clean's answer, its process, its wait, the carried-over clean and the request
  awk -v h="$SO" 'index($0, "static NSString *gPrefsDaemons = nil;") == 1 {f=1} f {print} f && index($0, h) == 1 {g=1} g && /^[}]/ {exit}' "$1"
  grep -q 'static volatile int gICleanBusy' <(awk -v h="$SO" 'index($0, "static NSString *gPrefsDaemons = nil;") == 1 {f=1} f {print} f && index($0, h) == 1 {exit}' "$1") \
    || echo 'static volatile int gICleanBusy = 0;   // (the code before the L80 fix declared it with section 6)'
  fn "$1" 'static void ICleanWriteAnswer(NSString *rid, NSString *line) {'
  if has "$1" "$RUN"; then fn "$1" "$RUN"; else echo 'static int ICleanRun(const char *rid, const char *why) { return 3; }   // (the code before: no clean process of its own)'; fi
  if has "$1" "$WATCH"; then fn "$1" "$WATCH"; fi
  if has "$1" "$CARRY"; then fn "$1" "$CARRY"; else echo 'static void ICleanCarriedOver(int argc, char **argv) {}   // (the code before: nothing carried over a start-over)'; fi
  fn "$1" "$REQ"
}

compiled() {   # $1 main.m, $2 quiet: the scenarios built on its code and run; 0 when every check passes
  local d=$W/c$RANDOM; mkdir -p "$d/dir"
  code "$1" > "$d/startover.inc"
  { printf '#!/bin/sh\n[ -e "$MSBD_TEST_RUNS.running" ] && echo overlap >> "$MSBD_TEST_RUNS"\necho run >> "$MSBD_TEST_RUNS"\n: > "$MSBD_TEST_RUNS.running"\n'
    printf 'sleep "${MSBD_TEST_SECS:-3}"\nrm -f "$MSBD_TEST_RUNS.running"\necho success=true\necho freed=1.0 MB\necho deleted=3\necho shouldrespring=false\n'; } > "$d/dir/iCleaner"
  chmod +x "$d/dir/iCleaner"
  if ! clang -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -I"$d" -DIS_DIR="\"$d/dir\"" -framework Foundation -framework CoreFoundation -o "$d/t" test-icleanstartover.m > "$d/build.txt" 2>&1; then
    [ -n "$2" ] || { echo "(test-icleanstartover.m does not build against $1:)"; grep -m 3 'error:' "$d/build.txt"; }; return 1
  fi
  ( "$d/t" > "$d/out.txt" 2>&1 ) & local p=$!
  local i=0; while kill -0 $p 2>/dev/null && [ $i -lt 600 ]; do sleep 0.1; i=$((i + 1)); done   # (its own bound: 60 s)
  if kill -0 $p 2>/dev/null; then kill -9 $p 2>/dev/null; wait $p 2>/dev/null; [ -n "$2" ] || { cat "$d/out.txt"; echo "(test-icleanstartover.m did not finish in 60 s)"; }; return 1; fi
  wait $p; local r=$?
  [ -n "$2" ] || cat "$d/out.txt"
  return $r
}

main_part() { awk '/^int main\(int argc, char \*\*argv\) \{/,0' "$1"; }
line_of() { grep -nF -- "$2" "$1" | head -1 | cut -d: -f1; }   # $1 file, $2 fixed text: its first line number
run_mode_first() {   # $1 main.m: the clean's process's job, before the daemon's start
  main_part "$1" > "$W/main"
  local a b; a=$(line_of "$W/main" '        if (argc > 3 && strcmp(argv[1], "--iclean-run") == 0) return ICleanRun(argv[2], argv[3]);'); b=$(line_of "$W/main" 'gPrefsDaemons = PrefsDaemonSignature();')
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]
}
fresh_order() {   # $1 main.m: the queue, the clean carried over (next line), the request's post, the resumed request, the start's own look
  main_part "$1" > "$W/main"
  local a b e c d
  a=$(line_of "$W/main" 'gICleanQueue = dispatch_queue_create('); b=$(line_of "$W/main" '        ICleanCarriedOver(argc, argv);'); e=$(line_of "$W/main" 'notify_register_dispatch(kMSBDICleanRequestName')
  c=$(line_of "$W/main" 'if (resume && strstr(resume, "iclean")) ICleanRequest(@"Finder (after starting over)");'); d=$(line_of "$W/main" 'ICleanRequest(@"daemon start");')
  [ -n "$a" ] && [ -n "$b" ] && [ -n "$e" ] && [ -n "$c" ] && [ -n "$d" ] && [ "$b" = $((a + 1)) ] && [ "$e" -gt "$b" ] && [ "$c" -gt "$e" ] && [ "$d" -gt "$c" ]
}

sites() {   # $1 main.m, $2 quiet; the number of failed checks
  local M=$1 q=$2 n=0
  c() { if (eval "$2") >/dev/null 2>&1; then [ -n "$q" ] || echo "PASS  $1"; else [ -n "$q" ] || echo "FAIL  $1"; n=$((n + 1)); fi; }
  c "the start-over waits only for an eject (keeping what was asked); a clean under way does not hold it: its process is named for the fresh one" \
    "fn $M '$SO' > \$W/so && grep -qF 'if (gEjectBusy) { gWorkWhileBusy |= work; return; }' \$W/so && ! grep -q 'gICleanBusy) {' \$W/so \
     && grep -qF 'work |= gPendingWork | gWorkWhileBusy;' \$W/so && grep -qF 'if (work & kWorkIClean) [kinds addObject:@\"iclean\"];' \$W/so \
     && grep -qF 'pid_t clean = gICleanBusy ? gICleanPid : 0;' \$W/so \
     && grep -qF 'char *args[] = { gSelfPath, \"--resume\", (char *)resume.UTF8String, clean > 0 ? \"--iclean-running\" : NULL, cleanPid, NULL };' \$W/so"
  c "  ... it looks at the busy eject only once a start-over is due (after the cfprefsd check)" \
    "fn $M '$SO' | awk '/isEqualToString:gPrefsDaemons\\]\\) return;/{a=NR} /if \\(gEjectBusy\\) \\{ gWorkWhileBusy/{b=NR} END{exit !(a && b > a)}'"
  c "a clean request asks for the start-over first, before it reads the request" \
    "fn $M '$REQ' | awk '/if \\(gICleanBusy\\) \\{ gICleanAgain = YES; return; \\}/{a=NR} /StartOverIfPrefsDaemonRestarted\\(kWorkIClean\\);/{b=NR} /CFPreferencesCopyValue\\(key/{c=NR} END{exit !(a && b > a && c > b)}'"
  c "the clean runs in its own process (--iclean-run): none of the helper's descriptors but /dev/null on 0-2, no signal blocked; then waited for" \
    "fn $M '$REQ' > \$W/rq && grep -qF 'char *args[] = { gSelfPath, \"--iclean-run\", (char *)rid.UTF8String, (char *)why.UTF8String, NULL };' \$W/rq \
     && grep -qF 'posix_spawnattr_setflags(&at, POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK);' \$W/rq && [ \$(grep -c 'posix_spawn_file_actions_addopen(&fa, [012], \"/dev/null\"' \$W/rq) = 3 ] \
     && grep -qF 'int rc = posix_spawn(&pid, gSelfPath, &fa, &at, args, environ);' \$W/rq && grep -qxF '    ICleanWatch(pid);' \$W/rq && ! grep -q 'MSBDRunHelperTimed\\|dispatch_async' \$W/rq"
  c "  ... main runs that process's job (ICleanRun) before anything of the daemon's start" "run_mode_first $M"
  c "  ... it runs iCleaner, never stopped (no time limit), and writes the answer itself" \
    "fn $M '$RUN' > \$W/run && grep -qF 'int rc = MSBDRunHelperTimed(kMSBDICleanBinary, args, kMSBDICleanTimeout, &out, &status, &late);' \$W/run \
     && grep -q 'static const double kMSBDICleanTimeout = 0.0;' ../common/ICleaner.h && grep -qF 'ICleanWriteAnswer(r, line);' \$W/run && ! grep -q 'CFPreferences' \$W/run"
  c "the fresh process: a clean carried over is waited for right after the clean's queue is made, before any request; then the waiting request again (--resume ...iclean), before the start's own look" \
    "fresh_order $M"
  return $n
}

rc=0
if compiled "$M0"; then echo "PASS  the scenarios (test-icleanstartover.m against $M0)"; else echo "FAIL  the scenarios (test-icleanstartover.m against $M0)"; rc=1; fi
sites "$M0" || rc=1
if [ -z "$IS_SSH_M" ]; then
  mtf() {   # $1 name, $2 a filter on main.m (stdin to stdout) that takes one part of the fix out
    "$2" < "$M0" > "$W/m.m"
    if cmp -s "$W/m.m" "$M0"; then echo "FAIL  made-to-fail ($1): the copy did not change"; rc=1; return; fi
    if compiled "$W/m.m" quiet && sites "$W/m.m" quiet; then echo "FAIL  made-to-fail ($1): still passes"; rc=1
    elif compiled "$W/m.m" quiet; then echo "FAIL  made-to-fail ($1): caught by the site checks only"; rc=1
    else echo "PASS  made-to-fail ($1): caught by the scenarios"; fi
  }
  held() { sed -e 's/    if (gEjectBusy) { gWorkWhileBusy |= work; return; }/    if (gEjectBusy || gICleanBusy) { gWorkWhileBusy |= work; return; }/'; }
  not_named() { sed -e 's/clean > 0 ? "--iclean-running" : NULL, cleanPid, NULL };/NULL, cleanPid, NULL };/'; }
  not_waited() { grep -vxF '    ICleanWatch((pid_t)pid);'; }
  fds() { sed -e 's/posix_spawnattr_setflags(&at, POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK);/posix_spawnattr_setflags(\&at, POSIX_SPAWN_SETSIGMASK);/'; }
  no_ask() { grep -vF '    StartOverIfPrefsDaemonRestarted(kWorkIClean);   // (cfprefsd restarted:'; }
  no_kind() { grep -vF '    if (work & kWorkIClean) [kinds addObject:@"iclean"];'; }
  mtf "the start-over held back for a clean again" held
  mtf "the clean under way not named for the fresh process" not_named
  mtf "the fresh process not waiting for the clean carried over" not_waited
  mtf "the clean's process given the helper's descriptors" fds
  mtf "a clean request read without the start-over first" no_ask
  mtf "a clean not named in the resumed work" no_kind
fi
[ $rc = 0 ] && echo "test-icleanstartover: all pass" || echo "test-icleanstartover: FAILED"
exit $rc
