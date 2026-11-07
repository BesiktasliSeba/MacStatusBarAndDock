#!/bin/bash
# Mac test: never "MacDock" in a text the user reads (1.8.3.1). "MacDock" is the Dock line's library name (MacDock.dylib, as Choicy and iCleaner
# Pro list it) and another tweak's name too (com.mikiyan1978.macdock); the Dock page's switch is "Mac-Style Dock", as "Mac-Style Banners".
# What may still name it: keys and ids (the line's name "MacDock", lineName, our pref keys), file names and paths, and log lines.
# Looked at: every plist we ship (each string under a key that is not an identifier), the strings in our code outside tools/ (test-nomacdock.py),
# the line switch's alerts (they name a line by its title, not its name), the crash guard's words (crashmap-rules.txt titles) and the control file.
set -e
cd "$(dirname "$0")/.."
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }

check "no plist of ours shows MacDock (labels, footers, titles, list titles; lineName, key, id and the like may name it)" \
  "git ls-files '*.plist' | grep -v -E '^(tools|packages)/' | python3 -I tools/test-nomacdock.py plists"
check "no string in our code shows MacDock (the line's name \"MacDock\", file names and paths, log lines and focus-lock reasons may name it)" \
  "git ls-files '*.m' '*.x' '*.xm' '*.mm' '*.h' '*.c' | grep -v -E '^(tools|packages)/' | python3 -I tools/test-nomacdock.py code"

# the line switch's alerts name a line by its title ("Mac-Style Dock" for the Dock's), never by its name
L=common/LineSwitch.h
awk '/^static void MSBDSetLine\(/,/^}/' $L > "$W/setline"
check "the line switch's alerts (Could Not Change, Respring to Finish, both pages off) name the line by its title: the Dock's is \"Mac-Style Dock\"" \
  "grep -q 'static inline NSString \\*MSBDLineTitle(NSString \\*line) { return \\[line isEqualToString:@\"MacDock\"\\] ? @\"Mac-Style Dock\" : line; }' $L \
   && grep -q '@\"Choicy still keeps %@ %@. Check Choicy.s settings for SpringBoard.\", MSBDLineTitle(line),' \$W/setline \
   && grep -q 'stringWithFormat:@\"%@ turns on after a respring.\", MSBDLineTitle(line)\\]' \$W/setline \
   && grep -q 'stringWithFormat:@\"%@ turns off after a respring.\", MSBDLineTitle(line)\\]' \$W/setline \
   && grep -q 'both pages leave Settings. To turn them back on, use %@.\", MSBDLineTitle(other),' \$W/setline \
   && ! grep -E 'stringWithFormat:|stringByAppendingFormat:' \$W/setline | grep -q -E '\", (line|other)[],]'"

check "Settings > Dock: the switch at the top reads \"Mac-Style Dock\"; its line is still \"MacDock\" (Choicy's and iCleaner Pro's name for it)" \
  "plutil -convert json -o - dock/dockmagnificationprefs/Resources/Root.plist | python3 -I -c 'import json,sys; it=json.load(sys.stdin)[\"items\"]; r=[x for x in it if x.get(\"id\")==\"MSBD_LINE\"]; sys.exit(0 if len(r)==1 and r[0].get(\"label\")==\"Mac-Style Dock\" and r[0].get(\"lineName\")==\"MacDock\" else 1)'"

check "the crash guard's words name no part MacDock (crashmap-rules.txt titles: \"SpringBoard crashed twice in the Dock, so the Dock was turned off for now.\")" \
  "grep -qx 'title DockMagnification the Dock|the Dock' tools/crashmap-rules.txt && ! grep -E '^title ' tools/crashmap-rules.txt | grep -q 'MacDock'"

check "the package's name and description, as Sileo shows them, name no MacDock" "! grep -E '^(Name|Description|Author|Maintainer):' control | grep -q 'MacDock'"

[ $fails = 0 ] && echo "test-nomacdock: all checks pass" || { echo "test-nomacdock: FAILED"; exit 1; }
