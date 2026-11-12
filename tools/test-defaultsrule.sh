#!/bin/bash
# Mac test of which defaults entries an install writes (common/DefaultsRule.h, test-defaultsrule.c), then the root helper's use of it
# (macsettings/sshtoggled/main.m FreezeOldDefaults).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -Wall -Wextra -Wno-unused-function -o "$W/tdr" test-defaultsrule.c
"$W/tdr"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
H=../macsettings/sshtoggled/main.m
fn() { awk '/^static void FreezeOldDefaults\(void\) \{/,/^}/' $H; }
check "the helper asks the rule: a device that settled a version before is no first install, whatever dpkg says" \
  "fn | grep -qF 'BOOL fresh = MSBDDefaultsFirstInstall([decision isEqualToString:@\"fresh\"], (long)done);' && grep -qF '#include \"../../common/DefaultsRule.h\"' $H"
check "  ... each old default written by the rule, where nothing is stored" \
  "fn | grep -qF 'if (MSBDDefaultsFreezes([e[3] integerValue], (long)done, fresh) && WriteMobilePrefsKey(e[0], e[1], e[2], YES))' && ! fn | grep -qF 'if (!fresh) for'"
check "  ... the first-install extras (Stage Manager engine) only for a first install" \
  "fn | grep -qxF '    if (fresh) {' && ! fn | grep -qF 'fresh && done == 0'"
check "1.8.6: Show Apps' Own Menus on for every device once (written over what is stored, by the rule), and the v4 step it rides on" \
  "grep -qF '    return @[ @[@\"com.besiktasliseba.macstatusbar\", @\"appOwnMenus\", @YES, @4] ];' $H && fn | grep -qF 'if (MSBDDefaultsForAll([e[3] integerValue], (long)done) && WriteMobilePrefsKey(e[0], e[1], e[2], NO))' && grep -qE '^#define DEFAULTSVERSION ([4-9]|[1-9][0-9]) ' $H && ! awk '/^static NSArray<NSArray \*> \*OldDefaults\(void\) \{/,/^}/' $H | grep -q appOwnMenus"
check "1.8.7 (v5): Window Tiling Shortcuts and Custom Shortcuts written off where never set on an update (new installs: on), the key extras untouched" \
  "grep -q '^#define DEFAULTSVERSION 5 ' $H && awk '/^static NSArray<NSArray \*> \*OldDefaults\(void\) \{/,/^}/' $H > \$W/od \
   && grep -qF '@[@\"com.besiktasliseba.macstatusbar\", @\"windowTilingKeys\", @NO, @5]' \$W/od && grep -qF '@[@\"com.besiktasliseba.customshortcuts\", @\"enabled\", @NO, @5]' \$W/od \
   && ! grep -q 'graveescapetweak\|tabmutetweak\|volumeglobetweak\|brightnesskeytweak' \$W/od \
   && grep -qF '@[@\"com.besiktasliseba.dockmagnification\", @\"showTrash\", @NO, @4],' \$W/od"
[ $fails = 0 ] && echo "test-defaultsrule: site checks pass" || { echo "test-defaultsrule: site checks FAILED"; exit 1; }
