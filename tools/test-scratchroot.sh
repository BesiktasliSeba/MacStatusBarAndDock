#!/bin/bash
# test-scratchroot.sh: tools/scratch-root.sh, which the tests that run the package's shell scripts use so that a script never runs with a real path
# in it (the tests also run on the iPads' own test lanes, where /var/jb and /var/mobile are the owner's files): every absolute path goes under the
# scratch root, in every place a shell script names one; /bin, /sbin, /dev, a URL and the #! line stay; a copy that still names a real path, or
# one built from ~, the environment, an empty variable, a glued option or a "..", is refused; so is a root that is not a private folder (1.8.8.4
# review). Then each of the package's four scripts: as shipped it names real paths, its copy none, and the copy is the script with only the root
# put in; and every test that runs one of them makes its copy with scratch_copy (none with a sed of its own, none runs a script of the tree as
# it is, none links to something not its own).
set -u
cd "$(dirname "$0")/.."
W=$(mktemp -d "${TMPDIR:-/tmp}/msbd-scratchroot.XXXXXX")
trap 'rm -rf "$W"' EXIT
. tools/scratch-root.sh
pass=0; fail=0
ok() { pass=$((pass+1)); echo "ok    $1"; }
bad() { fail=$((fail+1)); echo "FAIL  $1"; }
R="$W/root"
cat > "$W/s" <<'EOF'
#!/bin/sh
S=/var/jb/var/lib/x
rm -rf "/var/mobile/Library/Application Support/MacStatusBarAndDock"
[ "$1" = purge ] && rm -f /var/mobile/Library/Caches/a.plist '/var/root/b' /tmp/c
/var/jb/usr/bin/killall -9 dasd 2>/dev/null; (cd /private/var/tmp && ls)
X=`echo /usr/libexec/y`; Y=$(echo /Library/LaunchDaemons/z.plist)
rmdir "$S" 2>/dev/null
EOF
if scratch_copy "$W/s" "$R" "$W/c" > "$W/left"; then ok "a script naming paths in every place a shell script does: its copy made"; else bad "the copy refused: $(tr '\n' ' ' < "$W/left")"; fi
want="#!/bin/sh
S=$R/var/jb/var/lib/x
rm -rf \"$R/var/mobile/Library/Application Support/MacStatusBarAndDock\"
[ \"\$1\" = purge ] && rm -f $R/var/mobile/Library/Caches/a.plist '$R/var/root/b' $R/tmp/c
$R/var/jb/usr/bin/killall -9 dasd 2>/dev/null; (cd $R/private/var/tmp && ls)
X=\`echo $R/usr/libexec/y\`; Y=\$(echo $R/Library/LaunchDaemons/z.plist)
rmdir \"\$S\" 2>/dev/null"
[ "$(cat "$W/c" 2>/dev/null)" = "$want" ] && ok "  ... every path under the root (quoted, after =, a space, a ( or a backquote), the #! line, 2>/dev/null and the variables as they were" \
  || bad "  ... the copy is not as wanted: $(diff <(printf '%s\n' "$want") "$W/c" | tr '\n' ' ' | cut -c1-600)"
[ -x "$W/c" ] && ok "  ... executable" || bad "  ... not executable"
[ -n "$(scratch_left "$W/s" "$R")" ] && [ -z "$(scratch_left "$W/c" "$R")" ] && ok "  ... the check sees the real paths in the script and none in its copy" || bad "  ... the check is wrong: $(scratch_left "$W/s" "$R" | wc -l) / $(scratch_left "$W/c" "$R" | tr '\n' ' ')"
# (1.8.8.4 review) what the first copy let through, each a real path on an iPad's lane: a bare top folder or "/" and then a relative path or a
# variable, a path spliced from quotes or a command, a top folder glued to an option or after a variable that can be empty, ~ and the
# environment's folders, "cd" alone, a ".." that climbs out of the root; a root that is not a private folder of plain names; a list narrowed by
# the environment. Each is now under the root or refused (no copy left), and a check that cannot run never says "none left"
D="$W/brk"; mkdir -m 700 "$D"
moved() {   # moved <what> <script line> <the copy's line>
  printf '#!/bin/sh\n%s\n' "$2" > "$D/s"; rm -f "$D/c"
  if out=$(scratch_copy "$D/s" "$R" "$D/c") && [ "$(sed -n 2p "$D/c")" = "$3" ]; then ok "under the root: $1"
  else bad "not under the root as wanted: $1 ([$(printf '%s' "$out" | tr '\n' ' ')] [$(sed -n 2p "$D/c" 2>/dev/null)])"; fi
}
refused() {   # refused <what> <script line> <the reason, as said>
  printf '#!/bin/sh\n%s\n' "$2" > "$D/s"
  out=$(scratch_copy "$D/s" "$R" "$D/c"); rc=$?
  if [ $rc = 1 ] && [ ! -e "$D/c" ] && printf '%s\n' "$out" | grep -qF -- "$3"; then ok "refused, no copy left: $1"
  else bad "not refused as it should be: $1 (rc $rc, [$(printf '%s' "$out" | tr '\n' ' ')], copy $([ -e "$D/c" ] && echo left || echo none))"; fi
}
moved "a bare top folder, then a relative path or a variable (cd /tmp; T=/tmp)" 'cd /tmp && rm -f msb-flag; T=/tmp; rm -f "$T/x"' "cd $R/tmp && rm -f msb-flag; T=$R/tmp; rm -f \"\$T/x\""
moved "a bare / (cd /, then a relative path), a bare top folder (find /var)" 'cd / && rm -rf var/mobile/x; find /var -name y -delete' "cd $R/ && rm -rf var/mobile/x; find $R/var -name y -delete"
moved "a path spliced from quotes or a command" 'rm -rf "/""var/x" /va""r/y /$(echo var)/z' "rm -rf \"$R/\"\"var/x\" $R/va\"\"r/y $R/\$(echo var)/z"
moved "a redirection, a link, a PATH" 'echo x >/var/mobile/b; ln -s /var/mobile /var/jb/m; PATH=/usr/bin:/var/jb/usr/bin' "echo x >$R/var/mobile/b; ln -s $R/var/mobile $R/var/jb/m; PATH=$R/usr/bin:$R/var/jb/usr/bin"
moved "any top folder, not only a list of the system's" 'rm -rf /AppleInternal/x /root/z /x' "rm -rf $R/AppleInternal/x $R/root/z $R/x"
moved "  ... the tools, the devices, a URL and a path after a quoted variable as they were" 'ls /bin/x /sbin/y 2>/dev/null; echo http://example.com/x; rm -f "$S"/.ssh-state.*' 'ls /bin/x /sbin/y 2>/dev/null; echo http://example.com/x; rm -f "$S"/.ssh-state.*'
refused "~mobile (mobile's real home)" 'rm -rf ~mobile/Library/x' 'a home folder from ~: ~mobile/Library/x'
refused "a bare ~" 'rm -rf ~ /x' 'a home folder from ~: ~'
refused "\$HOME" 'rm -rf "$HOME/x"' 'a folder from the environment: $HOME'
refused "\${TMPDIR}" 'rm -rf "${TMPDIR}x"' 'a folder from the environment: ${TMPDIR'
refused "cd alone (to the home folder)" 'cd && rm -rf Library' 'cd to the home or the last folder: cd'
refused "a top folder glued to an option" 'tar -C/var/mobile -xf a.tar' 'a top folder after something: tar -C/var'
refused "a top folder after a variable that can be empty" 'rm -rf "$DPKG_ROOT/var/jb/x"' 'a top folder after something:  "$DPKG_ROOT/var'
refused "  ... after \${X} too" 'rm -rf ${X}/var/y' 'a top folder after something: rm -rf ${X}/var'
refused "a .. that climbs out of the root" 'rm -rf /var/jb/../../../../../../../../var/mobile/x' 'a .. part: ..'
refused "a / in arithmetic (the copy would make it a path)" 'x=$((4 / 2))' 'a / in arithmetic'
refused "a pattern the copy would make a path (awk)" "awk '/^Version/ {print}' f" 'a pattern, not a path, moved under the root: /^Version/'
rr() {   # rr <what> <root> <the reason, as said>
  printf '#!/bin/sh\nrm -f /var/x\n' > "$D/s"
  out=$(scratch_copy "$D/s" "$2" "$D/c"); rc=$?
  if [ $rc = 1 ] && [ ! -e "$D/c" ] && printf '%s\n' "$out" | grep -qF -- "$3"; then ok "the root refused, no copy: $1"
  else bad "the root not refused: $1 (rc $rc, [$(printf '%s' "$out" | tr '\n' ' ')])"; fi
}
mkdir -m 755 "$D/open"; ln -s /var "$D/link"; echo x > "$D/file"
rr "/" / 'not an absolute path of plain names: /'
rr "none" "" 'not an absolute path of plain names'
rr "a relative one" root 'not an absolute path of plain names: root'
rr "one with a space (the shell would split it)" "$D/a b" 'not an absolute path of plain names'
rr "one with a .." "$D/../brk/root" 'a . or .. part'
rr "one right in /tmp" /tmp/msbd-scratchroot-x 'its folder is not a real folder'
rr "one in a folder others may enter" "$D/open/root" "its folder is not this user's alone"
rr "a link (to /var)" "$D/link" 'there already and not a folder'
rr "a file" "$D/file" 'there already and not a folder'
( export SCRATCH_TOPS=var SCRATCH_ALL=var SCRATCH_ROOT=/ SCRATCH_PL=; . tools/scratch-root.sh; printf '#!/bin/sh\nrm -f /var/x /tmp/y\n' > "$D/s"
  scratch_copy "$D/s" "$R" "$D/c" >/dev/null && [ "$(sed -n 2p "$D/c")" = "rm -f $R/var/x $R/tmp/y" ] ) \
  && ok "the environment narrows nothing (SCRATCH_TOPS=var, as the first copy took it): both paths under the root" || bad "the environment changed the copy"
scratch_left "$D/no-such-copy" "$R" >/dev/null 2>&1 && bad "the check of a copy it cannot read said: none left" || ok "the check that cannot read its copy fails (never \"none left\")"
for s in preinst postinst prerm postrm; do
  n=$(scratch_left "layout/DEBIAN/$s" "$R" | wc -l | tr -d ' ')
  if scratch_copy "layout/DEBIAN/$s" "$R" "$W/$s" > "$W/left-$s" && [ "$n" -gt 0 ]; then ok "layout/DEBIAN/$s: names $n real paths as shipped, its copy none"
  else bad "layout/DEBIAN/$s: $n real paths, copy left: $(tr '\n' ' ' < "$W/left-$s")"; fi
  # (what the tests prove stays: the copy is the script with only the root put in front of its paths)
  R="$R" perl -pe 's/\Q$ENV{R}\E//g' "$W/$s" 2>/dev/null | cmp -s - "layout/DEBIAN/$s" && ok "  ... the root taken out of the copy gives layout/DEBIAN/$s back byte for byte" || bad "  ... the copy of layout/DEBIAN/$s changed more than its paths"
done
grep -qF '"/var/mobile/Library/Application Support/MacStatusBarAndDock"' layout/DEBIAN/postrm && grep -qF "\"$R/var/mobile/Library/Application Support/MacStatusBarAndDock\"" "$W/postrm" \
  && ok "  ... the postrm's purge of the sticky notes' folder goes to the scratch root (it stayed the real folder before)" || bad "  ... the sticky notes' folder is not under the scratch root in the postrm's copy"
# (the links such a test makes: each to a file of its own folder -- "$W/...", or a variable set to one -- never out of it)
links_out() {
  perl -ne 'BEGIN { local $/; open(F, "<", $ARGV[0]); my $all = <F>; close F; %own = map { $_ => 1 } $all =~ /\b([A-Za-z_][A-Za-z0-9_]*)="?\$W\//g; }
            while (/(?:^|[;&|]\s*)ln\s+-[A-Za-z]*s[A-Za-z]*\s+("?)(\S+?)\1(?:\s|$)/g) { my $x = $2; next if $x =~ m{\A\$\{?W\}?/}; next if $x =~ /\A\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?\z/ && $own{$1}; print "$x\n"; }' "$1"
}
# every test that runs one of the package's scripts makes its copy so (no sed of its own on a script of the tree, no script of the tree run as it is)
for t in tools/test-*.sh; do
  case "$t" in tools/test-scratchroot.sh) continue ;; esac
  grep -qE 'layout/DEBIAN/(preinst|postinst|prerm|postrm)' "$t" || continue
  if grep -qE 'sed[^|]*layout/DEBIAN/|(^|[;&|] *)(sh|bash) +layout/DEBIAN/|"\$\{?PWD\}?/layout/DEBIAN/|^ *layout/DEBIAN/[a-z]+ ' "$t"; then bad "$t runs or rewrites a package script itself: $(grep -nE 'sed[^|]*layout/DEBIAN/|(sh|bash) +layout/DEBIAN/' "$t" | head -2 | tr '\n' ' ')"
  elif [ -n "$(links_out "$t")" ]; then bad "$t makes a link to something not its own (in its scratch root a link could lead a script's path out): $(links_out "$t" | tr '\n' ' ')"
  elif grep -qE 'scratch_copy layout/DEBIAN/' "$t" || ! grep -qE '"\$W/(preinst|postinst|prerm|postrm)"' "$t"; then ok "$t: its copies by scratch_copy (or it only reads the scripts), its links its own"
  else bad "$t runs a copy not made by scratch_copy"; fi
done
echo "scratchroot: $pass passed, $fail failed"
[ "$fail" = 0 ]
