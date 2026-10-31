#!/bin/bash
# Mac test of the prewarm block's build ID and start stamp (common/PrewarmPartID.h, test-prewarmpartid.c, tools/prewarm-part-id.sh; 1.7.2 item 8):
# the install restarts dasd only when it does not have the block just installed -- a dasd started again costs the M1 10 to 26 minutes of CPU.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -o "$W/tpp" test-prewarmpartid.c
"$W/tpp"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
# the build ID: the same sources give the same ID wherever they are built; any change to them, or the other build kind, gives another
d1=$(./prewarm-part-id.sh ../prewarmblock d); r1=$(./prewarm-part-id.sh ../prewarmblock r)
check "the ID: 16 lower-case hex digits, debug and release different" "[[ '$d1' =~ ^[0-9a-f]{16}$ ]] && [[ '$r1' =~ ^[0-9a-f]{16}$ ]] && [ '$d1' != '$r1' ]"
mkdir -p "$W/tree/prewarmblock" "$W/tree/common" "$W/tree/tools"
cp ../prewarmblock/* "$W/tree/prewarmblock/"; cp ../common/*.h "$W/tree/common/"; cp prewarm-part-id.sh "$W/tree/tools/"
check "the same sources in another folder (another worktree): the same ID" "[ \"\$('$W/tree/tools/prewarm-part-id.sh' '$W/tree/prewarmblock' d)\" = '$d1' ]"
check "  ... run from the part's own folder as its Makefile does: the same ID" "[ \"\$(cd '$W/tree/prewarmblock' && ../tools/prewarm-part-id.sh . d)\" = '$d1' ]"
echo '// a change' >> "$W/tree/common/PrewarmQuitSet.h"
check "a header the part includes (common/PrewarmQuitSet.h) changed: another ID" "[ \"\$('$W/tree/tools/prewarm-part-id.sh' '$W/tree/prewarmblock' d)\" != '$d1' ]"
cp ../common/PrewarmQuitSet.h "$W/tree/common/"; echo '// a change' >> "$W/tree/common/PrewarmPartID.h"
check "the stamp's header changed: another ID" "[ \"\$('$W/tree/tools/prewarm-part-id.sh' '$W/tree/prewarmblock' d)\" != '$d1' ]"
cp ../common/PrewarmPartID.h "$W/tree/common/"; echo '# a change' >> "$W/tree/prewarmblock/Makefile"
check "the part's Makefile changed: another ID" "[ \"\$('$W/tree/tools/prewarm-part-id.sh' '$W/tree/prewarmblock' d)\" != '$d1' ]"
cp ../prewarmblock/Makefile "$W/tree/prewarmblock/"; echo '// a change' >> "$W/tree/common/DockTrash.h"
check "a header the part does not include changed: the same ID (that install leaves dasd running)" "[ \"\$('$W/tree/tools/prewarm-part-id.sh' '$W/tree/prewarmblock' d)\" = '$d1' ]"
printf '#include "../common/DockTrash.h"\n' >> "$W/tree/prewarmblock/PrewarmShape.h"
check "  ... once an included file includes it (followed through), it counts: another ID" "[ \"\$('$W/tree/tools/prewarm-part-id.sh' '$W/tree/prewarmblock' d)\" != '$d1' ]"
printf '#include "../common/NoSuchHeader.h"\n' >> "$W/tree/prewarmblock/PrewarmShape.h"
check "an include that is not there: no ID (the build stops)" "! '$W/tree/tools/prewarm-part-id.sh' '$W/tree/prewarmblock' d >/dev/null 2>&1"
check "a build kind other than d or r: refused" "! ./prewarm-part-id.sh ../prewarmblock x >/dev/null 2>&1"
# the wiring as built
mk1='MSBD_DASD_PART_ID := $(shell ../tools/prewarm-part-id.sh . $(if $(findstring DEBUG,$(THEOS_SCHEMA)),d,r))'
mk2="-DMSBD_DASD_PART_ID='\"\$(MSBD_DASD_PART_ID)\"'"
mk3='$(error the prewarm block'
check "the Makefile: the ID from the script, by the build kind, compiled in; no ID stops the build" \
  'grep -qF -- "$mk1" ../prewarmblock/Makefile && grep -qF -- "$mk2" ../prewarmblock/Makefile && grep -qF -- "$mk3" ../prewarmblock/Makefile'
# (the schema the top-level make exports: _THEOS_ON_SCHEMA is set only there, and read in the part's make it gave debug builds the release ID --
#  1.7.2~a02 on the M1 carried 16c179b1..., the release ID, in a debug part)
check "  ... the build kind read from THEOS_SCHEMA (exported to the part's make), never _THEOS_ON_SCHEMA (empty there)" \
  "! grep -n '_THEOS_ON_SCHEMA' ../prewarmblock/Makefile | grep -v '^[0-9]*:#'"
st1='want=$$(tools/prewarm-part-id.sh prewarmblock $(if $(findstring DEBUG,$(_THEOS_ON_SCHEMA)),d,r));'
st2='got=$$(strings -a "$$P/PrewarmBlockTweak.dylib" | sed -n'
check "the top Makefile: the ID in the part it packages is checked against this tree and build kind (a stale or wrong part stops the build)" \
  'grep -qF -- "$st1" ../Makefile && grep -qF -- "$st2" ../Makefile && grep -q "the prewarm block.s build ID is" ../Makefile'
check "the part: the marker with the ID kept in the binary; the stamp written once armed" \
  "grep -q '__attribute__((used)) static const char kPartMark\\[\\] = kMSBDPrewarmPartMarker MSBD_DASD_PART_ID;' ../prewarmblock/PrewarmBlock.x && awk '/gArmed = YES;/{a=1; next} a{print; exit}' ../prewarmblock/PrewarmBlock.x | grep -q 'WriteLoadedStamp();'"
check "  ... the stamp replaced in one rename (never half a line), its own pid and start time from the system" \
  "awk '/^static void WriteLoadedStamp/{f=1} f&&/KERN_PROC_PID, getpid\\(\\)/{k=1} f&&/rename\\(kMSBDPrewarmLoadedFile \".new\", kMSBDPrewarmLoadedFile\\)/{r=1} f&&/^}/{print (k && r) ? \"ok\" : \"no\"; exit}' ../prewarmblock/PrewarmBlock.x | grep -q ok"
check "  ... and not written by a part its crash guard switched off (it returns before arming)" \
  "awk '/^%ctor/{f=1} f&&/if \\(SelfDisabledByCrashLoop\\(\\)\\) return;/{c=1} f&&/WriteLoadedStamp\\(\\);/{print c ? \"ok\" : \"no\"; exit}' ../prewarmblock/PrewarmBlock.x | grep -q ok"
check "the helper: --dasd-part-current answers 0 only from MSBDPrewarmPartCurrent on the stamp, the process at its pid and the installed part's ID" \
  "grep -q 'strcmp(argv\\[1\\], \"--dasd-part-current\") == 0) return DasdPartCurrent() ? 0 : 1;' ../macsettings/sshtoggled/main.m && awk '/^static BOOL DasdPartCurrent\\(void\\)/{f=1} f&&/KERN_PROC_PID/{k=1} f&&/MSBDPrewarmPartIDIn\\(part.bytes/{i=1} f&&/return MSBDPrewarmPartCurrent\\(stamp, run, iid\\) != 0;/{print (k && i) ? \"ok\" : \"no\"; exit}' ../macsettings/sshtoggled/main.m | grep -q ok"
check "the postinst: dasd killed unless the helper says it has the block just installed" \
  "grep -q 'if \\[ -x \"\$H\" \\] && \"\$H\" --dasd-part-current; then :; else /var/jb/usr/bin/killall -9 dasd 2>/dev/null; fi' ../layout/DEBIAN/postinst && [ \$(grep -c 'killall -9 dasd' ../layout/DEBIAN/postinst) = 1 ]"
check "the postrm: the stamp goes; dasd is still restarted on removal (our code leaves it)" \
  "grep -q 'MacStatusBarAndDock-PrewarmBlockLoaded.txt' ../layout/DEBIAN/postrm && grep -q 'killall -9 dasd' ../layout/DEBIAN/postrm"
[ $fails = 0 ] && echo "test-prewarmpartid: wiring checks pass" || { echo "test-prewarmpartid: wiring checks FAILED"; exit 1; }
