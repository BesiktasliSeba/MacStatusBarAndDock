#!/bin/bash
# Mac test of what our own Control Center hands back to Apple's when iPadOS's look comes back without a respring (1.8.0, regression F1): the
# plain-C rules (common/CCGiveBack.h, test-ccgiveback.c: the header's status bar alpha as Apple's iPad Control Center sets it -- once, at its
# -initWithFrame: -- and as the iPhone's provider does, Apple's views' order after any takes, removals and adds; the rules as built in 1.8.0~z02
# as references that fail), then the sites in the code as built (statusbar/CCPanel.h): each piece of Apple's the panel changes is kept when ours
# first changes it and handed back by DMCCPGiveBack -- the header's status bar alpha through Apple's own setter, the backdrop's hidden flag only
# (its alpha never ours), each container at its place among Apple's views with its hidden flag and Apple's presentation values, its controller in
# Apple's order.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -o "$W/t" test-ccgiveback.c
"$W/t"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
P=${MSBD_TEST_CCPANEL:-../statusbar/CCPanel.h}   # (MSBD_TEST_CCPANEL: another copy of the panel, to see these checks fail on the old one)
check "the panel uses the rules of CCGiveBack.h" \
  "grep -q '^#include \"../common/CCGiveBack.h\" ' $P"
check "the header: Apple's own status bar alpha kept on the header before ours first sets 0 (its getter, in the API table as the sensor part's: no getter, no 0), and once kept never read again (what is there is ours)" \
  "grep -qF '{ \"CCUIHeaderPocketView\", \"statusBarAlpha\", \"d16@0:8\", NO, YES, NO,' $P && grep -q 'else if (!strcmp(r->sel, \"statusBarAlpha\")) sensor = NO;' $P \
   && awk '/^static void DMCCPHeaderBarAway\\(void\\) \\{/{f=1} f&&/!DMCCTypes\\(hp, @\"statusBarAlpha\", \"d16@0:8\"\\)\\) return;/{a=1} f&&a&&/if \\(!k.kept\\) \\{/{b=1} f&&b&&/MSBDCCKeepBefore\\(&k, \\(\\(double \\(\\*\\)\\(id, SEL\\)\\)objc_msgSend\\)\\(hp, NSSelectorFromString\\(@\"statusBarAlpha\"\\)\\)\\);/{c=1} f&&c&&/DMCCPAppleBarSet\\(hp, k\\);/{d=1} f&&d&&/o_DMCCPHeaderBarAlpha\\(hp, NSSelectorFromString\\(@\"setStatusBarAlpha:\"\\), 0.0\\);/{print \"ok\"; exit} f&&/^}/{exit}' $P | grep -q ok"
check "  ... ours goes in through Apple's own setter (never through our hook, which would take our 0 for Apple's wish); nothing of ours calls the setter through the runtime" \
  "! grep -q 'objc_msgSend)(hp, NSSelectorFromString(@\"setStatusBarAlpha:\")' $P && [ \$(grep -c 'o_DMCCPHeaderBarAlpha(hp, NSSelectorFromString(@\"setStatusBarAlpha:\"),' $P) = 2 ]"
check "  ... Apple's own calls while ours holds the header are kept as Apple's (0 set in their place), and pass untouched once iPadOS's look is back" \
  "awk '/^static void DMCCPHeaderBarAlpha\\(id self, SEL _cmd, double a\\) \\{/{f=1} f&&/BOOL ours = gCCPOn && \\(\\(UIView \\*\\)gCCPHost\\).superview;/{a=1} f&&a&&/if \\(ours \\|\\| k.kept\\) \\{ MSBDCCKeepAsked\\(&k, a\\); DMCCPAppleBarSet\\(self, k\\); \\}/{b=1} f&&b&&/o_DMCCPHeaderBarAlpha\\(self, _cmd, ours \\? 0.0 : a\\);/{print \"ok\"; exit} f&&/^}/{exit}' $P | grep -q ok"
check "  ... the give-back hands each kept header's value back through Apple's setter, once (the keep cleared)" \
  "awk '/^static void DMCCPGiveBack\\(NSString \\*why\\) \\{/{f=1} f&&/for \\(UIView \\*hp in gCCPAppleBarHeaders.allObjects\\) \\{/{a=1} f&&a&&/if \\(MSBDCCGiveBack\\(&k, &a\\) && o_DMCCPHeaderBarAlpha\\) \\{ o_DMCCPHeaderBarAlpha\\(hp, NSSelectorFromString\\(@\"setStatusBarAlpha:\"\\), a\\); bars\\+\\+; \\}/{b=1} f&&b&&/DMCCPAppleBarSet\\(hp, k\\);/{print \"ok\"; exit} f&&/^}/{exit}' $P | grep -q ok \
   && grep -q 'if (k.kept) \[gCCPAppleBarHeaders addObject:hp\]; else \[gCCPAppleBarHeaders removeObject:hp\];' $P"
check "the backdrop: hidden only while it showed, the one ours hid shown again by the give-back; its alpha is never written (Apple's presentation's)" \
  "grep -q 'if (back && !back.hidden) { back.hidden = YES; gCCPHidBackdrop = back; }' $P && awk '/^static void DMCCPGiveBack\\(NSString \\*why\\) \\{/{f=1} f&&/UIView \\*back = gCCPHidBackdrop;/{a=1} f&&a&&/if \\(back.hidden\\) back.hidden = NO;/{b=1} f&&b&&/gCCPHidBackdrop = nil;/{print \"ok\"; exit} f&&/^}/{exit}' $P | grep -q ok \
   && ! grep -q 'back.alpha = 1.0' $P && ! grep -qE 'DMCCPBackdrop\\(\\)[^;]*\\.alpha *=' $P"
check "each container as Apple had it, kept at its move: the views before it in Apple's view, its hidden flag (before ours moves it); a container already ours keeps what its first move kept" \
  "awk '/^static void DMCCPAdopt\\(/{f=1} f&&/NSArray<UIView \\*> \\*before = home.subviews;/{a=1} f&&a&&/BOOL appleHidden = cv.hidden;/{b=1} f&&b&&/\\[gCCPScroll insertSubview:cv atIndex:0\\];/{c=1} f&&c&&/DMCCPAppleKeep \\*keep = DMCCPAppleKeepOf\\(cv\\);/{d=1} f&&d&&/if \\(!keep && home && home != gCCPScroll\\) \\{/{e=1} f&&e&&/DMCCPPresentedLook\\(cv, containerVC, keep\\);/{print \"ok\"; exit} f&&/^}/{exit}' $P | grep -q ok \
   && grep -q 'for (NSUInteger i = 0; at != NSNotFound && i < at && i < before.count; i++) \[keep.before addPointer:(__bridge void \*)before\[i\]\];' $P"
check "  ... the presented look keeps the transform and alpha it replaces (once per view); handed back only where they are still ours" \
  "awk '/^static void DMCCPPresentedLook\\(/{f=1} f&&/if \\(keep && !\\[keep.transforms objectForKey:v\\]\\) \\[keep.transforms setObject:\\[NSValue valueWithCGAffineTransform:v.transform\\] forKey:v\\];/{a=1} f&&a&&/v.transform = CGAffineTransformIdentity;/{b=1} f&&b&&/if \\(keep && !\\[keep.alphas objectForKey:v\\]\\) \\[keep.alphas setObject:@\\(v.alpha\\) forKey:v\\];/{print \"ok\"; exit} f&&/^}/{exit}' $P | grep -q ok \
   && grep -q 'if (CGAffineTransformIsIdentity(v.transform)) v.transform = \[\[k.transforms objectForKey:v\] CGAffineTransformValue\];' $P && grep -q 'if (MSBDCCStillOurs(v.alpha, 1.0)) v.alpha = \[\[k.alphas objectForKey:v\] doubleValue\];' $P"
check "  ... a container Apple removes, or replaces with a new one, takes its keep with it (Apple's grid never gets it back)" \
  "awk '/^static void DMCCPWillRemove\\(id self, SEL _cmd, id grid, id containerVC\\) \\{/{f=1} f&&/DMCCPAppleKeepDrop\\(cv\\);/{print \"ok\"; exit} f&&/^}/{exit}' $P | grep -q ok && grep -q '        DMCCPAppleKeepDrop(old);   // (Apple' $P"
check "the give-back: the views first, in the reverse order of their moves, each right after the last of its views that is back (CCGiveBack.h), with Apple's hidden flag and no transform of ours; then the controllers, in Apple's order; then Apple's values on the views; the keeps cleared" \
  "awk '/^static void DMCCPGiveBack\\(NSString \\*why\\) \\{/{f=1} f&&/for \\(DMCCPAppleKeep \\*k in keeps.reverseObjectEnumerator\\) \\{/{a=1} f&&a&&/cv.hidden = k.hidden;/{b=1} f&&b&&/at = MSBDCCPutBackAt\\(prevAt, nPrev\\);/{c=1} f&&c&&/\\[home insertSubview:cv atIndex:\\(NSUInteger\\)at\\];/{d=1} f&&d&&/for \\(DMCCPAppleKeep \\*k in keeps\\) \\{/{e=1} f&&e&&/\\[grid addChildViewController:vc\\]; \\[vc didMoveToParentViewController:grid\\];/{g=1} f&&g&&/DMCCPAppleLookBack\\(k\\);/{h=1} f&&h&&/\\[gCCPAppleKeeps removeAllObjects\\];/{print \"ok\"; exit} f&&/^}/{exit}' $P | grep -q ok \
   && ! awk '/^static void DMCCPGiveBack\\(NSString \\*why\\) \\{/{f=1} f&&/cv.hidden = NO;|\\[home addSubview:cv\\];|cv.frame = f;/{print \"bad\"} f&&/^}/{exit}' $P | grep -q bad"
check "the crash guard: a crash in what the give-back runs (CCGiveBack.h: inlined into the panel in a release build, its own functions in a debug build) sets Control Center Style back to iPadOS's, as the panel's own code" \
  "grep -qxF 'file MacStatusBarCore ^(CCPanel|CCLayout|CCGiveBack)\\.h\$ controlcenter' crashmap-rules.txt && grep -q '^sym MacStatusBarCore ^_\*DMCCP\[A-Z\] controlcenter$' crashmap-rules.txt"
check "no em dashes in the new files" "! grep -n \$'\\xe2\\x80\\x94' ../common/CCGiveBack.h test-ccgiveback.c test-ccgiveback.sh"
[ $fails = 0 ] && echo "test-ccgiveback: wiring checks pass" || { echo "test-ccgiveback: wiring checks FAILED"; exit 1; }
