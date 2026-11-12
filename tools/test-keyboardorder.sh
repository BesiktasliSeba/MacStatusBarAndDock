#!/bin/bash
# Mac test of Settings > Keyboard's order (KT 12 Nov, 1.8.7): top to bottom, your own shortcuts -- KeyPilot's row first while it is installed, then
# Custom Shortcuts --, Window Tiling Shortcuts, the five Mac key switches (their footer and its Modifier Keys link), then Apple's Hardware Keyboard
# rows; on iPadOS 18 the same order in our block at the top of Apple's Hardware Keyboard page, Mac Keys last. Site checks of
# macsettings/KeyboardSettings.x and AppleGroups18.x, then made-to-fail copies (the old order, and each part of it put back) that must fail them.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
KB=../macsettings/KeyboardSettings.x; G=../macsettings/AppleGroups18.x
fn() { awk -v head="$1" 'index($0, head) == 1 {f=1} f {print} f && /^}/ {exit}' "$2" > "$W/fn"; }
# Line of the first line holding each text in $W/fn, in the order given: all there and rising, or fail.
inorder() { python3 -I -c 'import sys; L=open(sys.argv[1]).read().split("\n"); n=[next((i for i, l in enumerate(L) if t in l), -1) for t in sys.argv[2:]]; sys.exit(0 if min(n) >= 0 and n == sorted(n) and len(set(n)) == len(n) else 1)' "$W/fn" "$@"; }
# The order checks on a copy (kb, g): the shortcuts' groups, our page, Apple's 18 page.
shortcuts_ok() {
  fn 'NSArray *MSKeysShortcutSpecifiers(id target) {' "$1" && inorder '[cg setIdentifier:@"MAC_CUSTOM_SHORTCUTS_GROUP"];' '[s addObject:cg];' \
     'if (kpInstalled) [s addObject:MSKeyPilotRowSpecifier(target)];' '[s addObject:MSCustomShortcutsRowSpecifier()];' \
     '[g setIdentifier:@"MAC_WINDOW_KEYS_GROUP"];' '[s addObject:g];' '[s addObject:keys];' 'return s;' \
  && [ "$(grep -c 'return s;' "$W/fn")" = 1 ] && [ "$(grep -c 'addObject:' "$W/fn")" = 5 ]
}
page_ok() {
  fn '- (NSMutableArray *)specifiers {' "$1" && inorder 'NSArray *hw = MSNESpecifiers(self, @"TIHardwareKeyboardController"' \
     'NSMutableArray *s = [NSMutableArray arrayWithArray:MSKeysShortcutSpecifiers(self)];' '[s addObjectsFromArray:MSKeysGroupSpecifiers(self, nil, hw, self)];' \
     'if (hw.count) [s addObjectsFromArray:hw];' '_specifiers = s;' \
  && [ "$(grep -c 'MSKeysShortcutSpecifiers\|MSKeysGroupSpecifiers\|addObjectsFromArray:hw' "$W/fn")" = 3 ]
}
g18_ok() {
  grep -q 'return kind == G18Keyboard ? \[MSKeysShortcutSpecifiers(prefs) arrayByAddingObjectsFromArray:MSKeysGroupSpecifiers(prefs, @"Mac Keys", apple, prefs)\] : MSPointerOwnSpecifiers(prefs, YES);' "$1" \
  && [ "$(grep -c 'MSKeysGroupSpecifiers(prefs' "$1")" = 1 ]
}
check "your own shortcuts' group first: KeyPilot's row (only while it is installed) above Custom Shortcuts' row, then Window Tiling Shortcuts' group and switch" "shortcuts_ok $KB"
check "  ... KeyPilot's row as before: its name, id, cell, two lines' height; the footer's KeyPilot sentence while it is installed" \
  "fn 'static PSSpecifier *MSKeyPilotRowSpecifier(id target) {' $KB && grep -q 'PSSpecifier \*kp = \[PSSpecifier preferenceSpecifierNamed:@\"KeyPilot\" target:target set:nil get:nil detail:nil cell:kCellTitleValue edit:nil\];' \$W/fn \
   && grep -q '\[kp setIdentifier:@\"MAC_KEYPILOT\"\];' \$W/fn && grep -q 'if (cell) \[kp setProperty:cell forKey:@\"cellClass\"\];' \$W/fn && grep -q '\[kp setProperty:@58.0 forKey:@\"height\"\];' \$W/fn \
   && grep -q 'While KeyPilot is installed, its shortcuts work and Custom Shortcuts waits.' $KB"
check "our Keyboard page: the shortcuts, then the Mac keys (their footer reads Apple's rows), then Apple's Hardware Keyboard rows at the end" "page_ok $KB"
check "  ... the five Mac key switches and their group as before, the footer's Modifier Keys link to the page" \
  "fn 'NSArray *MSKeysGroupSpecifiers(id target, NSString *title, NSArray *native, id linkTarget) {' $KB && grep -q '\[g setIdentifier:@\"MAC_KEYS_GROUP\"\];' \$W/fn && [ \$(grep -c 'MSKeySwitch(target, @' \$W/fn) = 5 ] \
   && grep -q 'MSKeysSetFooter(g, native, linkTarget);' \$W/fn && grep -q '(void)msOpenModifierKeys { MSKeysOpenModifierKeysOn(self); }' $KB"
check "  ... the page built again as before when the footers' shared keys change (MSKCSignature)" \
  "grep -q 'return \[NSString stringWithFormat:@\"%@|%@|%@|%d\", MSKCFooterLines(0), MSKCFooterLines(1), MSKCFooterLines(2), MSKCWindowKeysOn()\];' $KB && grep -q 'NSString \*now = MSKCSignature();' $KB"
check "iPadOS 18: our block at the top of Apple's Hardware Keyboard page in the same order, Mac Keys after the shortcuts" "g18_ok $G"
# Made to fail: copies with the old order (1.8.3-1.8.7 kb02: Mac keys, Apple's rows, Window Tiling, Custom Shortcuts, KeyPilot last), or one part of
# it, must fail the checks above.
mutant() {   # name, which check (shortcuts_ok, page_ok, g18_ok), file, then pairs of texts: each found once and replaced
  local name=$1 what=$2 src=$3; shift 3
  python3 -I -c 'import sys
s = open(sys.argv[1]).read()
for a, b in zip(sys.argv[3::2], sys.argv[4::2]):
    assert s.count(a) == 1, "mutant site not found: " + a
    s = s.replace(a, b)
open(sys.argv[2], "w").write(s)' "$src" "$W/m-$name" "$@" || return 1
  ! $what "$W/m-$name"
}
OLDPAGE='        NSMutableArray *s = [NSMutableArray arrayWithArray:MSKeysGroupSpecifiers(self, nil, hw, self)];
        if (hw.count) [s addObjectsFromArray:hw];
        [s addObjectsFromArray:MSKeysShortcutSpecifiers(self)];'
NEWPAGE='        NSMutableArray *s = [NSMutableArray arrayWithArray:MSKeysShortcutSpecifiers(self)];
        [s addObjectsFromArray:MSKeysGroupSpecifiers(self, nil, hw, self)];
        if (hw.count) [s addObjectsFromArray:hw];'
check "made to fail: our page in the old order (Mac keys and Apple's rows first, the shortcuts at the end)" "mutant oldpage page_ok $KB \"\$NEWPAGE\" \"\$OLDPAGE\""
check "made to fail: Apple's rows above the Mac keys" "mutant hwfirst page_ok $KB '        [s addObjectsFromArray:MSKeysGroupSpecifiers(self, nil, hw, self)];
        if (hw.count) [s addObjectsFromArray:hw];' '        if (hw.count) [s addObjectsFromArray:hw];
        [s addObjectsFromArray:MSKeysGroupSpecifiers(self, nil, hw, self)];'"
check "made to fail: KeyPilot's row after Custom Shortcuts' (the old place)" "mutant kplast shortcuts_ok $KB '    if (kpInstalled) [s addObject:MSKeyPilotRowSpecifier(target)];
    [s addObject:MSCustomShortcutsRowSpecifier()];' '    [s addObject:MSCustomShortcutsRowSpecifier()];
    if (kpInstalled) [s addObject:MSKeyPilotRowSpecifier(target)];'"
check "made to fail: KeyPilot's row gone" "mutant kpgone shortcuts_ok $KB '    if (kpInstalled) [s addObject:MSKeyPilotRowSpecifier(target)];
' ''"
check "made to fail: Window Tiling's group above your own shortcuts (the old order)" "mutant tilingfirst shortcuts_ok $KB '    [cg setIdentifier:@\"MAC_CUSTOM_SHORTCUTS_GROUP\"];' '    [g setIdentifier:@\"MAC_WINDOW_KEYS_GROUP\"];
    [cg setIdentifier:@\"MAC_CUSTOM_SHORTCUTS_GROUP\"];' '    [g setIdentifier:@\"MAC_WINDOW_KEYS_GROUP\"];
    [s addObject:g];' '    [s addObject:g];'"
check "made to fail: iPadOS 18's block in the old order (Mac Keys first)" "mutant old18 g18_ok $G '[MSKeysShortcutSpecifiers(prefs) arrayByAddingObjectsFromArray:MSKeysGroupSpecifiers(prefs, @\"Mac Keys\", apple, prefs)]' '[MSKeysGroupSpecifiers(prefs, @\"Mac Keys\", apple, prefs) arrayByAddingObjectsFromArray:MSKeysShortcutSpecifiers(prefs)]'"
exit $fails
