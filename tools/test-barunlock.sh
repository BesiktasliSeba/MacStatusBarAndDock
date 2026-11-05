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
# ... as built (StatusBar.x): the screen's own bar going off makes a full-screen window's strip decide again, by SpringBoard's own setters of its wrapper; a copy of ours closed up without a clock lays out again at its time label's arrival
if awk '/^%hook UIStatusBar_Modern/{f=1} f{print} f&&/^%end/{exit}' ../statusbar/StatusBar.x | grep -q 'MSBDScreenBarWentOff(before, me.alpha).*DMSMMainBarChanged(me)'; then echo "PASS  the screen's bar going off: the strip decides again"; else echo "FAIL  the screen's bar going off: the strip decides again"; exit 1; fi
if awk 'index($0, "static void DMAttachIfFilledNow(UIView *fg, const char *why, BOOL now) {") == 1 {f=1} f {print} f && /^}/ {exit}' ../statusbar/StatusBar.x | grep -q 'kLogoKey)) { DMClosedUpClockBack(fg); return; }'; then echo "PASS  a closed-up copy of ours at its time label's arrival"; else echo "FAIL  a closed-up copy of ours at its time label's arrival"; exit 1; fi
if grep -q 'CGFloat tw = DMLabelShown(timeLabel) ? MSBDTimeLabelWidth(timeLabel.bounds.size.width, ceil(' ../statusbar/StatusBar.x; then echo "PASS  the time's width in our layout: its text's when more"; else echo "FAIL  the time's width in our layout"; exit 1; fi
