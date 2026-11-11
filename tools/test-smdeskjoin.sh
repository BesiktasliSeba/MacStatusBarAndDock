#!/bin/bash
# Mac test of the Stage Manager engine's one-desktop rule for transitions SpringBoard builds itself (statusbar/SMDeskJoin.h, test-smdeskjoin.m):
# another stage asked for joins the desktop (the 4-window rule), the desktop's own and Stage Manager's own arrangements pass, a random sweep.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/tdj" test-smdeskjoin.m
"$W/tdj"
# Review of 1.8.6 (tv): a stage SpringBoard asks for on the TV joins the TV's desktop through none of the Mac Switcher's iPad-only paths
# (statusbar/SMDesktop.h DMSMJoinStageAsked): no "another desktop's window" flag, which alone leads to DMMSWSMAskedBringHere, DMSMJoinWindowCardGo and
# DMSMJoinMinimizedGo (each writes an iPad desktop's windows, DMMSWSMDeskWindows, into the TV's transition), no minimized window reopened on its iPad
# desktop, no new iPad desktop for a full TV desktop, nothing recorded on the iPad's current desktop after the join.
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
D=../statusbar/SMDesktop.h
body() { awk '/^__attribute__\(\(noinline\)\) static void DMSMJoinStageAsked\(/,/^}/' $D; }
check "tv: the asked join knows its display before any flag is read" \
  "body | awk '/BOOL tv = !DMSMIsMainIdentity\\(identity\\);/{a=NR} /flags \\|= DMSMJoinOtherDesk;/{if(!b)b=NR} END{exit !(a && b && a < b)}'"
check "tv: DMSMJoinOtherDesk is set only for an iPad join (every place it is set), and the Go/Bring paths need exactly that flag" \
  "[ \$(body | grep -c 'flags |= DMSMJoinOtherDesk') = 2 ] && [ \$(body | grep -c 'if (!tv && DMSMDeskOnOtherDesktop(k)) flags |= DMSMJoinOtherDesk;') = 1 ] && body | grep -q 'if (!tv && reopenAsk && askedW.count == 1' && body | grep -q 'if (flags == DMSMJoinOtherDesk && ' && grep -q 'NSString \\*tapped = flags == DMSMJoinOtherDesk && gMSWGoToAppDesk' $D && grep -q 'NSNumber \\*did = k && flags == DMSMJoinOtherDesk && askedW.count == 1' $D"
check "tv: the reopen is the asked join's only call of DMSMJoinMinimizedReopen (gated above)" \
  "[ \$(body | grep -c 'DMSMJoinMinimizedReopen(') = 1 ]"
check "tv: a full TV desktop opens no new iPad desktop (DMMSWSMAskedFull iPad only)" \
  "[ \$(body | grep -c 'DMMSWSMAskedFull(') = 1 ] && body | grep -q 'if (!tv && leftOut.count && DMMSWSMAskedFull(ctx, asked, freshB, askedEntity, identity, frontB)) return;'"
check "tv: the join's end records nothing on the iPad's current desktop for the TV (left-out windows minimized and said, as a TV launch)" \
  "[ \$(grep -c 'DMSMDeskJoinDone(.*, tv, ' $D) = 2 ] && awk '/^static void DMSMDeskJoinDone\\(/,/^}/' $D | grep -q 'if (tv) DMMSWSMLeftOut(leftOut, nil);' && awk '/^static void DMSMDeskJoinDone\\(/,/^}/' $D | grep -q 'else DMMSWSMAskedJoined(fresh, leftOut);' && [ \$(grep -c 'DMMSWSMAskedJoined(' $D) = 1 ]"
check "tv: the desktop read is the TV's own (no Mac Switcher desktop windows)" \
  "body | grep -q 'NSArray<NSArray \\*> \\*mswWins = tv ? nil : DMMSWSMAskedDeskWindows();' && [ \$(grep -c 'DMMSWSMAskedDeskWindows()' $D) = 1 ]"
[ $fails = 0 ] && echo "test-smdeskjoin: tv site checks pass" || { echo "test-smdeskjoin: tv site checks FAILED"; exit 1; }
