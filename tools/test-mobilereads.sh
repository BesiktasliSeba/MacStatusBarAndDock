#!/bin/bash
# test-mobilereads.sh: the root helper reads mobile's files as mobile, and only plain files (1.8.7.5, audit L22 of 1.8.7.2). sshtoggled read
# Choicy's settings, our records of our changes in them, the engines' saved settings, the old packages' preference files and Control Center's lists
# as root, then wrote what it read, or what it made of it, back where mobile reads it: a hostile process running as mobile could swap one for a
# link to a file only root may read and have it published (disclosure only). The postinst's copy of the prewarm quit set (a cp as root) the same.
# Now one reader (MobileFileData, MobilePlist): O_NOFOLLOW, O_NONBLOCK, fstat S_ISREG, read from that descriptor, inside AsMobile; the quit set's
# copy is the helper's (--quit-set-copy). The reads that only decide something are left as they were.
# 1. test-mobilereads.m on the real reader cut out of main.m (MR_SSH_M: another copy; without the reader, the reads as they were);
# 2. site checks: every read of a mobile file whose contents are written back goes through it; 3. made-to-fail copies.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
M0=${MR_SSH_M:-../macsettings/sshtoggled/main.m}
fn() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }   # one function of a file, from its first line
reader() {   # $1 main.m: the reader and the quit set's copy, or (the code before the fix) the reads as they were
  if grep -q '^static NSData \*MobileFileData(NSString \*path) {' "$1"; then
    fn "$1" 'static BOOL AsMobile(BOOL (^work)(void)) {'; grep '^#define kMobileFileLimit ' "$1"
    fn "$1" 'static NSData *MobileFileData(NSString *path) {'; fn "$1" 'static NSDictionary *MobilePlist(NSString *path) {'
    grep '^#define QUITSETPREFS ' "$1"; fn "$1" 'static int CopyQuitSetForDasd(void) {'
  else
    echo 'static NSData *MobileFileData(NSString *p) { return [NSData dataWithContentsOfFile:p]; }   // (before the fix: each site read so, as root)'
    echo 'static NSDictionary *MobilePlist(NSString *p) { return [NSDictionary dictionaryWithContentsOfFile:p]; }'
  fi
}

compiled() {   # $1 main.m, $2 quiet: the cases built on its reader and run, bounded (20 s); 0 when every check passes
  local d=$W/c$RANDOM; mkdir -p "$d/dir"
  reader "$1" > "$d/reader.inc"
  local copy=""; grep -q 'CopyQuitSetForDasd' "$d/reader.inc" && copy=-DMR_COPY=1
  if ! clang -fobjc-arc -Wall -Wno-unused-function -Wno-deprecated-declarations $copy -I"$d" -DMR_DIR="\"$d/dir\"" -framework Foundation -o "$d/t" test-mobilereads.m > "$d/build.txt" 2>&1; then
    [ -n "$2" ] || { echo "(test-mobilereads.m does not build against $1:)"; grep -m 3 'error:' "$d/build.txt"; }; return 1
  fi
  "$d/t" > "$d/out.txt" 2>&1 &
  local p=$! i=0
  while kill -0 $p 2>/dev/null && [ $i -lt 200 ]; do sleep 0.1; i=$((i + 1)); done
  if kill -0 $p 2>/dev/null; then kill -9 $p 2>/dev/null; wait $p 2>/dev/null; [ -n "$2" ] || { cat "$d/out.txt"; echo "  FAIL BLOCKED: the read did not return in 20 s (stopped)"; }; return 1; fi
  wait $p; local r=$?
  [ -n "$2" ] || cat "$d/out.txt"
  return $r
}

# the functions whose reads of mobile's files are written back (as mobile) where mobile reads them, and how many reads each makes
ROUTED='GiveBackDomain:static BOOL GiveBackDomain(NSString *dir, NSString *domain, NSString *notifyName) {:1
CopyAsMobile:static void CopyAsMobile(NSString *from, NSString *to) {:1
GiveBackChoicyEngines:static void GiveBackChoicyEngines(void) {:2
GiveBackChoicyEntriesOf:static void GiveBackChoicyEntriesOf(NSArray<NSString *> *libs, NSString *why) {:2
ChoicyApplyChoices:static void ChoicyApplyChoices(NSString *why) {:2
MigratePrefFiles:static void MigratePrefFiles(void) {:1
MigrateChoicy:static NSSet<NSString *> *MigrateChoicy(void) {:2
Migrate:static void Migrate(void) {:0
MigrateOldOnOff (the old on/off, from Migrate):static void MigrateOldOnOff(void) {:2
TakeOurControlsOut:static void TakeOurControlsOut(void) {:1
Uninstall:static void Uninstall(void) {:2
CopyQuitSetForDasd:static int CopyQuitSetForDasd(void) {:1'
sites() {   # $1 main.m, $2 quiet; the number of failed checks
  local M=$1 q=$2 n=0
  c() { if (eval "$2") >/dev/null 2>&1; then [ -n "$q" ] || echo "PASS  $1"; else [ -n "$q" ] || echo "FAIL  $1"; n=$((n + 1)); fi; }
  c "the reader: O_NOFOLLOW and O_NONBLOCK, a regular file by fstat, read from that descriptor, all as mobile (inside AsMobile)" \
    "fn $M 'static NSData *MobileFileData(NSString *path) {' > \$W/mfd && grep -qF '    AsMobile(^BOOL{' \$W/mfd \
     && grep -qF 'int fd = open(path.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);' \$W/mfd \
     && grep -qF 'if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode) || st.st_size > kMobileFileLimit) { odd = YES; close(fd); return NO; }' \$W/mfd \
     && grep -qF 'ssize_t n = read(fd, (char *)d.mutableBytes + have, d.length - have);' \$W/mfd && ! grep -q 'ContentsOfFile' \$W/mfd"
  local IFS_=$IFS line name head want got
  while IFS= read -r line; do
    name=${line%%:*}; head=${line#*:}; want=${head##*:}; head=${head%:*}
    c "$name: its reads of mobile's files through the reader ($want), none of its own (its own folder's, MIGDIR, as root as before)" \
      "fn $M '$head' > \$W/f && [ -s \$W/f ] && ! grep 'ContentsOfFile' \$W/f | grep -vq '@MIGDIR' && [ \$(grep -o 'MobilePlist(\\|MobileFileData(' \$W/f | wc -l) -eq $want ]"
  done <<EOF
$ROUTED
EOF
  c "the quit set's copy: --quit-set-copy runs it (the postinst asks it, test-postinst.sh)" \
    "grep -qF 'if (argc > 1 && strcmp(argv[1], \"--quit-set-copy\") == 0) return CopyQuitSetForDasd();' $M"
  c "no read of Choicy's settings or our records as root left but those that only decide (the engines' default, the switch-off watcher, the debug dry run)" \
    "! grep -q 'ContentsOfFile:@CHOICYPREFS\\|ContentsOfFile:@CHOICYRECORD\\|ContentsOfFile:@LINERECORD' $M \
     && [ \$(grep -c 'ContentsOfFile:kMSBDExChoicyPrefs\\|ContentsOfFile:@PREFSDIR \"/com.opa334.choicyprefs.plist\"' $M) = 2 ] \
     && fn $M 'static NSString *EngineToKeep(NSString *status, BOOL *windowing, BOOL *picked) {' | grep -q 'ContentsOfFile:kMSBDExChoicyPrefs' \
     && fn $M 'static BOOL MacStatusBarSwitchedOff(NSString *status, NSString **how) {' | grep -q 'ContentsOfFile:@PREFSDIR'"
  return $n
}

rc=0
if compiled "$M0"; then echo "PASS  the cases (test-mobilereads.m against $M0)"; else echo "FAIL  the cases (test-mobilereads.m against $M0)"; rc=1; fi
sites "$M0" || rc=1
if [ -z "$MR_SSH_M" ]; then
  mtf() {   # $1 name, $2 what must catch it (cases|sites), $3 a filter on main.m (stdin to stdout) that takes one part of the fix out
    "$3" < "$M0" > "$W/m.m"
    if cmp -s "$W/m.m" "$M0"; then echo "FAIL  made-to-fail ($1): the copy did not change"; rc=1; return; fi
    if [ "$2" = cases ]; then if compiled "$W/m.m" quiet; then echo "FAIL  made-to-fail ($1): the cases still pass"; rc=1; else echo "PASS  made-to-fail ($1): caught by the cases"; fi
    else if sites "$W/m.m" quiet; then echo "FAIL  made-to-fail ($1): the site checks still pass"; rc=1; else echo "PASS  made-to-fail ($1): caught by the site checks"; fi; fi
  }
  follow() { sed -e 's/O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC/O_RDONLY | O_NONBLOCK | O_CLOEXEC/'; }
  block() { sed -e 's/O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC/O_RDONLY | O_NOFOLLOW | O_CLOEXEC/'; }
  any_kind() { sed -e 's/if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode) || st.st_size > kMobileFileLimit)/if (fstat(fd, \&st) != 0 || st.st_size > kMobileFileLimit)/'; }
  copy_link() { sed -e 's/    if (Exists(@kMSBDPrewarmQuitSetFile)) return 1;/    if (access(kMSBDPrewarmQuitSetFile, F_OK) == 0) return 1;/'; }
  site_back() { sed -e 's/    NSMutableDictionary \*record = \[MobilePlist(@CHOICYRECORD) mutableCopy\];/    NSMutableDictionary *record = [[NSDictionary dictionaryWithContentsOfFile:@CHOICYRECORD] mutableCopy];/'; }
  copy_back() { sed -e 's/            NSData \*data = MobileFileData(from);/            NSData *data = [NSData dataWithContentsOfFile:from];/'; }
  mtf "links followed (no O_NOFOLLOW)" cases follow
  mtf "a fifo waited on (no O_NONBLOCK)" cases block
  mtf "any kind of file read (no S_ISREG)" cases any_kind
  mtf "the quit set's copy writing through a link at dasd's file" cases copy_link
  mtf "GiveBackChoicyEntriesOf's record read as root again" sites site_back
  mtf "MigratePrefFiles' copy read as root again" sites copy_back
fi
[ $rc = 0 ] && echo "test-mobilereads: all pass" || echo "test-mobilereads: FAILED"
exit $rc
