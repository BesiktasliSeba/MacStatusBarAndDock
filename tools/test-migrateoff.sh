#!/bin/bash
# test-migrateoff.sh: the old separate packages' "switched off" moved to a line switch also when Choicy has no settings file yet (1.8.7.5, audit
# L106 of 1.8.7.2). The old MacStatusBarToggle / DockMagnificationToggle entries wrote tweakEnabled = NO; the migration (sshtoggled --migrate, once,
# from the postinst) switches that line off in Choicy (or iCleaner Pro) instead, where the switch at the top of its Settings page shows it, and
# clears tweakEnabled. With Choicy installed but never configured there is no settings file, and the migration only edited an existing one: the
# part stayed off the old way, which only the parts read (StatusBar.x, Dock.x), for good, while Settings showed it on. Now a missing file starts
# from preferenceVersion 1, as ChoicyApplyChoices starts it; a file that is there but can't be read is still left alone. And the move (MigrateOldOnOff)
# is looked at again at every later install (Migrate's "done before" path): a device migrated up to 1.8.7.4 with the part left off so is repaired by
# the update (the review of the L106 fix), where it would have stayed so for good behind the "migrated" marker.
# 1. test-migrateoff.m on the real move and the real Migrate cut out of main.m (MO_SSH_M: another copy of main.m, e.g. the code before the fix);
# 2. site checks; 3. made-to-fail copies: each takes one part of the fix out and must fail.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
M0=${MO_SSH_M:-../macsettings/sshtoggled/main.m}
fn() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }   # one function of a file, from its first line
LOOP='    // the old separate on/off entries (MacStatusBarToggle / DockMagnificationToggle) wrote tweakEnabled = NO; the lines replace them'
loop() { awk -v h="$LOOP" 'index($0, h) == 1 {f=1} f && index($0, "    [@\"1\" writeToFile:@MIGDIR \"/migrated\"") == 1 {exit} f {print}' "$1"; }   # (the code before: the move inside Migrate)
has() { awk -v h="$2" 'index($0, h) == 1 {f=1} END {exit !f}' "$1"; }   # the file has a line that starts so
ONOFF='static void MigrateOldOnOff(void) {'
onoff() {   # $1 main.m: the old on/off move as a function (the code before: the loop cut out of Migrate, made one)
  if has "$1" "$ONOFF"; then fn "$1" "$ONOFF"; else echo "$ONOFF"; loop "$1"; echo '}'; fi
}

compiled() {   # $1 main.m, $2 quiet: the scenarios built on its loop and run; 0 when every check passes
  local d=$W/c$RANDOM; mkdir -p "$d"
  onoff "$1" > "$d/onoff.inc"; fn "$1" 'static void Migrate(void) {' > "$d/migrate.inc"
  fn "$1" 'static void RecordLineChange(NSMutableDictionary *record, NSString *listKey, NSString *entry) {' > "$d/record.inc"
  { grep '^#define kMobileFileLimit ' "$1"; fn "$1" 'static NSData *MobileFileData(NSString *path) {'; fn "$1" 'static NSDictionary *MobilePlist(NSString *path) {'; } > "$d/reader.inc"
  if ! [ -s "$d/onoff.inc" ] || ! [ -s "$d/migrate.inc" ] || ! clang -fobjc-arc -Wall -Wno-unused-function -I"$d" -DMO_DIR="\"$d/dir\"" -framework Foundation -o "$d/t" test-migrateoff.m > "$d/build.txt" 2>&1; then
    [ -n "$2" ] || { echo "(test-migrateoff.m does not build against $1:)"; grep -m 3 'error:' "$d/build.txt"; }; return 1
  fi
  if [ -n "$2" ]; then "$d/t" > /dev/null 2>&1; else "$d/t"; fi
}

move_sites() {   # $1 main.m
  fn "$1" 'static void Migrate(void) {' > "$W/mig"
  grep -qxF '    if (Exists(@MIGDIR "/migrated")) { MigrateOldOnOff(); ELog(@"migrate: done before -- nothing else to do"); return; }   // (the old on/off: also after the move, below)' "$W/mig" || return 1
  [ "$(grep -c 'MigrateOldOnOff();' "$W/mig")" = 2 ] || return 1
  local a b; a=$(grep -nxF '    MigrateOldOnOff();' "$W/mig" | cut -d: -f1); b=$(grep -nF '    [@"1" writeToFile:@MIGDIR "/migrated"' "$W/mig" | cut -d: -f1)
  [ -n "$a" ] && [ -n "$b" ] && [ "$b" = $((a + 1)) ] && ! grep -q 'tweakEnabled' "$W/mig"
}

sites() {   # $1 main.m, $2 quiet; the number of failed checks
  local M=$1 q=$2 n=0
  c() { if (eval "$2") >/dev/null 2>&1; then [ -n "$q" ] || echo "PASS  $1"; else [ -n "$q" ] || echo "FAIL  $1"; n=$((n + 1)); fi; }
  c "a missing Choicy file starts from preferenceVersion 1, only when it is not there (access), before the edit" \
    "onoff $M | awk '/if \\(!prefs && access\\(CHOICYPREFS, F_OK\\) != 0\\) \\{/{a=NR} /prefs = \\[NSMutableDictionary dictionaryWithObject:@1 forKey:@\"preferenceVersion\"\\];/{b=NR} /if \\(prefs\\) \\{/{c=NR} END{exit !(a && b == a + 1 && c > b)}'"
  c "  ... the same start as ChoicyApplyChoices'" \
    "fn $M 'static void ChoicyApplyChoices(NSString *why) {' | grep -qF 'prefs = [NSMutableDictionary dictionaryWithObject:@1 forKey:@\"preferenceVersion\"];'"
  c "  ... both files written as mobile, tweakEnabled cleared only when that worked" \
    "onoff $M | grep -qF 'done = AsMobile(^BOOL{ return [record writeToFile:@LINERECORD atomically:YES] && [prefs writeToFile:@CHOICYPREFS atomically:YES]; });' \
     && onoff $M | grep -qxF '        if (done) WriteMobilePrefsKey(p[0], @\"tweakEnabled\", nil, NO);'"
  c "the move runs in Migrate at a first migration, before its \"migrated\" marker, and at every later install (its \"done before\" path)" "move_sites $M"
  return $n
}

rc=0
if compiled "$M0"; then echo "PASS  the scenarios (test-migrateoff.m against $M0)"; else echo "FAIL  the scenarios (test-migrateoff.m against $M0)"; rc=1; fi
sites "$M0" || rc=1
if [ -z "$MO_SSH_M" ]; then
  mtf() {   # $1 name, $2 a filter on main.m (stdin to stdout) that takes one part of the fix out
    "$2" < "$M0" > "$W/m.m"
    if cmp -s "$W/m.m" "$M0"; then echo "FAIL  made-to-fail ($1): the copy did not change"; rc=1; return; fi
    if compiled "$W/m.m" quiet && sites "$W/m.m" quiet; then echo "FAIL  made-to-fail ($1): still passes"; rc=1
    elif compiled "$W/m.m" quiet; then echo "FAIL  made-to-fail ($1): caught by the site checks only"; rc=1
    else echo "PASS  made-to-fail ($1): caught by the scenarios"; fi
  }
  no_start() { awk '/^            if \(!prefs && access\(CHOICYPREFS, F_OK\) != 0\) \{$/ {s=1; next} s && /^            \}$/ {s=0; next} !s'; }
  any_nil() { sed -e 's/            if (!prefs \&\& access(CHOICYPREFS, F_OK) != 0) {/            if (!prefs) {/'; }
  no_version() { awk '/^            if \(!prefs && access\(CHOICYPREFS, F_OK\) != 0\) \{$/ {s=1} s && /dictionaryWithObject:@1 forKey:@"preferenceVersion"\];/ {sub(/\[NSMutableDictionary dictionaryWithObject:@1 forKey:@"preferenceVersion"\]/, "[NSMutableDictionary dictionary]"); s=0} {print}'; }
  no_repair() { sed -e 's/    if (Exists(@MIGDIR "\/migrated")) { MigrateOldOnOff(); ELog(@"migrate: done before -- nothing else to do"); return; }/    if (Exists(@MIGDIR "\/migrated")) { ELog(@"migrate: done before -- nothing else to do"); return; }/'; }
  mtf "a move left undone before not repaired at a later install" no_repair
  mtf "a missing file not started" no_start
  mtf "an unreadable file replaced too" any_nil
  mtf "the new file without preferenceVersion" no_version
fi
[ $rc = 0 ] && echo "test-migrateoff: all pass" || echo "test-migrateoff: FAILED"
exit $rc
