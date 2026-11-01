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
    printf("%s: %d/%d checks pass\n", fails ? "test-menuarrow FAILED" : "test-menuarrow", checks - fails, checks);
    return fails ? 1 : 0;
}
