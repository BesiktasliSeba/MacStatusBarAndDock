#!/bin/bash
# Mac test of what a round-icon catch makes of a window (statusbar/A5LockCatch.h, test-a5lockcatch.c): 1.7.9 regression G-4b, Aerial 5 minimizing
# every window as the screen locks -- the user's minimized windows stay minimized and windows on another desktop stay there; the windows that were on
# screen come back after the unlock as before. Then the wiring in StatusBar.x: the catch asks the rule, the lock watch catches the windows we keep
# hidden (no per-frame watch looks at them), and a window brought back while Aerial still has it minimized waits for Aerial's restore.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
clang -std=c11 -O1 -Wall -Werror -Wno-unused-function -o "$W/talc" test-a5lockcatch.c && "$W/talc" || fails=1
X=../statusbar/StatusBar.x
wire() { if grep -q -- "$2" "$X"; then echo "PASS  wiring: $1"; else echo "FAIL  wiring: $1"; fails=1; fi; }
wire "the header is included" '#include "A5LockCatch.h"'
wire "the catch asks the rule (with whether we hide it already)" 'int role = MSBDA5CatchRole(hiddenOurs, away,'
wire "a kept window is not marked the lock's or coming back" 'if (role & MSBDA5CatchLock) objc_setAssociatedObject(stage, kA5LockHiddenKey'
wire "a window of another desktop is not put in our minimized state" 'if (!away) objc_setAssociatedObject(stage, kStageHiddenKey, @YES'
wire "the lock watch looks at every desktop's windows" 'for (UIView \*s in DMAerialStagesAll()) {   // when each window last changed'
wire "the lock watch catches a window we keep hidden when Aerial minimizes it" 'DMA5CatchBehindHide(s)'
wire "a window brought back while Aerial has it minimized waits for its restore" 'if (DMA5ShowWaits(stage)) return;'
wire "the follow shows its window through the plain restore (no second wait)" 'DMRestoreStageNow(st);'
wire "the unlock keeps the lock's mark until it brings the window back" 'objc_setAssociatedObject(st, kA5LockHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);   // (brought back now'
exit $fails
