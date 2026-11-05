// AboutWindow.h -- About This iPad as macOS's About This Mac (1.8.1 item 6, KT): its window size, the big device picture, the name's and the
// rows' type sizes, the grey secondary text, the More Info… button, light and dark, and the spacing. Plain C: StatusBar.x DMShowAbout builds the
// window from these numbers; the Mac test (tools/test-aboutwindow.sh) checks them against macOS.
// The numbers are macOS 27's own About This Mac, measured on Apple's published picture of it (support.apple.com/109033, 4 Nov 2026: a 560 x 1006
// pixel window at 2x, so 280 x 503 points, in points below): the window 280 wide with a 16 pt continuous corner and a hairline edge, 14 pt traffic
// lights 23 apart (only the red one lit), the picture 150 wide centred 140 from the top, the name in 22 pt bold, the second line in 10 pt, the
// rows in 11 pt on a 16 pt pitch with the labels ending 118 from the left and the values starting at 129.5, the More Info… button 24 high with
// 13 pt text and 13 pt either side, and the fine print under it in 11 pt on a 14.5 pt pitch. Vertical places are cap tops (the top of a capital).
// Colours (light) are the picture's own: the name and the labels #4D4D4D, the values #999999, the second line and the fine print #B1B1B1, a link
// #BDBDBD underlined, the button #EEEEEE with black text, the window white. Dark takes macOS's way of mirroring them: white text with the same
// opacities on a #1E1E1E window.
// What is ours and not macOS's: the rows themselves (an iPad's chip, memory, storage, serial number and iPadOS, the two virtualization lines
// centred as before, then the jailbreak's rows after a gap), the iPad drawn in place of the Mac's photograph, and our virtualization note as the
// fine print (macOS's place for its regulatory link and copyright lines, which are Apple's and not shown).
#pragma once

typedef struct {
    double width, corner;
    double lightDiameter, lightFirstX, lightPitch, lightY;          // (centres)
    double pictureWidth, pictureCenterY;
    double titleSize, titleCapFromPictureCenter;
    double subtitleSize, subtitleCapFromTitle;
    double rowSize, firstRowFromSubtitle, rowPitch, groupGap;
    double labelRight, valueLeft, sideMargin;
    double buttonFromLastRow, buttonHeight, buttonRadius, buttonPad, buttonTextSize, buttonTouchHeight;
    double finePrintFromButton, finePrintSize, finePrintPitch, bottomMargin;
} MSBDAboutMetrics;
static const MSBDAboutMetrics kMSBDAboutMac = {
    280.0, 16.0,
    14.0, 15.75, 23.0, 15.75,
    150.0, 140.0,
    22.0, 96.5,
    10.0, 27.0,
    11.0, 33.0, 16.0, 12.0,
    118.0, 129.5, 12.0,
    31.5, 24.0, 5.5, 13.0, 13.0, 40.0,
    40.5, 11.0, 14.5, 31.0,
};

// Where everything goes for `rows` rows in `groups` groups (a gap between groups), `finePrintLines` lines of fine print (0: none), with or
// without the second line: cap tops of the name, the second line, the first row and the first fine print line, the button's top, and the window's
// height. A row's cap top: firstRowCapTop + its index * rowPitch + the groups before it * groupGap.
typedef struct { double titleCapTop, subtitleCapTop, firstRowCapTop, lastRowCapTop, buttonTop, finePrintCapTop, height; } MSBDAboutPlan;
static inline MSBDAboutPlan MSBDAboutLayout(const MSBDAboutMetrics *m, int rows, int groups, int finePrintLines, int hasSubtitle) {
    MSBDAboutPlan p;
    p.titleCapTop = m->pictureCenterY + m->titleCapFromPictureCenter;
    p.subtitleCapTop = p.titleCapTop + m->subtitleCapFromTitle;
    p.firstRowCapTop = (hasSubtitle ? p.subtitleCapTop : p.titleCapTop) + m->firstRowFromSubtitle;
    int n = rows > 0 ? rows : 0, g = groups > 1 ? groups - 1 : 0;
    p.lastRowCapTop = n ? p.firstRowCapTop + (n - 1) * m->rowPitch + g * m->groupGap : p.firstRowCapTop - m->rowPitch;
    p.buttonTop = p.lastRowCapTop + m->buttonFromLastRow;
    p.finePrintCapTop = p.buttonTop + m->finePrintFromButton;
    // (the window ends a bottom margin under the last line's descent: 0.35 em under its cap top's baseline, as macOS's fine print sits)
    double last = finePrintLines > 0 ? p.finePrintCapTop + (finePrintLines - 1) * m->finePrintPitch + m->finePrintSize * 0.705 + m->finePrintSize * 0.25
                                     : p.buttonTop + m->buttonHeight;
    p.height = last + m->bottomMargin;
    return p;
}

// The window's colours as RGBA, light and dark (see above).
typedef struct { double r, g, b, a; } MSBDAboutRGBA;
typedef struct { MSBDAboutRGBA window, edge, title, label, value, subtitle, finePrint, link, button, buttonText, lightOff, lightOffEdge; } MSBDAboutColors;
static const MSBDAboutColors kMSBDAboutLight = {
    {1.0, 1.0, 1.0, 1.0}, {210 / 255.0, 210 / 255.0, 215 / 255.0, 1.0},
    {0.0, 0.0, 0.0, 0.698}, {0.0, 0.0, 0.0, 0.698}, {0.0, 0.0, 0.0, 0.4}, {0.0, 0.0, 0.0, 0.306}, {0.0, 0.0, 0.0, 0.306}, {0.0, 0.0, 0.0, 0.259},
    {0.0, 0.0, 0.0, 0.067}, {0.0, 0.0, 0.0, 1.0},
    {237 / 255.0, 238 / 255.0, 241 / 255.0, 1.0}, {0.0, 0.0, 0.0, 0.2},
};
static const MSBDAboutColors kMSBDAboutDark = {
    {30 / 255.0, 30 / 255.0, 30 / 255.0, 1.0}, {1.0, 1.0, 1.0, 0.15},
    {1.0, 1.0, 1.0, 0.698}, {1.0, 1.0, 1.0, 0.698}, {1.0, 1.0, 1.0, 0.4}, {1.0, 1.0, 1.0, 0.306}, {1.0, 1.0, 1.0, 0.306}, {1.0, 1.0, 1.0, 0.259},
    {1.0, 1.0, 1.0, 0.12}, {1.0, 1.0, 1.0, 0.85},
    {1.0, 1.0, 1.0, 0.16}, {1.0, 1.0, 1.0, 0.12},
};
// A colour as it shows on the window (alpha over the window's own colour), 0-255 per channel: what the Mac test compares with the picture.
static inline void MSBDAboutOnWindow(MSBDAboutRGBA c, MSBDAboutRGBA w, int out[3]) {
    out[0] = (int)(255.0 * (c.r * c.a + w.r * (1.0 - c.a)) + 0.5);
    out[1] = (int)(255.0 * (c.g * c.a + w.g * (1.0 - c.a)) + 0.5);
    out[2] = (int)(255.0 * (c.b * c.a + w.b * (1.0 - c.a)) + 0.5);
}

// The iPad as drawn (landscape, the camera on the left like the Magic Keyboard holds it): its outline and screen in points for a picture of
// `width`, from the screen's own shape (native pixels, either way round). Home button iPads: wide bezels left and right (9 % of the width each, the
// 9.7-inch's), the Home button in the right one; Face ID iPads: an even 4.5 % bezel and rounded screen corners.
typedef struct { double width, height, corner, bezelSide, bezelTop, screenCorner, homeRadius; } MSBDAboutIPad;
static inline MSBDAboutIPad MSBDAboutIPadShape(double width, double screenW, double screenH, int homeButton) {
    MSBDAboutIPad d;
    double aspect = (screenW > screenH ? screenW / screenH : screenH / screenW);
    if (!(aspect > 1.0 && aspect < 2.5)) aspect = 4.0 / 3.0;
    d.width = width;
    d.bezelSide = width * (homeButton ? 0.09 : 0.045);
    d.bezelTop = width * 0.045;
    double sw = width - 2.0 * d.bezelSide;
    d.height = sw / aspect + 2.0 * d.bezelTop;
    d.corner = width * (homeButton ? 0.065 : 0.06);
    d.screenCorner = homeButton ? 0.0 : width * 0.018;
    d.homeRadius = homeButton ? width * 0.022 : 0.0;
    return d;
}
