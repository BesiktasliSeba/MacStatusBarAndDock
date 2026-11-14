#!/bin/bash
# test-1872.sh: the 1.8.7.2 fixes (KT 14 Nov, A12Z 18.5), site checks on the code as built:
#  1. the Dock's own items (Finder, Downloads, the Launchpad picture) draw their picture again only when their size changed -- the size it was drawn for,
#     never the image's own whole-pixel size (at a 47.64 pt Dock every layout drew a "new" picture, and in Edit Home Screen a new picture lays the Dock
#     out again: SpringBoard's main thread looped until the watchdog, a Dock icon moved);
#  2. the Lock Screen's padlock goes down by what Menu Bar Size added to the bar, as the grabber does (Large covered its shackle);
#  3. Swipe Up to Quit on the A12Z: the trackpad's swipe in the screen's up, and a finger's flick blocked only on a desktop or "+".
# Each check fails on 1.8.7.1's code (57b9c969).
cd "$(dirname "$0")" || exit 1
rc=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; rc=1; }
D=../dock; X=../statusbar/StatusBar.x; M=../statusbar/MacSwitcher.h
fn() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }

# 1. no image-size comparison left for our own drawn pictures; each keeps the size it drew for
if ! grep -q 'CGSizeEqualToSize(self.image.image.size, self.bounds.size)' $D/FinderIcon.m $D/Downloads.m \
   && ! grep -q 'CGSizeEqualToSize(overlay.image.size, bounds.size)' $D/Launchpad.m; then
  pass "no Dock item of ours compares its picture's own (whole-pixel) size with its view's"
else fail "a Dock item still redraws when its image's size is not its view's (every layout at a fractional Dock size)"; fi
if fn $D/FinderIcon.m '- (void)dm_layoutPicture {' | grep -q '!CGSizeEqualToSize(self.drawnSize, self.bounds.size)' \
   && fn $D/FinderIcon.m '- (void)dm_layoutPicture {' | grep -q 'self.drawnSize = self.bounds.size;'; then
  pass "Finder: the face is drawn again only for a new size (drawnSize kept with each drawing)"
else fail "Finder: dm_layoutPicture does not keep and compare the size it drew for"; fi
if fn $D/Downloads.m '- (void)dm_layoutPicture {' | grep -q '!CGSizeEqualToSize(self.drawnSize, self.bounds.size)) { self.image.image = DMFolderImage(self.bounds.size); self.drawnSize = self.bounds.size; }'; then
  pass "Downloads: the folder is drawn again only for a new size"
else fail "Downloads: dm_layoutPicture does not keep and compare the size it drew for"; fi
if grep -q 'NSValue \*drawnFor = objc_getAssociatedObject(overlay, kDrawnSizeKey);' $D/Launchpad.m \
   && grep -q '!drawnFor || !CGSizeEqualToSize(drawnFor.CGSizeValue, bounds.size)' $D/Launchpad.m \
   && grep -q 'objc_setAssociatedObject(overlay, kDrawnSizeKey, \[NSValue valueWithCGSize:bounds.size\]' $D/Launchpad.m; then
  pass "Launchpad: its picture is drawn again only for a new size (or a new style)"
else fail "Launchpad: the overlay does not keep and compare the size it drew for"; fi
# (the layout hook still follows a real new picture: the stand-ins and Glass Shelf's reflection depend on it)
if grep -q 'if (self.image.image != was) DMDockItemPictureChanged(self);' $D/FinderIcon.m && grep -q 'if (self.image.image != was) DMDockItemPictureChanged(self);' $D/Downloads.m; then
  pass "a real new picture still lays the Dock out again (Glass Shelf, Edit Home Screen)"
else fail "DMDockItemPictureChanged is no longer called for a new picture"; fi

# 2. the padlock
if fn $X 'static void DMBarSizeProudLockApply(UIView *v) {' | grep -q 'MSBDMenuBarGrabberShift(gDMBarSize, gDMMenuBarH, gDMMenuBarStockH)' \
   && fn $X 'static void DMBarSizeProudLockApply(UIView *v) {' | grep -q 'v.layer.sublayerTransform = want;' \
   && fn $X 'static void DMBarSizeProudLockApply(UIView *v) {' | grep -q 'v.window.screen != \[UIScreen mainScreen\]' \
   && grep -q '%hook SBUIProudLockIconView' $X && grep -q 'DMBarSizeProudLockApply((UIView \*)self);' $X \
   && grep -q 'if (DMBarSizeOwns(pl, NO, "layoutSubviews", "v16@0:8")) { %init(MenuBarSizeProudLock, SBUIProudLockIconView = pl);' $X \
   && grep -A2 '    DMBarSizeGrabberInit();' $X | grep -q '    DMBarSizeProudLockInit();'; then
  pass "the Lock Screen's padlock is drawn lower by what the size added to the bar (the grabber's shift), on the iPad's screen, at each of its layouts"
else fail "the Lock Screen's padlock does not follow the bar's height"; fi

# 3. Swipe Up to Quit on the A12Z: the trackpad's swipe read as it comes (already in the screen's up; asked for in the turned view, UIKit turned it
#    across: -263,-13 for an up swipe), and a finger's flick a move only when let go on a desktop or "+" -- not anywhere in a band from the first desktop
#    to the screen's right edge (a flick up of the right-hand window, under the strip, never quit)
if fn $M 'static CGPoint DMMSWScrollVector(UIPanGestureRecognizer *g, BOOL velocity) {' | grep -q 'return velocity ? \[g velocityInView:nil\] : \[g translationInView:nil\];' \
   && grep -q 'CGFloat dy = MIN(0.0, DMMSWScrollVector(g, NO).y);' $M \
   && grep -q 'CGPoint tr = DMMSWScrollVector(g, NO), v = DMMSWScrollVector(g, YES);' $M \
   && ! grep -q '\[g translationInView:gMSWRoot\].y' $M; then
  pass "Swipe Up to Quit by trackpad: the swipe read in the screen's up as it comes, never turned again by the view's turn"
else fail "the two-finger swipe is still read in the turned view (an up swipe reads across in landscape on 16+)"; fi
if fn $M 'static BOOL DMMSWFlickOverDesks(CGPoint p) {' | grep -q 'if (MSBDMSWDropOnDesk(p.x, p.y, CGRectGetMinX(r), CGRectGetMinY(r), CGRectGetMaxX(r), CGRectGetMaxY(r))) return YES;' \
   && fn $M 'static BOOL DMMSWFlickOverDesks(CGPoint p) {' | grep -q 'return !CGRectIsNull(plus) && MSBDMSWDropOnDesk(' \
   && ! fn $M 'static BOOL DMMSWFlickOverDesks(CGPoint p) {' | grep -q 'DMMSWDropTargetAt' \
   && ! grep -q 'MSBDMSWFlickOverStrip' $M ../statusbar/MSWFlick.h; then
  pass "Swipe Up to Quit by finger: a flick is a move only when let go on a desktop or \"+\" (no band to the screen's right edge)"
else fail "a flick let go anywhere in the strip's band (or the drop's '+' target to the right edge) is still never a quit"; fi

[ $rc = 0 ] && echo "test-1872: all pass"
exit $rc
