#!/bin/bash
# Mac test of how SpringBoard's controllers are asked for (common/SBShared.h, test-sbshared.m; 1.8.0.1): never made by us -- SpringBoard went down at
# its start on the iPad 2 (16.7.7) when our constructor asked +[SBControlCenterController sharedInstance] before SpringBoard's launch had made its
# main workspace (a late start: our constructor 10.4 s after SpringBoard's exec). Then the wiring: Control Center's controller is asked that way,
# and "SpringBoard is still starting" is measured from our constructor, which sets its time first.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
clang -fobjc-arc -Wall -Werror -Wno-unused-function -framework Foundation -o "$W/tsbs" test-sbshared.m && "$W/tsbs" || fails=1
X=../statusbar/StatusBar.x C=../common/CCController.h
check() { if eval "$2"; then echo "PASS  wiring: $1"; else echo "FAIL  wiring: $1"; fails=1; fi; }
fn() { awk -v h="$2" '!p && index($0, h) == 1 && /\{ *(\/\/.*)?$/ {p=1} p {print} p && /^}/ {exit}' "$1"; }   # one function of a file, from its first line
check "Control Center's controller (15-17): the shared instance as SpringBoard made it, never +sharedInstance itself" \
  "fn $C 'static inline id MSBDControlCenterController(' | grep -qF 'if ([(id)c respondsToSelector:shared]) return MSBDSBSharedIfExists(c);' \
   && ! fn $C 'static inline id MSBDControlCenterController(' | grep -qF '((id (*)(id, SEL))objc_msgSend)((id)c, shared)' && grep -qF '#import \"SBShared.h\"' $C"
check "  ... every part asks it there (StatusBar.x's wrapper and the Dock's); no code of ours asks +[SBControlCenterController sharedInstance] itself (the debug as-built switch aside)" \
  "fn $X 'static id DMControlCenterController(' | grep -qF 'return MSBDControlCenterController();' && grep -qF 'id cc = MSBDControlCenterController();' ../dock/Dock.x \
   && [ \$(cat $X ../dock/*.x ../dock/*.h ../statusbar/*.h ../common/*.h 2>/dev/null | grep -v '^ *//' | grep 'SBControlCenterController' | grep -c 'sharedInstance') = 1 ] \
   && fn $X 'static id DMControlCenterController(' | grep -B1 'SEL s = NSSelectorFromString(@\"sharedInstance\");' | grep -qF 'DMTestFlag(\"/tmp/msb-ccquery-asbuilt\")' \
   && fn $X 'static id DMControlCenterController(' | awk '/^#if DEBUG/{d=1} /^#endif/{d=0} /sharedInstance\"\);/{if (!d) bad=1} END{exit bad}'"
check "SpringBoard is still starting: the first 8 s after our constructor, not the process's age" \
  "fn $X 'static BOOL DMStarting(' | grep -qF 'if (gDMLoadedAt > 0 && CACurrentMediaTime() - gDMLoadedAt >= 8.0) { over = YES; return NO; }' \
   && ! fn $X 'static BOOL DMStarting(' | grep -v 'msb-starting-asbuilt' | grep -qF 'DMProcessAge()'"
check "  ... our constructor sets that time first (before anything of ours that waits for the start runs, our Control Center's start among it)" \
  "awk '/^%ctor \{/{c=NR} c && !g && /gDMLoadedAt = CACurrentMediaTime\(\);/{g=NR} c && /DMCCPanelInit\(\);/{p=NR} END{exit !(c && g > c && p > g)}' $X \
   && awk '/^%ctor \{/{c=NR} c && !g && /gDMLoadedAt = CACurrentMediaTime\(\);/{g=NR} END{exit !(c && g && g - c < 12)}' $X"
exit $fails
