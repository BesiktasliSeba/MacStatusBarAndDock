// Mac test of About This iPad's window against macOS 27's About This Mac (statusbar/AboutWindow.h, 1.8.1 item 6): the window's size and places
// for macOS's own five rows and three fine print lines are the ones measured on Apple's picture (280 x 503 points), the colours show as the
// picture's, and the iPad drawn has the proportions of the iPads it stands for. Run by test-aboutwindow.sh.
#include <stdio.h>
#include <math.h>
#include <stdlib.h>
#include "../statusbar/AboutWindow.h"
static int fails = 0, checks = 0;
#define CHECK(c, what) do { checks++; if (!(c)) { fails++; printf("FAIL %s:%d %s\n", __FILE__, __LINE__, what); } } while (0)
#define NEAR(a, b, tol) (fabs((double)(a) - (double)(b)) <= (tol))
static int SameRGB(MSBDAboutRGBA c, MSBDAboutRGBA w, int r, int g, int b) { int o[3]; MSBDAboutOnWindow(c, w, o); return abs(o[0] - r) <= 2 && abs(o[1] - g) <= 2 && abs(o[2] - b) <= 2; }
int main(void) {
    const MSBDAboutMetrics *m = &kMSBDAboutMac;
    // macOS's own window: five rows (Chip, Memory, Startup disk, Serial number, macOS), its regulatory link and two copyright lines
    MSBDAboutPlan p = MSBDAboutLayout(m, 5, 1, 3, 1);
    CHECK(m->width == 280.0 && NEAR(p.height, 503.0, 1.0), "the window: 280 x 503 points, as macOS's");
    CHECK(NEAR(p.titleCapTop, 236.5, 0.75) && NEAR(p.subtitleCapTop, 263.5, 0.75), "the name and the second line where macOS has them");
    CHECK(NEAR(p.firstRowCapTop, 296.5, 0.75) && NEAR(p.lastRowCapTop, 360.5, 0.75), "the first and the fifth row");
    CHECK(NEAR(p.buttonTop, 392.0, 0.75) && NEAR(p.buttonTop + m->buttonHeight, 415.5, 0.75), "More Info…: 24 high at 392");
    CHECK(NEAR(p.finePrintCapTop, 432.5, 0.75), "the fine print under the button");
    CHECK(m->titleSize == 22.0 && m->subtitleSize == 10.0 && m->rowSize == 11.0 && m->buttonTextSize == 13.0 && m->finePrintSize == 11.0, "type sizes: 22 bold, 10, 11, 13, 11");
    CHECK(m->labelRight == 118.0 && m->valueLeft == 129.5 && m->rowPitch == 16.0, "the rows' columns and pitch");
    CHECK(m->lightDiameter == 14.0 && NEAR(m->lightFirstX, 15.75, 0.1) && m->lightPitch == 23.0 && m->pictureWidth == 150.0 && m->pictureCenterY == 140.0, "lights and picture");
    // ours: rows in two groups, no fine print: the button ends the window a bottom margin under it; a group gap only between groups
    MSBDAboutPlan q = MSBDAboutLayout(m, 14, 2, 0, 1);
    CHECK(NEAR(q.lastRowCapTop, 296.5 + 13 * 16.0 + 12.0, 0.01) && NEAR(q.height, q.buttonTop + 24.0 + 31.0, 0.01), "two groups, no fine print");
    CHECK(NEAR(MSBDAboutLayout(m, 3, 1, 0, 0).firstRowCapTop, 236.5 + 33.0, 0.01), "no second line: the rows move up under the name");
    // colours as the picture shows them (light), and dark: the same opacities, white on the dark window
    const MSBDAboutColors *L = &kMSBDAboutLight, *D = &kMSBDAboutDark;
    CHECK(SameRGB(L->title, L->window, 77, 77, 77) && SameRGB(L->label, L->window, 77, 77, 77), "name and labels #4D4D4D");
    CHECK(SameRGB(L->value, L->window, 153, 153, 153), "values #999999");
    CHECK(SameRGB(L->subtitle, L->window, 177, 177, 177) && SameRGB(L->finePrint, L->window, 177, 177, 177), "second line and fine print #B1B1B1");
    CHECK(SameRGB(L->link, L->window, 189, 189, 189), "a link #BDBDBD");
    CHECK(SameRGB(L->button, L->window, 238, 238, 238) && SameRGB(L->buttonText, L->window, 0, 0, 0), "the button #EEEEEE, black text");
    CHECK(SameRGB(L->window, L->window, 255, 255, 255) && SameRGB(D->window, D->window, 30, 30, 30), "the window: white / #1E1E1E");
    CHECK(D->title.a == L->title.a && D->value.a == L->value.a && D->subtitle.a == L->subtitle.a && D->title.r == 1.0, "dark: white text with light's opacities");
    // the iPads drawn: the M1's 11-inch (2388 x 1668, Face ID) and the iPad 2's 9.7-inch (2048 x 1536, Home button), 150 wide
    MSBDAboutIPad a = MSBDAboutIPadShape(150.0, 1668.0, 2388.0, 0), b = MSBDAboutIPadShape(150.0, 2048.0, 1536.0, 1);
    CHECK(NEAR(150.0 / a.height, 247.6 / 178.5, 0.03) && a.homeRadius == 0.0 && a.screenCorner > 0.0, "the 11-inch's outline (247.6 x 178.5 mm), no Home button");
    CHECK(NEAR(150.0 / b.height, 240.0 / 169.5, 0.03) && b.homeRadius > 0.0 && b.bezelSide > b.bezelTop, "the 9.7-inch's outline (240 x 169.5 mm), its Home button bezel");
    CHECK(NEAR(MSBDAboutIPadShape(150.0, 0.0, 0.0, 0).height, MSBDAboutIPadShape(150.0, 4.0, 3.0, 0).height, 0.01), "an unknown screen: 4:3");
    printf("aboutwindow: %d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
