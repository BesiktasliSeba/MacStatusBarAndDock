#!/bin/bash
# Mac test of Fit to Window's question panels (1.8.3 item 6; statusbar/FitQuestionPlace.h, test-fitpanels.c), then the sites in the code as built.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -framework CoreGraphics -o "$W/tfp" test-fitpanels.c
"$W/tfp"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
S=../statusbar/StatusBar.x
check "the panels: the window's frame for the side, on every engine (never the engine's frame: Aerial 5.x's stage)" \
  "grep -q 'CGRect f = MSBDFitQuestionPanel(DMLayoutFrameWindow(side));' $S && ! grep -q 'CGRectInset(DMLayoutFrame(side)' $S"
check "both questions' titles: under the windows' desktop" \
  "[ \"\$(grep -c 'CGRect usable = DMLayoutFrameWindow(@\"fill\");   // (the windows. desktop, as the panels: FitQuestionPlace.h)' $S)\" = 2 ] && [ \"\$(grep -c 'pill.frame = CGRectMake(pillX, MSBDFitQuestionTitleY(usable), pillW, 40.0);' $S)\" = 2 ]"
check "the header is included" "grep -q '#include \"FitQuestionPlace.h\"' $S"
exit $fails
