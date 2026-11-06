// test-menuarrow.c -- Mac test of common/MenuArrow.h (1.7.5 item 5): where a menu that opens from a point goes (centred over its source, pushed in
// at the screen's sides, its edge an arrow's height from the source) and where its arrow sits (under the source's middle, sliding along the edge,
// never into the rounded corners), and the arrow's outline. Numbers as read on the M1 (15.6.1, landscape 1194 x 834) and the A12Z (18.5): the
// Settings icon's menu {595.5, 306.5, 250, 457} over its preview {798, 771.5, 47.5, 47.5}; Finder's menu {60.5, 644.5, 250, 97} over Finder at the
// Dock's left end. Run by test-menuarrow.sh.
#include <stdio.h>
#include "../common/MenuArrow.h"
static int fails = 0, checks = 0;
static int near(double a, double b) { return fabs(a - b) < 0.01; }
static void Frame(const char *what, CGRect got, CGRect want) {
    checks++;
    if (near(got.origin.x, want.origin.x) && near(got.origin.y, want.origin.y) && near(got.size.width, want.size.width) && near(got.size.height, want.size.height)) printf("PASS  %s\n", what);
    else { fails++; printf("FAIL  %s (got {%.2f, %.2f, %.2f, %.2f}, want {%.2f, %.2f, %.2f, %.2f})\n", what, got.origin.x, got.origin.y, got.size.width, got.size.height, want.origin.x, want.origin.y, want.size.width, want.size.height); }
}
static void Num(const char *what, double got, double want) { checks++; if (near(got, want)) printf("PASS  %s\n", what); else { fails++; printf("FAIL  %s (got %.3f, want %.3f)\n", what, got, want); } }
static void Int(const char *what, int got, int want) { checks++; if (got == want) printf("PASS  %s\n", what); else { fails++; printf("FAIL  %s (got %d, want %d)\n", what, got, want); } }
int main(void) {
    const CGFloat H = kMSBDArrowHeight, G = kMSBDArrowTipGap, W = kMSBDArrowWidth, R = 10.0;   // (R: the menus' corner, MacContextMenus)
    CGRect bounds = CGRectMake(8, 38, 1178, 788);   // (UIKit's content bounds on the M1: the screen less its margins and the menu bar)
    int dir = -1;
    // ---- a Dock app's menu in the middle of the Dock: centred over the icon, the arrow in its middle ----
    CGRect settingsMenu = CGRectMake(595.5, 306.5, 250, 457), settingsIcon = CGRectMake(798, 771.5, 47.5, 47.5);
    CGRect m = MSBDArrowMenuFrame(settingsMenu, settingsIcon, bounds, H, G, &dir);
    Frame("Settings' menu: centred over its icon (x 821.75 - 125), its bottom 9 + 3 pt above the icon, its height kept", m, CGRectMake(697, 302.5, 250, 457));
    Int("  ... the arrow points down (the menu opened above the icon)", dir, MSBDArrowDown);
    Num("  ... the arrow under the icon's middle: 124.75 pt from the menu's left edge", MSBDArrowOffset(m, CGRectGetMidX(settingsIcon), R, W), 124.75);
    Num("  ... its tip 3 pt above the icon", CGRectGetMaxY(m) + H, CGRectGetMinY(settingsIcon) - G);
    // ---- pushed in at the left side (Finder at the Dock's left end): the menu at the bounds' edge, the arrow slides over the icon ----
    CGRect finderMenu = CGRectMake(60.5, 644.5, 250, 97), finderIcon = CGRectMake(60.5, 760, 47.5, 47.5);
    m = MSBDArrowMenuFrame(finderMenu, finderIcon, bounds, H, G, &dir);
    Frame("Finder's menu: pushed in to the left side (x 8), its bottom an arrow above the icon", m, CGRectMake(8, 651, 250, 97));
    Num("  ... the arrow slides along the edge, still under Finder's middle (84.25 - 8)", MSBDArrowOffset(m, CGRectGetMidX(finderIcon), R, W), 76.25);
    // ---- and at the right side (the Downloads stack or the Trash at the Dock's right end) ----
    CGRect trashIcon = CGRectMake(1130, 760, 47.5, 47.5);
    m = MSBDArrowMenuFrame(CGRectMake(928, 644.5, 250, 97), trashIcon, bounds, H, G, &dir);
    Frame("the Trash's menu: pushed in to the right side (1186 - 250)", m, CGRectMake(936, 651, 250, 97));
    Num("  ... the arrow under the Trash's middle (1153.75 - 936)", MSBDArrowOffset(m, CGRectGetMidX(trashIcon), R, W), 217.75);
    // ---- the arrow never runs into the rounded corners ----
    Num("an item further out than the corner (its middle 2 pt in from the menu's edge): the arrow stops at corner + half its width", MSBDArrowOffset(CGRectMake(8, 0, 250, 97), 10.0, R, W), R + W / 2.0);
    Num("  ... at the right end the same", MSBDArrowOffset(CGRectMake(8, 0, 250, 97), 300.0, R, W), 250.0 - R - W / 2.0);
    Num("a menu too narrow for an arrow between its corners: the middle", MSBDArrowOffset(CGRectMake(0, 0, 30, 50), 3.0, R, W), 15.0);
    Num("the Downloads panel (corner 18): the stack's icon near the side keeps the arrow 28 pt in", MSBDArrowOffset(CGRectMake(652, 300, 360, 400), 1010.0, 18.0, W), 360.0 - 18.0 - W / 2.0);
    // ---- a menu below its source: the arrow on its top edge, pointing up ----
    CGRect src = CGRectMake(500, 100, 60, 60);
    m = MSBDArrowMenuFrame(CGRectMake(480, 170, 250, 200), src, bounds, H, G, &dir);
    Frame("a menu that opened below its source: centred, its top an arrow below the source", m, CGRectMake(405, 172, 250, 200));
    Int("  ... the arrow points up", dir, MSBDArrowUp);
    // ---- room ----
    m = MSBDArrowMenuFrame(CGRectMake(697, 40, 250, 722), settingsIcon, bounds, H, G, &dir);
    Frame("a menu as tall as the room above the icon: shortened by what it would cross the top by (it scrolls)", m, CGRectMake(697, 38, 250, 721.5));
    Int("  ... with its arrow", dir, MSBDArrowDown);
    CGRect tiny = CGRectMake(600, 0, 250, 60);
    m = MSBDArrowMenuFrame(tiny, CGRectMake(700, 80, 40, 40), bounds, H, G, &dir);
    Frame("no room above the source (30 pt left under the bounds' top, a menu needs 44): as it was", m, tiny);
    Int("  ... and no arrow", dir, MSBDArrowNone);
    m = MSBDArrowMenuFrame(settingsMenu, CGRectNull, bounds, H, G, &dir);
    Frame("no source: as it was", m, settingsMenu);
    Int("  ... no arrow", dir, MSBDArrowNone);
    m = MSBDArrowMenuFrame(CGRectMake(0, 0, 1300, 97), CGRectMake(600, 760, 47, 47), bounds, H, G, &dir);
    Num("a menu wider than the bounds: its left edge at the bounds' left", m.origin.x, 8.0);
    m = MSBDArrowMenuFrame(CGRectMake(NAN, 0, 250, 97), settingsIcon, bounds, H, G, &dir);
    Int("nonsense numbers: no arrow", dir, MSBDArrowNone);
    // ---- the outline ----
    CGPathRef p = MSBDArrowPathCreate(W, H, 1.0, MSBDArrowDown, false);
    CGRect pb = CGPathGetPathBoundingBox(p);
    Frame("the down arrow's outline fills its view: 20 wide, the 1 pt band over the menu's edge and 9 pt to the tip", pb, CGRectMake(0, 0, W, H + 1.0));
    Int("  ... the tip is at the bottom middle", CGPathContainsPoint(p, NULL, CGPointMake(W / 2.0, H + 1.0 - 0.6), false), 1);
    Int("  ... and not at the bottom corners", CGPathContainsPoint(p, NULL, CGPointMake(1.0, H + 0.5), false) || CGPathContainsPoint(p, NULL, CGPointMake(W - 1.0, H + 0.5), false), 0);
    CGPathRelease(p);
    p = MSBDArrowPathCreate(W, H, 1.0, MSBDArrowUp, false);
    Int("the up arrow's tip is at the top middle", CGPathContainsPoint(p, NULL, CGPointMake(W / 2.0, 0.6), false), 1);
    Int("  ... its band at the bottom", CGPathContainsPoint(p, NULL, CGPointMake(1.0, H + 0.5), false), 1);
    CGPathRelease(p);
    p = MSBDArrowPathCreate(W, H, 1.0, MSBDArrowNone, false);
    Int("no direction: an empty outline", CGPathIsEmpty(p), 1);
    CGPathRelease(p);
    // ---- the Dock at the screen's side (Settings > Dock > Position, 1.8.2): the menu beside its source, the arrow on the facing edge (A12Z, 1366 x 1024) ----
    CGRect sideBounds = CGRectMake(12, 54, 1342, 958), sideIcon = CGRectMake(1282, 440, 60, 60);
    m = MSBDArrowSideMenuFrame(CGRectMake(600, 300, 250, 200), sideIcon, sideBounds, H, G, true, &dir);
    Frame("the Dock at the right: the menu to the icon's left, level with its middle, an arrow from it", m, CGRectMake(1282 - G - H - 250, 370, 250, 200));
    Int("  ... the arrow points right", dir, MSBDArrowRight);
    Num("  ... at the icon's middle: 100 pt from the menu's top", MSBDArrowOffsetY(m, CGRectGetMidY(sideIcon), R, W), 100.0);
    Num("  ... its tip 3 pt from the icon", CGRectGetMaxX(m) + H, CGRectGetMinX(sideIcon) - G);
    CGRect leftIcon = CGRectMake(24, 440, 60, 60);
    m = MSBDArrowSideMenuFrame(CGRectMake(600, 300, 250, 200), leftIcon, sideBounds, H, G, false, &dir);
    Frame("the Dock at the left: to the icon's right", m, CGRectMake(84 + G + H, 370, 250, 200));
    Int("  ... the arrow points left", dir, MSBDArrowLeft);
    m = MSBDArrowSideMenuFrame(CGRectMake(600, 300, 250, 200), CGRectMake(1282, 60, 60, 60), sideBounds, H, G, true, &dir);
    Frame("Finder on top: pushed down to the bounds' top, under the bar", m, CGRectMake(1282 - G - H - 250, 54, 250, 200));
    Num("  ... the arrow slides, still at the icon's middle (90 - 54 + 0 from its top, kept off the corner)", MSBDArrowOffsetY(m, 90.0, R, W), 36.0);
    m = MSBDArrowSideMenuFrame(CGRectMake(600, 300, 250, 200), CGRectMake(1282, 950, 60, 60), sideBounds, H, G, true, &dir);
    Frame("the Trash at the bottom: pushed up to the bounds' bottom", m, CGRectMake(1282 - G - H - 250, 812, 250, 200));
    m = MSBDArrowSideMenuFrame(CGRectMake(600, 0, 250, 1200), sideIcon, sideBounds, H, G, true, &dir);
    Frame("a menu taller than the bounds: as tall, it scrolls", m, CGRectMake(1282 - G - H - 250, 54, 250, 958));
    m = MSBDArrowSideMenuFrame(CGRectMake(0, 0, 1300, 200), sideIcon, sideBounds, H, G, true, &dir);
    Frame("no room beside the Dock: as it was", m, CGRectMake(0, 0, 1300, 200));
    Int("  ... without an arrow", dir, MSBDArrowNone);
    m = MSBDArrowSideMenuFrame(CGRectMake(NAN, 0, 250, 97), sideIcon, sideBounds, H, G, true, &dir);
    Int("nonsense numbers: no arrow", dir, MSBDArrowNone);
    Num("the side arrow never runs into the rounded corners, at the top", MSBDArrowOffsetY(CGRectMake(0, 100, 250, 200), 102.0, R, W), R + W / 2.0);
    Num("  ... at the bottom", MSBDArrowOffsetY(CGRectMake(0, 100, 250, 200), 299.0, R, W), 200.0 - R - W / 2.0);
    Num("a menu too short for an arrow between its corners: the middle", MSBDArrowOffsetY(CGRectMake(0, 0, 250, 30), 3.0, R, W), 15.0);
    // ---- the Downloads panel beside a side Dock laid out again (code review 1.8.2, 7): a search grows it upwards, its bottom kept; the keyboard lifts it ----
    // (the A12Z, Right: the stack's middle at y 930, the panel opened 300 tall and pushed up to the bounds' bottom, 1012: 712..1012, the arrow level with the stack)
    CGRect opened = CGRectMake(1282 - G - H - 360, 712, 360, 300);
    CGFloat ay = -1, amid = -1;
    CGRect grown = MSBDArrowSidePanelRelayout(opened, 580, 1012, 930, R, W, &ay, &amid);
    Frame("8 results found: the panel 280 pt taller, upwards, its bottom where it opened", grown, CGRectMake(opened.origin.x, 432, 360, 580));
    Num("  ... the arrow stays level with the stack (it moved up 76.5 pt with the panel's share: off the stack)", amid, 930);
    Num("  ... and the panel pops up from it and goes back into it: the anchor at the stack's level", 432 + ay * 580, 930);
    CGRect back = MSBDArrowSidePanelRelayout(grown, 300, 1012, 930, R, W, &ay, &amid);
    Frame("the search cleared: back as it opened", back, opened);
    Num("  ... the arrow at the stack", amid, 930);
    MSBDArrowSidePanelRelayout(opened, 300, 600, 930, R, W, &ay, &amid);
    Num("the on-screen keyboard lifts it off the stack: the arrow stays inside, off the corner (it is hidden meanwhile)", amid, 600 - R - W / 2.0);
    Num("  ... the anchor kept inside the panel", ay, 1.0);
    MSBDArrowSidePanelRelayout(CGRectMake(1282 - G - H - 360, 54, 360, 300), 300, 354, 60, R, W, &ay, &amid);
    Num("a stack near the top, under the bar (its middle 6 pt below the panel's top): the arrow off the top corner", amid, 54 + R + W / 2.0);
    // ---- 1.8.2.2: the arrow at the icon's middle at the side Dock's two ends (iPad 2 F2, M1 F4) ----
    // (the iPad 2, 16.7.7, 1024 x 768, a 20 pt bar: the Downloads stack at the Left Dock's bottom end, its middle at y 733.4; the panel 360 x 200, its corner 18,
    //  kept 12 pt over the bottom (54..756); reach: the Dock's own end margin, 6 pt over the bottom)
    CGRect stack = CGRectMake(17.0, 717.4, 32.0, 32.0), pb2 = CGRectMake(12, 54, 1000, 702), preach = CGRectMake(12, 54, 1000, 708);
    m = MSBDArrowSideMenuFrame(CGRectMake(0, 0, 360, 200), stack, pb2, H, G, false, &dir);
    Num("before: the panel held 12 pt over the bottom, its arrow 28 pt from the corner: 5.4 pt above the stack's middle", CGRectGetMinY(m) + MSBDArrowOffsetY(m, CGRectGetMidY(stack), 18.0, W), 728.0);
    m = MSBDArrowSideMenuFrameReaching(CGRectMake(0, 0, 360, 200), stack, pb2, preach, H, G, 18.0, W, false, &dir);
    Num("the panel goes down as far as its arrow needs (6.5 pt over the bottom, the Dock's margin 6)", CGRectGetMaxY(m), 761.5);
    Num("  ... its arrow at the stack's middle", CGRectGetMinY(m) + MSBDArrowOffsetY(m, CGRectGetMidY(stack), 18.0, W), 733.4);
    Int("  ... beside the Dock, pointing left", dir, MSBDArrowLeft);
    // (the M1, 15.6.1, 1194 x 834, a 30 pt bar: Finder at the top of the Left Dock, its middle at y 61.1; its menu 250 x 97. UIKit's content bounds for our icons'
    //  menus start 20 pt lower (50): held there, the arrow was 20 pt from the menu's top, at 70, 9 pt below Finder's middle. Now every Dock menu's room starts under
    //  the bar, 33)
    CGRect finder = CGRectMake(14.0, 46.85, 28.5, 28.5);
    m = MSBDArrowSideMenuFrame(CGRectMake(0, 0, 250, 97), finder, CGRectMake(20, 50, 1154, 776), H, G, false, &dir);
    Num("before: Finder's menu at UIKit's 50, its arrow at 70 (9 pt low)", CGRectGetMinY(m) + MSBDArrowOffsetY(m, CGRectGetMidY(finder), R, W), 70.0);
    m = MSBDArrowSideMenuFrameReaching(CGRectMake(0, 0, 250, 97), finder, CGRectMake(20, 33, 1154, 793), CGRectMake(20, 33, 1154, 795), H, G, R, W, false, &dir);
    Num("now: under the bar (33), the arrow at Finder's middle", CGRectGetMinY(m) + MSBDArrowOffsetY(m, CGRectGetMidY(finder), R, W), 61.1);
    Num("  ... the menu where any icon's menu goes (its top at the bar's end + 3)", CGRectGetMinY(m), 33.0);
    m = MSBDArrowSideMenuFrameReaching(CGRectMake(0, 0, 250, 97), finder, CGRectMake(20, 50, 1154, 776), CGRectMake(20, 33, 1154, 795), H, G, R, W, false, &dir);
    Num("  ... held lower by its bounds, the menu still rises for its arrow, as far as under the bar", CGRectGetMinY(m) + MSBDArrowOffsetY(m, CGRectGetMidY(finder), R, W), 61.1);
    // (the fullest Dock, the M1's 27 icons at Recent Apps 10: the Trash's middle 24.5 pt over the bottom, its menu 67 tall: the Dock's margin leaves it 1.5 pt short)
    CGRect trash27 = CGRectMake(1160.0, 797.5, 24.0, 24.0);
    m = MSBDArrowSideMenuFrameReaching(CGRectMake(0, 0, 250, 67), trash27, CGRectMake(8, 33, 1178, 793), CGRectMake(8, 33, 1178, 795), H, G, R, W, true, &dir);
    Num("  ... at the reach's end (6 pt over the bottom) and no further", CGRectGetMaxY(m), 828.0);
    Num("  ... the arrow as near the icon's middle as the corner lets it (1.5 pt)", CGRectGetMidY(trash27) - (CGRectGetMinY(m) + MSBDArrowOffsetY(m, CGRectGetMidY(trash27), R, W)), 1.5);
    m = MSBDArrowSideMenuFrameReaching(CGRectMake(0, 0, 250, 200), CGRectMake(1282, 440, 60, 60), sideBounds, sideBounds, H, G, R, W, true, &dir);
    Frame("an icon in the middle of the Dock: as before", m, MSBDArrowSideMenuFrame(CGRectMake(0, 0, 250, 200), CGRectMake(1282, 440, 60, 60), sideBounds, H, G, true, &dir));
    m = MSBDArrowSideMenuFrameReaching(CGRectMake(0, 0, 1300, 200), sideIcon, sideBounds, sideBounds, H, G, R, W, true, &dir);
    Int("  ... no room beside the Dock: no arrow, as before", dir, MSBDArrowNone);
    m = MSBDArrowSideMenuFrameReaching(CGRectMake(0, 0, 250, 97), finder, CGRectMake(20, 50, 1154, 776), CGRectNull, H, G, R, W, false, &dir);
    Num("  ... no reach given: within its bounds, as before", CGRectGetMinY(m), 50.0);

    // ---- 1.8.2.2: a lifted picture too big for the side Dock's icon (M1 F1, A12Z F1) ----
    // (the M1, Left: Sileo's widget 437 x 226.5 centred on Sileo's icon (28.3, 133.35) stood at x -190.2, y 20.1, under the bar and over its menu {62, 33, 250, 337})
    CGRect m1b = CGRectMake(8, 33, 1178, 793);
    int on = -1;
    CGRect lp = MSBDArrowSidePreviewFrame(CGRectMake(-190.2, 20.1, 437, 226.5), CGPointMake(28.3, 133.35), 50.0, m1b, 1194, H, G, false, &on);
    Int("Sileo's widget at the Left Dock: not on the icon", on, 0);
    Frame("  ... beside the Dock, as the Bottom Dock's: from the bounds' left edge, level with the icon and under the bar", lp, CGRectMake(8, 33, 437, 226.5));
    m = MSBDArrowSideMenuFrame(CGRectMake(0, 0, 250, 337), lp, m1b, H, G, false, &dir);
    Frame("  ... its menu beside the picture, level with it", m, CGRectMake(457, 33, 250, 337));
    Int("  ... the two apart and on the screen", CGRectGetMaxX(lp) < CGRectGetMinX(m) && CGRectGetMinX(lp) >= 0 && CGRectGetMaxX(m) <= 1194 && CGRectGetMinY(lp) >= 30 && CGRectGetMinY(m) >= 30, 1);
    Num("  ... the arrow at the picture's middle, as at the bottom", CGRectGetMinY(m) + MSBDArrowOffsetY(m, CGRectGetMidY(lp), R, W), CGRectGetMidY(lp));
    lp = MSBDArrowSidePreviewFrame(CGRectMake(947.2, 20.1, 437, 226.5), CGPointMake(1165.7, 133.35), 1144.0, m1b, 1194, H, G, true, &on);
    Frame("  ... at the Right Dock: against the bounds' right edge", lp, CGRectMake(749, 33, 437, 226.5));
    m = MSBDArrowSideMenuFrame(CGRectMake(0, 0, 250, 337), lp, m1b, H, G, true, &dir);
    Frame("  ... the menu to its left", m, CGRectMake(487, 33, 250, 337));
    // (the A12Z, 18.5, 1366 x 1024: Sileo's document preview 497 x 203 at x -212.3 at the Left Dock, its icon's middle (36.2, 175.7))
    lp = MSBDArrowSidePreviewFrame(CGRectMake(-212.3, 74.2, 497, 203), CGPointMake(36.2, 175.7), 65.8, CGRectMake(8, 40, 1350, 976), 1366, H, G, false, &on);
    Frame("the A12Z's document preview: beside the Dock, level with the icon", lp, CGRectMake(8, 74, 497, 203));
    lp = MSBDArrowSidePreviewFrame(CGRectMake(11.8, 551.3, 33, 33), CGPointMake(28.3, 567.8), 50.0, m1b, 1194, H, G, false, &on);
    Int("an icon-sized picture (Settings' on the M1) stays on its icon", on, 1);
    Frame("  ... centred on it", lp, CGRectMake(11.8, 551.3, 33, 33));
    lp = MSBDArrowSidePreviewFrame(CGRectMake(0, 0, 44, 44), CGPointMake(29.9, 500), 59.8, CGRectMake(8, 40, 1350, 976), 1366, H, G, false, &on);
    Int("  ... with Gap to Screen Edge 0 too (the A12Z's 44 pt picture 7.9 pt from the edge)", on, 1);
    lp = MSBDArrowSidePreviewFrame(CGRectMake(0, 0, 60, 60), CGPointMake(28.3, 400), 50.0, m1b, 1194, H, G, false, &on);
    Int("  ... a picture that would reach the menu's place is moved", on, 0);
    lp = MSBDArrowSidePreviewFrame(CGRectNull, CGPointMake(28.3, 400), 50.0, m1b, 1194, H, G, false, &on);
    Int("  ... no picture: nothing moved", on, 1);

    // ---- 1.8.2.2: the item order beside a side Dock (iPad 2 F1): every side menu takes the attachment of a menu below its source ----
    Int("UIKit attached a menu above its source at its top edge (1): below is the bottom edge (4)", (int)MSBDCtxAttachmentBelow(1, true), 4);
    Int("  ... or the other way round, at its bottom edge (4): below is 1", (int)MSBDCtxAttachmentBelow(4, true), 1);
    Int("  ... a menu UIKit put below already keeps its attachment (top edge)", (int)MSBDCtxAttachmentBelow(1, false), 1);
    Int("  ... (bottom edge)", (int)MSBDCtxAttachmentBelow(4, false), 4);
    Int("  ... a side attachment or anything else: nothing changed", (int)(MSBDCtxAttachmentBelow(2, true) | MSBDCtxAttachmentBelow(8, false) | MSBDCtxAttachmentBelow(0, true)), 0);
    p = MSBDArrowPathCreate(W, H, 1.0, MSBDArrowRight, false);
    pb = CGPathGetPathBoundingBox(p);
    Frame("the right arrow's outline fills its view: the band on its left, 9 pt to the tip, 20 tall", pb, CGRectMake(0, 0, H + 1.0, W));
    Int("  ... the tip at the right's middle", CGPathContainsPoint(p, NULL, CGPointMake(H + 1.0 - 0.6, W / 2.0), false), 1);
    Int("  ... its band on the menu's side", CGPathContainsPoint(p, NULL, CGPointMake(0.5, 1.0), false), 1);
    CGPathRelease(p);
    p = MSBDArrowPathCreate(W, H, 1.0, MSBDArrowLeft, false);
    pb = CGPathGetPathBoundingBox(p);
    Frame("the left arrow's outline: the same box", pb, CGRectMake(0, 0, H + 1.0, W));
    Int("  ... the tip at the left's middle", CGPathContainsPoint(p, NULL, CGPointMake(0.6, W / 2.0), false), 1);
    Int("  ... its band on the menu's side", CGPathContainsPoint(p, NULL, CGPointMake(H + 0.5, 1.0), false), 1);
    CGPathRelease(p);
    printf("%s: %d/%d checks pass\n", fails ? "test-menuarrow FAILED" : "test-menuarrow", checks - fails, checks);
    return fails ? 1 : 0;
}
