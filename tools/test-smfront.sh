#!/bin/bash
# Mac test of which Stage Manager window a finger's resize corner and an app's launch are for (statusbar/SMFrontRule.h, test-smfront.c): 1.7.9.2,
# GitHub #10 follow-up -- a covered window's corner takes no finger where a window in front covers it (Stage Manager picks the nearest corner, in
# front or behind), and a launch of an app whose window is on the desktop brings that window to the front unless it is newer than every other one.
# Then the wiring: SMResizeEdges.h's hooks on the nearest-corner lookup and the occluded answer, the join's bring-forward, the Dock's rule.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
clang -std=c11 -O1 -Wall -Werror -Wno-unused-function -framework CoreGraphics -o "$W/tsmf" test-smfront.c && "$W/tsmf" || fails=1
X=../statusbar/StatusBar.x E=../statusbar/SMResizeEdges.h
wire() { if grep -q -- "$3" "$2"; then echo "PASS  wiring: $1"; else echo "FAIL  wiring: $1"; fails=1; fi; }
wire "SMResizeEdges.h includes the rule" "$E" '#include "SMFrontRule.h"'
wire "the covered test asks the rule over the windows in front" "$E" 'return MSBDSMCoveredAt(at, fronts, n);'
wire "only windows in front of the card count" "$E" '!DMSMViewInFrontOf(other, card)) continue;'
wire "the window in front counts with our title bar" "$E" 'r = CGRectUnion(r, \[bar convertRect:bar.bounds toView:space\]);'
wire "the nearest-corner lookup is hooked with its signature checked" "$E" 'DMSMExpect(@encode(id), @encode(CGPoint), @encode(long long), @encode(BOOL), NULL)'
wire "only the foregrounded lookup (Apple's resize) is changed" "$E" 'if (!fore || gSMNearAsk.on || !DMSMFree()'
wire "a covered card answers occluded while the lookup runs" "$E" 'if (r || !gSMNearAsk.on || !\[self isKindOfClass:\[UIView class\]\] || !DMSMCardCoveredAt((UIView \*)self, gSMNearAsk.at, gSMNearAsk.space)) return r;'
wire "the engine installs the finger's corner rule" "$X" 'DMSMTouchCornersInstall();  // (optional'
wire "StatusBar.x includes the rule" "$X" '#include "SMFrontRule.h"'
wire "in front = newest alone (a tie is not)" "$X" 'return MSBDSMNewestAlone(times, n, at);'
wire "the Dock's bring-forward asks the rule" "$X" 'DMSMItemInFront(map, item, &newest)) return;   // (in front already, alone)'
wire "a launch of a window on the desktop brings it forward" "$X" 'DMSMJoinBringsForward(ctx, act, it, desk, map, identity, held); return; }'
wire "  ... unless it is in front already" "$X" 'if (DMSMItemInFront(map, mine, &newest)) {'
wire "  ... with the launch's own entity for its window" "$X" 'id e = me ? act : DMSMEntityForStageItem(desk, it);'
wire "  ... at the newest + 1, frontmost (the plan written with the launch's entity)" "$X" 'if (!DMSMWritePlan(ctx, toWrite, act))'
D=../statusbar/SMDesktop.h
wire "the app asked for alone in role 1 (-launchApplicationWithIdentifier:suspended:) is looked at" "$D" 'if (DMSMJoinActivatesWindow(ctx, asked, askedW, wins, flags, label0, identity)) return;'
wire "  ... only a plain one (no flags, one window, not a gesture's)" "$D" 'if (flags || asked.count != 1 || askedW.count != 1 || DMSMGestureCtx(ctx)'
wire "  ... not with an activating window (the launch join's shape)" "$D" '((id (\*)(id, SEL))objc_msgSend)(ctx, actS)) return NO;'
wire "  ... left as built when it is in front already" "$D" 'if (MSBDSMNewestAlone(times, n, at)) {'
wire "  ... the desktop kept, that window in front (the card's plan)" "$D" 'NSArray<NSArray \*> \*decision = DMSMDeskCardPlan(deskW, askedW, 0, &why);'
wire "  ... marked activating as Stage Manager's own bring-to-front" "$D" 'DMSMCtxMarkActivating(ctx, frontEntity);   // (as Stage Manager'
exit $fails
