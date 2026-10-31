#!/bin/bash
# test-postinst.sh: runs layout/DEBIAN/postinst on the Mac with a stand-in helper and launchctl (they only log what they were asked), /var/jb pointing
# into a scratch folder, and checks which steps run.
set -u
cd "$(dirname "$0")/.."
W=$(mktemp -d "${TMPDIR:-/tmp}/msbd-postinst.XXXXXX")
trap 'rm -rf "$W"' EXIT
R="$W/root/var/jb"
mkdir -p "$R/usr/bin" "$R/usr/libexec" "$R/Library/LaunchDaemons"
cat > "$R/usr/libexec/sshtoggled" <<EOF
#!/bin/sh
echo "helper \$*" >> "$W/calls"
[ "\$1" = "--is-ipad" ] && exit \$(cat "$W/ipad-rc")
[ "\$1" = "--quit-set-kept" ] && exit \$(cat "$W/kept-rc" 2>/dev/null || echo 0)
[ "\$1" = "--dasd-part-current" ] && exit \$(cat "$W/dasd-rc" 2>/dev/null || echo 1)
exit 0
EOF
cat > "$R/usr/bin/killall" <<EOF
#!/bin/sh
echo "killall \$*" >> "$W/calls"
EOF
cat > "$R/usr/bin/launchctl" <<EOF
#!/bin/sh
echo "launchctl \$*" >> "$W/calls"
EOF
chmod +x "$R/usr/libexec/sshtoggled" "$R/usr/bin/launchctl" "$R/usr/bin/killall"
: > "$R/Library/LaunchDaemons/com.besiktasliseba.sshtoggled.plist"
sed "s#/var/jb#$R#g" layout/DEBIAN/postinst > "$W/postinst"; chmod +x "$W/postinst"

pass=0; fail=0
run() {   # run <name> <is-ipad exit code> <expected: setup|nosetup> <postinst args...>
    local name="$1" rc="$2" want="$3"; shift 3
    echo "$rc" > "$W/ipad-rc"; : > "$W/calls"
    out=$("$W/postinst" "$@" 2>&1); prc=$?
    local setup=nosetup
    grep -q -- "--after-install" "$W/calls" && grep -q "launchctl load .*com.besiktasliseba.sshtoggled.plist" "$W/calls" && setup=setup
    if [ "$setup" = "$want" ] && [ "$prc" = 0 ]; then pass=$((pass+1)); printf 'ok    %s\n' "$name"
    else fail=$((fail+1)); printf 'FAIL  %s (got %s, postinst exit %s)\n%s\n' "$name" "$setup" "$prc" "$(sed 's/^/        /' "$W/calls")"; fi
}
run "configure on an iPad (0): full setup"                           0   setup   configure ""
run "configure on an iPhone (2): nothing set up"                     2   nosetup configure ""
run "configure, helper failed (1): full setup, said so"             1   setup   configure 1.0.0
run "configure, helper crashed (139): full setup"                   139 setup   configure 1.0.0
run "configure, helper killed (137): full setup"                    137 setup   configure 1.0.0
for a in abort-upgrade abort-remove abort-deconfigure; do
    echo 0 > "$W/ipad-rc"; : > "$W/calls"; "$W/postinst" $a 1.0.1 >/dev/null 2>&1; prc=$?
    if [ "$prc" = 0 ] && grep -q "launchctl load .*com.besiktasliseba.sshtoggled.plist" "$W/calls" && ! grep -q "^helper" "$W/calls"; then pass=$((pass+1)); echo "ok    $a: helper started again, nothing else run"
    else fail=$((fail+1)); echo "FAIL  $a: $(tr '\n' ';' < "$W/calls")"; fi
done
: > "$W/calls"; "$W/postinst" triggered >/dev/null 2>&1
[ ! -s "$W/calls" ] && { pass=$((pass+1)); echo "ok    other actions do nothing"; } || { fail=$((fail+1)); echo "FAIL  another action ran: $(cat "$W/calls")"; }
echo 1 > "$W/ipad-rc"; : > "$W/calls"; out=$("$W/postinst" configure 1.0.0 2>&1)
case "$out" in *"could not run (code 1)"*) pass=$((pass+1)); echo "ok    a failed check is reported";; *) fail=$((fail+1)); echo "FAIL  a failed check is not reported: $out";; esac
# the quit set's file for dasd: on the first update to a version that has it, it starts as the set SpringBoard keeps (cfprefsd's file of it);
# one that is there already is SpringBoard's own and stays; no set kept, no file
P="$R/var/mobile/Library/Preferences"; mkdir -p "$P"; QS="$P/MacStatusBarAndDock-PrewarmQuitSet.plist"; QP="$P/com.besiktasliseba.macstatusbar.prewarm.plist"
qs() {   # qs <name> <condition>
    if eval "$2"; then pass=$((pass+1)); echo "ok    $1"; else fail=$((fail+1)); echo "FAIL  $1"; fi
}
echo 0 > "$W/ipad-rc"; rm -f "$QS" "$QP"; printf 'bplist00 the set' > "$QP"
"$W/postinst" configure 1.6.1 >/dev/null 2>&1
qs "quit set: the first update starts dasd's file as SpringBoard's set" 'cmp -s "$QP" "$QS"'
printf 'ours' > "$QS"; "$W/postinst" configure 1.7.0 >/dev/null 2>&1
qs "quit set: a file of SpringBoard's own is kept" '[ "$(cat "$QS")" = ours ]'
rm -f "$QS" "$QP"; "$W/postinst" configure 1.6.1 >/dev/null 2>&1
qs "quit set: no set kept, no file made" '[ ! -e "$QS" ]'
# (code review, 30 Oct: the file is the block's switch since 1.7.1 -- made for a SpringBoard that keeps no set, dasd refused those apps until that
#  SpringBoard's start removed it. The helper answers as SpringBoard decides: Mac Status Bar's old on/off, Use Stock Status Bar, the version gate)
printf 'bplist00 the set' > "$QP"; echo 1 > "$W/kept-rc"; : > "$W/calls"; "$W/postinst" configure 1.7.0 >/dev/null 2>&1
qs "quit set: Mac Status Bar off, Use Stock Status Bar on or the tweak not running (the helper says no set is kept): no file made" '[ ! -e "$QS" ] && grep -q -- "--quit-set-kept" "$W/calls"'
printf 'left by 1.7.0' > "$QS"; "$W/postinst" configure 1.7.0 >/dev/null 2>&1
qs "quit set: no set kept, a file there (1.7.0 left it with the old on/off switched off): it goes before dasd starts again" '[ ! -e "$QS" ]'
echo 139 > "$W/kept-rc"; "$W/postinst" configure 1.7.0 >/dev/null 2>&1
qs "quit set: the helper could not answer (it crashed): no file made" '[ ! -e "$QS" ]'
printf 'ours' > "$QS"; "$W/postinst" configure 1.7.0 >/dev/null 2>&1
qs "  ... and one that is there stays" '[ "$(cat "$QS")" = ours ]'
rm -f "$QS"; echo 0 > "$W/kept-rc"; chmod -x "$R/usr/libexec/sshtoggled"; "$W/postinst" configure 1.7.0 >/dev/null 2>&1; chmod +x "$R/usr/libexec/sshtoggled"
qs "quit set: no helper to ask: no file made" '[ ! -e "$QS" ]'
: > "$W/calls"; "$W/postinst" configure 1.7.0 >/dev/null 2>&1
qs "quit set: the helper says a set is kept: the file made" 'cmp -s "$QP" "$QS" && grep -q -- "--quit-set-kept" "$W/calls"'
# dasd (1.7.2 item 8): restarted only when it lacks the prewarm block just installed -- the helper answers from the block's start stamp; any other
# answer, or no helper, restarts it as every install did before. The pointer process is restarted every time (unchanged).
echo 0 > "$W/ipad-rc"; echo 0 > "$W/kept-rc"
dasd() {   # dasd <name> <helper's answer, or "none"> <expected: kill|keep>
    if [ "$2" = none ]; then chmod -x "$R/usr/libexec/sshtoggled"; else echo "$2" > "$W/dasd-rc"; fi
    : > "$W/calls"; "$W/postinst" configure 1.7.1 >/dev/null 2>&1
    [ "$2" = none ] && chmod +x "$R/usr/libexec/sshtoggled"
    local got=keep; grep -q "^killall -9 dasd" "$W/calls" && got=kill
    if [ "$got" = "$3" ] && grep -q "^killall -9 pointeruid" "$W/calls"; then pass=$((pass+1)); echo "ok    $1"; else fail=$((fail+1)); echo "FAIL  $1 (got $got): $(tr '\n' ';' < "$W/calls")"; fi
}
dasd "dasd: the running dasd has the block just installed (helper 0): left running" 0 keep
dasd "dasd: it does not (helper 1: no stamp, another dasd, another build): restarted" 1 kill
dasd "dasd: the helper crashed (139): restarted" 139 kill
dasd "dasd: no helper to ask: restarted" none kill
echo 0 > "$W/dasd-rc"; : > "$W/calls"; "$W/postinst" configure 1.7.1 >/dev/null 2>&1
qs "dasd: the helper is asked after the quit set's file is settled (a dasd started again reads the right file)" 'awk "/--quit-set-kept/{q=NR} /--dasd-part-current/{d=NR} END{exit !(q && d && q < d)}" "$W/calls"'
echo "postinst: $pass passed, $fail failed"
[ "$fail" = 0 ]
