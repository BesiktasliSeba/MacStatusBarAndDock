#!/bin/bash
# Mac test of the status bar's locked look (statusbar/BarUnlock.h, test-barunlock.c): the unlocked look as soon as the Cover Sheet starts to leave
# (1.7.1 item 11: the M1's wake gave it 2 s late), the Lock Screen and Notification Center keep the locked look; after a wake the windows'
# follow-ups start as the Cover Sheet starts to leave (1.7.4: Zetsu's windows came back 2.8 s after the M1's unlock).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -o "$W/tbu" test-barunlock.c
"$W/tbu"
# ... as built (StatusBar.x): a copy held with its items gets one more layout pass before it is left to iOS, on every iPadOS: on 15.6.1 SpringBoard's own open from the Cover Sheet moves a copy into
# the App Switcher's window and no layout pass comes, so the first full-screen app after a respring, from the Lock Screen, had the stock bar over it (code review 1.8.1, finding 1's Lock Screen row)
F=$(awk 'index($0, "static void DMHoldSafetyCheck(UIView *fg, int checks) {") == 1 {f=1} f {print} f && /^}/ {exit}' ../statusbar/StatusBar.x)
if echo "$F" | awk '/if \(\(hasItems && checks >= 1\) \|\| checks >= 30\) \{/{a=1} a&&/^            \[v setNeedsLayout\]; \[v layoutIfNeeded\];$/{b=1} b&&/if \(!\[objc_getAssociatedObject\(v, kHoldKey\) boolValue\]\) \{.*return; \}/{c=1} c&&/left to iOS from now on/{print "ok"; exit}' | grep -q ok && ! echo "$F" | grep -q 'DMNewOS'; then echo "PASS  a copy's last layout pass before it is left to iOS, on every iPadOS"; else echo "FAIL  a copy's last layout pass before it is left to iOS"; exit 1; fi
