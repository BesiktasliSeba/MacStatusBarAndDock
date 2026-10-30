#!/bin/bash
# Mac test of RAM & CPU's tile kept in iPadOS 18's Control Center (common/CCTileKeep.h, test-cctile.m): the note, the put-back and what is never
# put back; then SpringBoard starts in a row, one process each, on files of their own: noted, dropped by a SpringBoard without our module, put back
# at the next start exactly as before; taken out by the user while our module is there (saved as a new file, or over the old one): noted as taken
# out and never put back; moved to another page: put back there.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -fobjc-arc -framework Foundation -o "$W/tcc" test-cctile.m
"$W/tcc"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
mkdir -p "$W/ControlCenter"; S="$W/ControlCenter/ControlsIconState.plist"; N="$W/note.plist"
xml() { plutil -convert xml1 -o - "$1"; }
placed() { python3 -I -c "import plistlib,sys; d=plistlib.load(open(sys.argv[1],'rb')); t=d['tiles']; print(int(d['placed']), ' '.join('%d/%d' % (x['page']+1, x['index']+1) for x in t))" "$1"; }
"$W/tcc" layout "$S"; cp "$S" "$W/original.plist"
"$W/tcc" start "$S" "$N" > "$W/o1"
check "start 1, no note yet: noted, the tile on page 1 at 15" "[ \"\$(placed '$N')\" = '1 1/15' ] && grep -q 'start: noted, placed 1: page 1 at 15 after L' '$W/o1'"
check "start 1: the layout left as it is" "cmp -s '$S' '$W/original.plist'"
"$W/tcc" layout "$S" pruned   # (a SpringBoard without our module -- safe mode, ElleKit's Safe Mode: 18 drops the tile and saves; nothing of ours runs)
check "dropped while our module was not there: the note still has it" "[ \"\$(placed '$N')\" = '1 1/15' ]"
"$W/tcc" start "$S" "$N" > "$W/o2"
check "start 2 (Turn Back On): put back, the layout exactly as before" "[ \"\$(xml '$S')\" = \"\$(xml '$W/original.plist')\" ] && grep -q 'start: 1 tile(s) put back (page 1 at 15)' '$W/o2'"
check "start 2: still noted as placed" "[ \"\$(placed '$N')\" = '1 1/15' ]"
"$W/tcc" start "$S" "$N" remove > "$W/o3"
check "start 3, the user takes it out (saved as a new file): noted as taken out" "[ \"\$(placed '$N')\" = '0 ' ] && grep -q 'saved: noted, placed 0' '$W/o3'"
"$W/tcc" start "$S" "$N" > "$W/o4"
check "start 4: not put back" "grep -q 'start: not noted as placed' '$W/o4' && ! grep -q ramcpu <(xml '$S')"
cp "$W/original.plist" "$S"
"$W/tcc" start "$S" "$N" inplace > "$W/o5"
check "start 5, added again, then taken out (saved over the old file): both noted" "grep -q 'start: noted, placed 1' '$W/o5' && grep -q 'saved: noted, placed 0' '$W/o5' && [ \"\$(placed '$N')\" = '0 ' ]"
cp "$W/original.plist" "$S"
"$W/tcc" start "$S" "$N" twice > "$W/o5b"
check "start 5b, taken out (a new file), then back (written over that new file): the watch follows the file, noted placed again" "grep -q 'saved: noted, placed 0' '$W/o5b' && [ \"\$(placed '$N')\" = '1 1/15' ]"
cp "$W/original.plist" "$S"
"$W/tcc" start "$S" "$N" move > "$W/o6"
check "start 6, moved to page 3: noted there" "[ \"\$(placed '$N')\" = '1 3/1' ]"
python3 -I -c "
import plistlib,sys
d=plistlib.load(open(sys.argv[1],'rb'))
d['iconLists']=[[i for i in p if not any(e.get('moduleIdentifier','').endswith('.ramcpu') for e in i['elements'])] for p in d['iconLists']]
plistlib.dump(d, open(sys.argv[1],'wb'), fmt=plistlib.FMT_BINARY)" "$S"
"$W/tcc" start "$S" "$N" > "$W/o7"
check "start 7, after another SpringBoard without it: back on page 3, first" "grep -q 'put back (page 3 at 1)' '$W/o7' && python3 -I -c \"import plistlib,sys; d=plistlib.load(open(sys.argv[1],'rb')); sys.exit(0 if d['iconLists'][2][0]['elements'][0]['moduleIdentifier'].endswith('.ramcpu') else 1)\" '$S'"
cp "$W/original.plist" "$S"; "$W/tcc" start "$S" "$N" > /dev/null   # (noted as placed again)
"$W/tcc" layout "$S" added   # (a SpringBoard without our module, and a tile added to that page meanwhile: ours may not fit any more)
"$W/tcc" start "$S" "$N" other > "$W/o8"
check "start 8, its page has a new tile: not put back, the note kept -- also when another file of that folder changes" "grep -q 'start: not put back: its page has a tile it did not have then' '$W/o8' && ! grep -q 'saved: noted' '$W/o8' && [ \"\$(placed '$N')\" = '1 1/15' ]"
"$W/tcc" start "$S" "$N" resave > "$W/o9"
check "start 9, the layout itself saved (our module there, the tile not): the kept note gives way" "grep -q 'saved: noted, placed 0' '$W/o9' && [ \"\$(placed '$N')\" = '0 ' ]"
cp "$W/original.plist" "$S"; "$W/tcc" start "$S" "$N" > /dev/null
"$W/tcc" start "$S" "$N" quick > "$W/o10"
check "start 10, taken out and SpringBoard gone a tenth of a second after the save: noted at once" "[ \"\$(placed '$N')\" = '0 ' ]"
# a note that is there but cannot be read at a start (code review, 30 Oct; on the iPad an I/O error -- here its permissions): not "no note" -- nothing
# put back, and not written over by a note of the layout that lost the tile; the next start that reads it puts the tile back
cp "$W/original.plist" "$S"; "$W/tcc" start "$S" "$N" > /dev/null; cp "$N" "$W/note-placed.plist"
"$W/tcc" layout "$S" pruned; cp "$S" "$W/pruned.plist"
chmod 000 "$N"; "$W/tcc" start "$S" "$N" > "$W/o11"; chmod 644 "$N"
check "start 11, the note there but not readable: nothing put back, the note kept as it is, the layout untouched" \
  "[ \$(id -u) = 0 ] || { grep -q 'start: the note is there but could not be read -- nothing put back, the note kept as it is' '$W/o11' && ! grep -q 'noted' '$W/o11' && cmp -s '$N' '$W/note-placed.plist' && cmp -s '$S' '$W/pruned.plist'; }"
"$W/tcc" start "$S" "$N" > "$W/o12"
check "start 12, the note readable again: put back, the layout exactly as before" "grep -q 'start: 1 tile(s) put back (page 1 at 15)' '$W/o12' && [ \"\$(xml '$S')\" = \"\$(xml '$W/original.plist')\" ]"
check "no layout at all: nothing written, nothing thrown" "rm -f '$S' && '$W/tcc' start '$S' '$W/n2.plist' | grep -q 'start: no layout' && [ ! -e '$S' ] && [ ! -e '$W/n2.plist' ]"
# the part that runs it: only on 18 and later, only with our module in the repository, before Control Center reads its layout
check "CCGrabber.x: started on 18 and later, once all three repository methods are taken" \
  "grep -q 'operatingSystemVersion.majorVersion >= 18 && gMSBDCCHooked == 3' ../macsettings/CCGrabber.x && awk '/^%ctor/{f=1} f&&/MSBDCCModuleRegisterWhenLoaded\\(\\)/{r=NR} f&&/MSBDCCTileKeepStart\\(/{k=NR} END{exit !(r && k && r < k)}' ../macsettings/CCGrabber.x"
# (the Mac reads every file as class 3, so the class kept is checked on the iPads -- 16.7.7 and 18.5: Foundation's atomic write made classes 1-3
#  class 4, MSBDCCTileWrite kept 1-4; here: the write makes the new file with the old one's class)
check "MSBDCCTileWrite: a file written over is made with the class the old one has" \
  "awk '/^static inline BOOL MSBDCCTileWrite/{f=1} f&&/int cls = stat\\(path.fileSystemRepresentation, &st\\) == 0 \\? MSBDCCTileClassOf\\(path\\) : 0;/{c=1} f&&/if \\(cls <= 0\\) return \\[d writeToFile:path options:NSDataWritingAtomic error:NULL\\];/{a=1} f&&/open_dprotected_np\\(tmp.fileSystemRepresentation, O_WRONLY \\| O_CREAT \\| O_EXCL \\| O_CLOEXEC, cls,/{o=1} f&&/^}/{print (c && a && o) ? \"ok\" : \"no\"; exit}' ../common/CCTileKeep.h | grep -q ok"
check "the note goes with the package (postrm), not with an update" \
  "grep -q 'MacStatusBarAndDock-CCTile.plist' ../layout/DEBIAN/postrm && awk '/if \\[ \"\\\$1\" = \"remove\" \\] \\|\\| \\[ \"\\\$1\" = \"purge\" \\]/{f=1} f&&/MacStatusBarAndDock-CCTile.plist/{print \"ok\"; exit}' ../layout/DEBIAN/postrm | grep -q ok"
[ $fails = 0 ] && echo "test-cctile: SpringBoard start checks pass" || { echo "test-cctile: SpringBoard start checks FAILED"; exit 1; }
