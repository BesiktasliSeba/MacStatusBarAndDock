#!/bin/bash
# Mac test (1.8.9 RC 2, KT 26 Nov: Settings crashed opening Status Bar > Mac Lock Screen): every settings page we ship has each specifier key
# in the type iPadOS's Preferences reads it as (test-prefsplisttypes.py says which and how it was measured on 15.6.1, 16.7.7, 17.5.1, 18.5),
# names cells, classes and methods that exist, and our code sets no literal of the wrong type on a specifier. It fails on RC 1's
# MacLockScreen.plist (autoCaps <integer>0</integer>) and on each kind of mistake below.
set -e
cd "$(dirname "$0")/.."
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
SRC="statusbar/macstatusbarprefs dock/dockmagnificationprefs common"
T="python3 -I tools/test-prefsplisttypes.py $SRC --"
# every plist we ship that is a settings page (a root dictionary with items), wherever it is: a new page is checked without being listed here
find . \( -path ./tools -o -path ./packages -o -path ./third_party -o -path ./.theos -o -path ./.git \) -prune -o -name '*.plist' -print | sort > "$W/all"
: > "$W/pages"
while read -r f; do
  plutil -convert json -o - "$f" 2>/dev/null | python3 -I -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if isinstance(d, dict) and isinstance(d.get("items"), list) else 1)' && echo "$f" >> "$W/pages"
done < "$W/all"
check "the settings pages are found by what they are: the five Status Bar bundle pages and the Dock page (and any new one)" \
  "grep -q 'macstatusbarprefs/Resources/MacLockScreen.plist' $W/pages && grep -q 'dockmagnificationprefs/Resources/Root.plist' $W/pages && [ \$(wc -l < $W/pages) -ge 6 ]"
check "every settings page we ship: each key in the type Preferences reads it as, real cells, classes and methods (iPadOS 15-18)" \
  "$T \$(cat $W/pages)"
check "our code that makes or changes specifiers (the pages, the Settings rows, the search) sets no literal of the wrong type on a key" \
  "python3 -I tools/test-prefsplisttypes.py --code \$(find statusbar/macstatusbarprefs dock/dockmagnificationprefs statusbar/macstatusbarsettings dock/dockmagnificationsettings macsettings common \\( -name '*.m' -o -name '*.x' -o -name '*.xm' -o -name '*.h' \\) | sort)"
check "  ... and Mac Lock Screen's Name field asks for no capitals as a string (None), with autocorrection off" \
  "plutil -convert json -o - statusbar/macstatusbarprefs/Resources/MacLockScreen.plist | python3 -I -c 'import json,sys; it=[x for x in json.load(sys.stdin)[\"items\"] if x.get(\"id\")==\"MLS_NAME\"]; sys.exit(0 if len(it)==1 and it[0].get(\"autoCaps\")==\"None\" and it[0].get(\"noAutoCorrect\") is True and it[0].get(\"cell\")==\"PSEditTextCell\" else 1)'"

# made to fail: RC 1's plist, and one mistake of each kind in a copy of the real page
M=statusbar/macstatusbarprefs/Resources/MacLockScreen.plist
plutil -convert xml1 -o "$W/rc1.plist" "$M"
perl -0pi -e 's#(<key>autoCaps</key>\s*)<string>None</string>#${1}<integer>0</integer>#' "$W/rc1.plist"
check "made to fail: 1.8.9 RC 1's MacLockScreen.plist (autoCaps <integer>0</integer>) is caught, at the Name field" \
  "! $T $W/rc1.plist > $W/rc1.out && grep -q 'MLS_NAME): autoCaps is int, not a string (Preferences throws while the page loads)' $W/rc1.out"
if git cat-file -e 2bb83a521391540a880ea327fc353fd78ccd6137:$M 2>/dev/null; then
  git show 2bb83a521391540a880ea327fc353fd78ccd6137:$M > "$W/rc1git.plist"
  check "  ... the very file RC 1 shipped (2bb83a52, from git)" "! $T $W/rc1git.plist > $W/rc1git.out && grep -q 'autoCaps is int' $W/rc1git.out"
fi
bad() {   # bad <name> <python that changes it (the Name field: n, the items: items)> <the line it must print>
  plutil -convert json -o - "$M" | python3 -I -c "
import json, plistlib, sys
d = json.load(sys.stdin); items = d['items']; n = [x for x in items if x.get('id') == 'MLS_NAME'][0]
$2
plistlib.dump(d, open(sys.argv[1], 'wb'))" "$W/$1.plist"
  check "made to fail: $1" "! $T $W/$1.plist > $W/$1.out && grep -q -F \"$3\" $W/$1.out"
}
bad keyboard-number "n['keyboard'] = 2" "keyboard is int, not a string (Preferences throws"
bad cell-number "n['cell'] = 8" "cell is int, not a string"
bad autocaps-capital "n['autoCaps'] = 'Words'" "autoCaps 'Words' is read as no capitals"
bad keyboard-capital "n['keyboard'] = 'Numbers'" "keyboard 'Numbers' gives the plain keyboard"
bad isip-array "n['isIP'] = ['x']" "isIP is list, not <true/> / <false/>"
bad label-number "n['label'] = 3" "label is int, not a string"
bad unknown-key "n['autoCorrect'] = False" "key autoCorrect is not in this test's list"
bad text-default "n['default'] = 0" "a text field's default is int, not a string"
bad cell-unknown "n['cell'] = 'PSEditCell'" "cell 'PSEditCell' is not one of Preferences' cell types"
bad no-class "[x for x in items if x.get('id') == 'MLS_CLOCK'][0]['detail'] = 'MSBNoSuchController'" "detail MSBNoSuchController is no class of our pages"
bad no-method "[x for x in items if x.get('id') == 'MLS_PICK'][0]['action'] = 'msb_noSuchPicker:'" "action msb_noSuchPicker: is no method of our pages"
bad titles-count "[x for x in items if x.get('id') == 'MLS_CLOCK'][0]['validTitles'].append('Extra')" "validValues but"
bad values-string "[x for x in items if x.get('id') == 'MLS_CLOCK'][0]['validValues'] = 'mac'" "validValues is not an array of plain values"
bad list-default "c = [x for x in items if x.get('id') == 'MLS_CLOCK'][0]; c['default'] = 'nosuch'" "default 'nosuch' is not one of its validValues"
bad switch-default "[x for x in items if x.get('cell') == 'PSSwitchCell'][0]['default'] = 1" "a switch's default is int, not <true/> / <false/>"
printf '%s\n' '[sp setProperty:@0 forKey:@"autoCaps"];' '[sp setProperty:@"YES" forKey:@"enabled"];' '[sp setProperty:@YES forKey:@"enabled"];' > "$W/c.m"
check "made to fail: code setting @0 as autoCaps and @\"YES\" as enabled (2 lines; @YES as enabled is right)" \
  "! python3 -I tools/test-prefsplisttypes.py --code $W/c.m > $W/c.out && [ \$(wc -l < $W/c.out) = 2 ] && grep -q 'c.m:1: autoCaps set to @0' $W/c.out && grep -q 'c.m:2: enabled set to the string' $W/c.out"
exit $fails
