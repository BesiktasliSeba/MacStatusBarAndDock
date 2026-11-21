// test-dockcolor.m -- Dock Background (1.8.8.1 DOCKCOLOR), run by tools/test-dockcolor.sh: "rule" checks common/DockColor.h (the stored choice,
// the colour and its first time, and the marks rule over the material measured on iPadOS 15, 16, 17 and 18 -- the M1 15.6.1, the iPad 2 16.7.7,
// the 17.5 17.5.1 and the A12Z 18.5, kTMaterial -- every opacity from 0 to 100 %), against a reckoning of its own (the WCAG maths written again
// here, not BatteryInside.h's), so a copy of the header made to fail is caught, and so is a measured row the header's range does not cover.
// Built with TDC_DOCK (Mac Catalyst's UIKit): the real dock/DockColor.m and dock/DockStyle.m, and the Dock's divider code cut out of dock/Dock.x,
// against stand-ins for SpringBoard's Dock (its window, Dock view, platter, Apple's material and divider, icons with their running dots, Finder),
// one scenario per run (their globals are the Dock part's own); preferences in scratch domains the script gives and removes.
#import <Foundation/Foundation.h>
#include <math.h>
#include "DockColor.h"

static int gFails, gChecks;
static void Check(BOOL ok, NSString *what) { gChecks++; if (!ok) gFails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }

// ---- the reckoning of our own: sRGB blend over the measured material, WCAG luminance and contrast ----
static double TLin(double c) { return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4); }
static double TLum(double r, double g, double b) { return 0.2126 * TLin(r) + 0.7152 * TLin(g) + 0.0722 * TLin(b); }
static double TRatio(double a, double b) { double hi = fmax(a, b), lo = fmin(a, b); return (hi + 0.05) / (lo + 0.05); }
typedef struct { double lo, hi; } TRange;
// The Dock material as measured, one row per iPad (plans/release-1.8.7.6.md, the "DOCKCOLOR material measured" sections): sRGB grey over a solid
// black and a solid white Desktop Picture, the darkest and the lightest, Light Mode then Dark Mode. Frosted: its blur alone (the A12Z's Frosted rows
// with our tint taken out). The reckoning takes the darkest and the lightest of every row of a layer, so a row that widens the range changes the
// reckoning's answers and the rule's cases fail until common/DockColor.h covers it.
typedef struct { const char *ios, *ipad; int frosted, light[2], dark[2]; } TMaterial;
static const TMaterial kTMaterial[] = {
    { "15.6.1", "the M1, Reduce Transparency off", 0, { 58, 246 }, { 37, 210 } },
    { "16.7.7", "the iPad 2, Reduce Transparency off", 0, { 59, 246 }, { 37, 210 } },
    { "17.5.1", "the 17.5, Reduce Transparency on", 0, { 59, 246 }, { 37, 210 } },
    { "18.5", "the A12Z, Reduce Transparency off", 0, { 58, 246 }, { 37, 210 } },
    { "18.5", "the A12Z", 1, { 142, 245 }, { 31, 126 } },
};
#define TMaterialRows ((int)(sizeof kTMaterial / sizeof kTMaterial[0]))
// ... and over KT's own pictures, Dock Style Default (not grey: the picture's colours through the material; with Reduce Transparency on, one flat colour)
static const struct { const char *ios, *ipad; int dark, rgb[3]; } kTOverPicture[] = {
    { "15.6.1", "the M1", 0, { 82, 97, 92 } }, { "15.6.1", "the M1", 1, { 27, 40, 36 } },
    { "16.7.7", "the iPad 2", 0, { 168, 100, 120 } }, { "16.7.7", "the iPad 2", 1, { 92, 32, 49 } },
    { "17.5.1", "the 17.5, one flat colour", 0, { 238, 160, 73 } }, { "17.5.1", "the 17.5, one flat colour", 1, { 145, 76, 0 } },
    { "18.5", "the A12Z", 0, { 136, 139, 153 } }, { "18.5", "the A12Z", 1, { 62, 64, 76 } },
};
static TRange TRow(const TMaterial *m, int dark) { const int *v = dark ? m->dark : m->light; return (TRange){ v[0] / 255.0, v[1] / 255.0 }; }
static TRange TMeasured(int frosted, int dark) {   // (the darkest and the lightest over every iPadOS measured for that layer)
    TRange u = { 1, 0 };
    for (int m = 0; m < TMaterialRows; m++) if (kTMaterial[m].frosted == frosted) { TRange r = TRow(&kTMaterial[m], dark); u.lo = fmin(u.lo, r.lo); u.hi = fmax(u.hi, r.hi); }
    return u;
}
static double TOver(double c, double a, double behind) { return a * c + (1 - a) * behind; }
// the worst contrast black and white each get on the colour at a over the range: the Dock's marks must be the better of the two at its worst
static void TWorst(const double rgb[3], double a, TRange u, double *black, double *white) {
    double dark = TLum(TOver(rgb[0], a, u.lo), TOver(rgb[1], a, u.lo), TOver(rgb[2], a, u.lo));
    double light = TLum(TOver(rgb[0], a, u.hi), TOver(rgb[1], a, u.hi), TOver(rgb[2], a, u.hi));
    *black = TRatio(dark, 0); *white = TRatio(light, 1);
}

static void Rule(void) {
    printf("== the stored choice and colour\n");
    Check(MSBDDockBackgroundOn("color") && !MSBDDockBackgroundOn("auto") && !MSBDDockBackgroundOn("") && !MSBDDockBackgroundOn(NULL) && !MSBDDockBackgroundOn("Color"),
          @"Background: \"color\" is Color; \"auto\", anything else or nothing stored is Automatic");
    Check(!strcmp(kMSBDDockBackgroundKey, "dockBackground") && !strcmp(kMSBDDockBackgroundColorKey, "dockBackgroundColor") && !strcmp(kMSBDDockBackgroundOpacityKey, "dockBackgroundOpacity")
          && !strcmp(kMSBDDockColorNote, "com.besiktasliseba.dockmagnification/colorChanged"), @"  ... the keys and the light note, as Settings writes and posts them");
    Check(MSBDDockColorOpacity(0, 0.2) == 0.7 && MSBDDockColorOpacity(1, 0.2) == 0.2 && MSBDDockColorOpacity(1, 1.5) == 1 && MSBDDockColorOpacity(1, -1) == 0 && MSBDDockColorOpacity(1, NAN) == 0,
          @"Opacity: 0.7 never set (the menu bar's), else kept to 0 .. 1 (NaN, below 0: 0)");
    double c[3] = { -1, -1, -1 };
    BOOL p1 = MSBDDockColorParse("#242225", c) && fabs(c[0] - 0x24 / 255.0) < 1e-9 && fabs(c[1] - 0x22 / 255.0) < 1e-9 && fabs(c[2] - 0x25 / 255.0) < 1e-9;
    BOOL p2 = MSBDDockColorParse(" ff3b30 ", c) && fabs(c[0] - 1) < 1e-9 && fabs(c[1] - 0x3b / 255.0) < 1e-9;
    BOOL p3 = MSBDDockColorParse("#FFF", c) && c[0] == 1 && c[1] == 1 && c[2] == 1;
    double keep[3] = { 0.5, 0.5, 0.5 };
    BOOL bad = !MSBDDockColorParse("#12345", keep) && !MSBDDockColorParse("#GGGGGG", keep) && !MSBDDockColorParse("", keep) && !MSBDDockColorParse(NULL, keep)
            && !MSBDDockColorParse("#1234567", keep) && !MSBDDockColorParse("#123456 x", keep) && keep[0] == 0.5 && keep[1] == 0.5 && keep[2] == 0.5;
    Check(p1 && p2 && p3 && bad, @"a colour reads from \"#RRGGBB\" or \"#RGB\" (# and spaces optional); anything else is refused and changes nothing");
    char hex[8]; double w[3] = { 1, 0x3b / 255.0, 0x30 / 255.0 }, o[3] = { 2, NAN, -0.5 }, h[3] = { 0.5 / 255.0 + 1e-9, 254.49 / 255.0, 0.5 };
    MSBDDockColorFormat(w, hex); BOOL f1 = !strcmp(hex, "#FF3B30");
    MSBDDockColorFormat(o, hex); BOOL f2 = !strcmp(hex, "#FF0000");
    MSBDDockColorFormat(h, hex); BOOL f3 = !strcmp(hex, "#01FE80");
    Check(f1 && f2 && f3, @"  ... and is stored as \"#RRGGBB\", each channel kept to 0 .. 1 and rounded (as the colour well writes it)");
    double s[3];
    BOOL s1 = MSBDDockColorStart("#FFFFFF", "#FF0000", s) == 1 && s[0] == 1 && s[1] == 1;
    BOOL s2 = MSBDDockColorStart(NULL, "#FF0000", s) == 0 && s[0] == 1 && s[1] == 0 && s[2] == 0;
    BOOL s3 = MSBDDockColorStart("nonsense", "#00FF00", s) == 0 && s[0] == 0 && s[1] == 1;
    BOOL s4 = MSBDDockColorStart(NULL, NULL, s) == 0 && fabs(s[0] - 0x24 / 255.0) < 1e-9 && fabs(s[2] - 0x25 / 255.0) < 1e-9;
    BOOL s5 = MSBDDockColorStart(NULL, "#12", s) == 0 && fabs(s[1] - 0x22 / 255.0) < 1e-9;
    Check(s1 && s2 && s3 && s4 && s5, @"the Dock's colour: its own once stored; never stored, Status Bar Background's as stored now, else #242225 (KT's decision 3: it starts as the menu bar's)");
    char st[8] = "same";
    BOOL f1s = MSBDDockColorFirstStore(NULL, "#FF3B30", st) == 1 && !strcmp(st, "#FF3B30");
    BOOL f2s = MSBDDockColorFirstStore(NULL, NULL, st) == 1 && !strcmp(st, "#242225");
    BOOL f3s = MSBDDockColorFirstStore("x", " fff ", st) == 1 && !strcmp(st, "#FFFFFF");
    strcpy(st, "same");
    BOOL f4s = MSBDDockColorFirstStore("#00FF00", "#FF3B30", st) == 0 && !strcmp(st, "same");
    Check(f1s && f2s && f3s && f4s, @"Settings, Color chosen the first time: Status Bar Background's colour (else #242225) stored as the Dock's own; once stored, nothing (no live link)");

    printf("== the marks rule over the measured material (B2): one answer, the better ink at its worst, iPadOS's own when it is the mode's\n");
    const unsigned colors[] = { 0xFFFFFF, 0x000000, 0x242225, 0xFF3B30, 0x007AFF, 0x808080, 0x34C759, 0xFFCC00, 0xAF52DE, 0x1C1C1E, 0xF2F2F7, 0x5856D6 };
    int n = (int)(sizeof colors / sizeof colors[0]), wrong = 0, cases = 0, worse = 0;
    NSMutableString *firstWrong = [NSMutableString string];
    for (int under = 0; under < 2; under++) for (int dark = 0; dark < 2; dark++) for (int i = 0; i < n; i++) for (int k = 0; k <= 20; k++) {
        double rgb[3], a = k / 20.0, bw, ww;
        MSBDDockColorFromInt(colors[i], rgb);
        TWorst(rgb, a, TMeasured(under, dark), &bw, &ww);
        int wantDark = bw >= ww, want = wantDark == !dark ? MSBDDockMarksApple : wantDark;
        int got = MSBDDockMarks(1, rgb[0], rgb[1], rgb[2], a, under, dark);
        cases++;
        if (got != want) { if (!wrong) [firstWrong appendFormat:@" (first: #%06X at %.2f, %s, %s: got %d, want %d)", colors[i], a, under ? "Frosted" : "Default", dark ? "Dark" : "Light", got, want]; wrong++; }
        int shownDark = got == MSBDDockMarksApple ? !dark : got;   // (what is drawn: iPadOS's own or ours)
        if ((shownDark ? bw : ww) + 1e-9 < (shownDark ? ww : bw)) worse++;
    }
    Check(!wrong, [NSString stringWithFormat:@"%d cases (12 colours x 21 opacities x Light/Dark x Default/Frosted): the answer is the reckoning's%@", cases, firstWrong]);
    Check(!worse, @"  ... in every case the marks drawn read at least as well at their worst as the other ink would (no \"in between\" left to the material)");

    printf("== the material under it, measured on every iPadOS: one range covers 15.6.1, 16.7.7, 17.5.1 and 18.5\n");
    int seen[4] = { 0 };
    for (int m = 0; m < TMaterialRows; m++) {
        const TMaterial *t = &kTMaterial[m];
        int major = atoi(t->ios);
        if (!t->frosted && major >= 15 && major <= 18) seen[major - 15] = 1;
        MSBDDockUnder ul = MSBDDockUnderRange(t->frosted, 0), ud = MSBDDockUnderRange(t->frosted, 1);
        long l0 = lround(ul.darkest * 255), l1 = lround(ul.lightest * 255), d0 = lround(ud.darkest * 255), d1 = lround(ud.lightest * 255);
        Check(l0 <= t->light[0] && l1 >= t->light[1] && d0 <= t->dark[0] && d1 >= t->dark[1],
              [NSString stringWithFormat:@"iPadOS %s (%s), %s: Light %d to %d, Dark %d to %d, inside the rule's range (Light %ld to %ld, Dark %ld to %ld)", t->ios, t->ipad,
               t->frosted ? "Frosted's blur" : "Dock Style Default", t->light[0], t->light[1], t->dark[0], t->dark[1], l0, l1, d0, d1]);
    }
    Check(seen[0] && seen[1] && seen[2] && seen[3], @"  ... Dock Style Default measured on iPadOS 15, 16, 17 and 18");
    int pictures = (int)(sizeof kTOverPicture / sizeof kTOverPicture[0]), outside = 0;
    NSMutableString *firstOut = [NSMutableString string];
    for (int p = 0; p < pictures; p++) {
        const int *v = kTOverPicture[p].rgb;
        TRange u = TMeasured(0, kTOverPicture[p].dark);
        double l = TLum(v[0] / 255.0, v[1] / 255.0, v[2] / 255.0);
        if (l + 1e-9 < TLum(u.lo, u.lo, u.lo) || l - 1e-9 > TLum(u.hi, u.hi, u.hi)) {
            if (!outside) [firstOut appendFormat:@" (first: iPadOS %s, %s, %s: %d,%d,%d at %.4f)", kTOverPicture[p].ios, kTOverPicture[p].ipad, kTOverPicture[p].dark ? "Dark" : "Light", v[0], v[1], v[2], l];
            outside++;
        }
    }
    Check(!outside, [NSString stringWithFormat:@"  ... the material over KT's own pictures (%d rows, Light and Dark, 15.6.1 to 18.5; with Reduce Transparency on one flat colour, not grey) is inside that range by luminance%@", pictures, firstOut]);
    // (not grey, so one channel can sit below the grey's: the M1's 27,40,36 in Dark Mode. The marks drawn over it may then read a little below the
    // worst reckoned over the grey range; a near tie, under 0.1:1, is what the grey range is trusted for)
    double below = 0; NSString *belowAt = @"";
    for (int p = 0; p < pictures; p++) for (int i = 0; i < n; i++) for (int k = 0; k <= 20; k++) {
        int dark = kTOverPicture[p].dark; const int *v = kTOverPicture[p].rgb;
        double rgb[3], a = k / 20.0, bw, ww; MSBDDockColorFromInt(colors[i], rgb);
        TWorst(rgb, a, TMeasured(0, dark), &bw, &ww);
        int got = MSBDDockMarks(1, rgb[0], rgb[1], rgb[2], a, 0, dark), shownDark = got == MSBDDockMarksApple ? !dark : got;
        double l = TLum(TOver(rgb[0], a, v[0] / 255.0), TOver(rgb[1], a, v[1] / 255.0), TOver(rgb[2], a, v[2] / 255.0));
        double s = (shownDark ? bw : ww) - TRatio(l, shownDark ? 0 : 1);
        if (s > below) { below = s; belowAt = [NSString stringWithFormat:@"iPadOS %s, %s, %s, #%06X at %.2f", kTOverPicture[p].ios, kTOverPicture[p].ipad, dark ? "Dark" : "Light", colors[i], a]; }
    }
    Check(below < 0.1, [NSString stringWithFormat:@"  ... over each of them the marks drawn read no more than 0.1:1 below their worst over the range (at most %.3f:1%@%@)", below, below > 0 ? @", " : @"", belowAt]);
    // (one range for all, not one per iPadOS: over each iPadOS's own range the marks drawn are the better ink at their worst, or a near tie under 0.1:1)
    for (int m = 0; m < TMaterialRows; m++) {
        const TMaterial *t = &kTMaterial[m];
        int ties = 0, all = 0; double most = 0;
        for (int dark = 0; dark < 2; dark++) for (int i = 0; i < n; i++) for (int k = 0; k <= 20; k++) {
            double rgb[3], a = k / 20.0, bw, ww;
            MSBDDockColorFromInt(colors[i], rgb);
            TWorst(rgb, a, TRow(t, dark), &bw, &ww);
            int got = MSBDDockMarks(1, rgb[0], rgb[1], rgb[2], a, t->frosted, dark), shownDark = got == MSBDDockMarksApple ? !dark : got;
            double behind = (shownDark ? ww : bw) - (shownDark ? bw : ww);
            all++;
            if (behind > 1e-9) { ties++; most = fmax(most, behind); }
        }
        Check(most < 0.1, [NSString stringWithFormat:@"  ... over iPadOS %s's own range (%s, %s) the marks drawn are the better ink at their worst or under 0.1:1 behind it (%d of %d cases behind, at most %.3f:1): no range of its own needed",
              t->ios, t->ipad, t->frosted ? "Frosted" : "Default", ties, all, most]);
    }
    int at0 = 1, notShown = 1;
    for (int under = 0; under < 2; under++) for (int dark = 0; dark < 2; dark++) for (int i = 0; i < n; i++) {
        double rgb[3]; MSBDDockColorFromInt(colors[i], rgb);
        if (MSBDDockMarks(1, rgb[0], rgb[1], rgb[2], 0, under, dark) != MSBDDockMarksApple || MSBDDockMarks(1, rgb[0], rgb[1], rgb[2], NAN, under, dark) != MSBDDockMarksApple
            || MSBDDockMarks(1, rgb[0], rgb[1], rgb[2], -2, under, dark) != MSBDDockMarksApple) at0 = 0;
        if (MSBDDockMarks(0, rgb[0], rgb[1], rgb[2], 1, under, dark) != MSBDDockMarksApple) notShown = 0;
    }
    Check(at0, @"at 0 % (and a NaN or negative opacity) iPadOS's own marks, in both modes, over both layers: the material decides alone, as stock");
    Check(notShown, @"our colour not drawn (Automatic, Glass Shelf): iPadOS's own marks, whatever the colour");
    double over1[3], is1[3];
    MSBDDockColorFromInt(0xFFCC00, over1); MSBDDockColorFromInt(0xFFCC00, is1);
    Check(MSBDDockMarks(1, over1[0], over1[1], over1[2], 7, 0, 1) == MSBDDockMarks(1, is1[0], is1[1], is1[2], 1, 0, 1), @"  ... an opacity over 1 is 100 %");
    // (named rows: what a user sees, Light / Dark, Dock Style Default -- the table in plans/release-1.8.7.6.md "DOCKCOLOR build status")
    struct { unsigned rgb; double a; int under, dark, want; const char *what; } rows[] = {
        { 0xFFFFFF, 1.0, 0, 0, MSBDDockMarksApple, "white 100 %, Light: iPadOS's own (black dots)" },
        { 0xFFFFFF, 1.0, 0, 1, MSBDDockMarksDark, "white 100 %, Dark: ours, black dots and dark dividers" },
        { 0xFFFFFF, 0.3, 0, 1, MSBDDockMarksDark, "white 30 %, Dark: ours, black (the material can be 37 under it)" },
        { 0x242225, 0.7, 0, 0, MSBDDockMarksLight, "#242225 70 % (the menu bar's default), Light: ours, white dots" },
        { 0x242225, 0.6, 0, 0, MSBDDockMarksLight, "  ... 60 %: the same (stable around the default, critique P1)" },
        { 0x242225, 0.8, 0, 0, MSBDDockMarksLight, "  ... 80 %: the same" },
        { 0x242225, 0.7, 0, 1, MSBDDockMarksApple, "#242225 70 %, Dark: iPadOS's own (white)" },
        { 0xFF3B30, 0.5, 0, 0, MSBDDockMarksApple, "#FF3B30 50 %, Light: iPadOS's own (black)" },
        { 0xFF3B30, 0.5, 0, 1, MSBDDockMarksDark, "#FF3B30 50 %, Dark: ours, black" },
        { 0xFF3B30, 0.2, 0, 1, MSBDDockMarksApple, "#FF3B30 20 %, Dark: iPadOS's own (white)" },
        { 0x007AFF, 1.0, 0, 1, MSBDDockMarksDark, "#007AFF 100 %, Dark: ours, black (5.0:1 against white's 4.2:1)" },
        { 0x000000, 0.5, 0, 0, MSBDDockMarksLight, "black 50 %, Light: ours, white" },
        { 0x000000, 0.3, 1, 0, MSBDDockMarksApple, "black 30 % over Frosted's blur, Light: iPadOS's own (Frosted's layer is lighter: 142 to 245)" },
        { 0x000000, 0.3, 0, 0, MSBDDockMarksLight, "  ... the same over iPadOS's material: ours, white (58 to 246)" },
        { 0xFFFFFF, 0.1, 1, 1, MSBDDockMarksApple, "white 10 % over Frosted's blur, Dark: iPadOS's own" },
        { 0x34C759, 0.5, 1, 1, MSBDDockMarksDark, "#34C759 50 % over Frosted's blur, Dark: ours, black" },
    };
    for (size_t r = 0; r < sizeof rows / sizeof rows[0]; r++) {
        double rgb[3]; MSBDDockColorFromInt(rows[r].rgb, rgb);
        Check(MSBDDockMarks(1, rgb[0], rgb[1], rgb[2], rows[r].a, rows[r].under, rows[r].dark) == rows[r].want, @(rows[r].what));
    }
    double rgb[3], bw, ww; MSBDDockColorFromInt(0x242225, rgb);
    TWorst(rgb, 0.7, TMeasured(0, 0), &bw, &ww);
    double bw2, ww2; TWorst(rgb, 0.7, TMeasured(0, 1), &bw2, &ww2);
    Check(ww > 5.5 && ww2 > 6.5 && bw < 2 && bw2 < 2, [NSString stringWithFormat:@"  ... #242225 at 70 %%: white at its worst %.1f:1 in Light, %.1f:1 in Dark (black %.1f / %.1f)", ww, ww2, bw, bw2]);
    double g, al;
    MSBDDockMarkDot(MSBDDockMarksDark, &g, &al); BOOL d1 = g == 0 && al == 1;
    MSBDDockMarkDot(MSBDDockMarksLight, &g, &al); BOOL d2 = g == 1 && al == 1;
    MSBDDockMarkLine(MSBDDockMarksDark, &g, &al); BOOL l1 = g == 0 && al == 0.25;
    MSBDDockMarkLine(MSBDDockMarksLight, &g, &al); BOOL l2 = g == 1 && al == 0.30;
    Check(d1 && d2 && l1 && l2, @"our marks: dots black or white (iPadOS's labelColor, measured exact), divider lines black 0.25 or white 0.30");
    // (the measured line against the colour: about iPadOS's own 1.3 to 2.3:1 -- never lost, never louder than a mark)
    double wl = TLum(1, 1, 1), lineOnWhite = TLum(0.75, 0.75, 0.75), dk[3]; MSBDDockColorFromInt(0x242225, dk);
    double onDark = TLum(TOver(1, 0.3, dk[0]), TOver(1, 0.3, dk[1]), TOver(1, 0.3, dk[2])), dkl = TLum(dk[0], dk[1], dk[2]);
    Check(TRatio(wl, lineOnWhite) > 1.5 && TRatio(wl, lineOnWhite) < 2.5 && TRatio(onDark, dkl) > 1.5 && TRatio(onDark, dkl) < 3.0,
          [NSString stringWithFormat:@"  ... a divider line %.1f:1 on solid white, %.1f:1 on solid #242225 (iPadOS's own: 1.3 to 2.3:1)", TRatio(wl, lineOnWhite), TRatio(onDark, dkl)]);
}

#if TDC_DOCK
// ==== the Dock part (Mac Catalyst): the real DockColor.m and DockStyle.m, the dividers' code cut out of Dock.x (dockx-cut.m) ====
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include "DockStyle.h"
extern void DMDockStyleApply(UIView *platter);
extern void DMDockStyleSetChoice(int style);
extern void DMDockStyleRefreshAll(void);
extern void DMDockStyleDot(UIView *dot, UIView *iconView, CGFloat d);
extern void DMDockColorApply(UIView *platter);
extern void DMDockColorLoad(BOOL tweakOn);
extern void DMDockColorChanged(void);
extern void DMDockColorDividers(UIView *dockView);
#if DEBUG
extern void DMDockColorDebug(const char *word);
#endif
extern void DMSecondDividerAttach(UIView *dockView);   // (dockx-cut.m: Dock.x's own, made reachable there)
extern void DMDockSecondDividerLook(UIView *dockView);
extern CGRect gDivider2Rect;
extern BOOL gDivider2Alone;

static int gTBgReads, gTDividerReads, gTResyncs, gTWalks, gTFinderDots, gTPlatterLayouts;
static NSMutableArray<NSString *> *gTLog;
void DMLogWrite(NSString *line) { [gTLog addObject:line]; }
int DMDockStylePlatterSide(UIView *platter) { return 0; }
int MSBDDockSideIconTurnSide(UIView *icon) { return 0; }

// ---- SpringBoard's Dock, as the code reads it ----
@interface MTMaterialView : UIView @end   // (Apple's material, the platter's -backgroundView: a layer of its own inside, as its backdrop)
@implementation MTMaterialView @end
@interface SBFloatingDockPlatterView : UIView
@property (nonatomic, strong) UIView *tBackground, *tShadow;
@end
@implementation SBFloatingDockPlatterView
- (UIView *)backgroundView { gTBgReads++; return self.tBackground; }
- (UIView *)shadowView { return self.tShadow; }
@end
@interface SBFloatingDockView : UIView
@property (nonatomic, strong) UIView *tDivider;
@property (nonatomic, strong) SBFloatingDockPlatterView *mainPlatterView;
@end
@implementation SBFloatingDockView
- (UIView *)dividerView { gTDividerReads++; return self.tDivider; }   // (read by Dock.x's DMNativeDivider through KVC)
@end
@interface SBFloatingDockWindow : UIWindow @end
@implementation SBFloatingDockWindow @end
@interface TDot : UIView
@property (nonatomic) int writes;   // (colour writes after it was made: today's dot is written once, when made)
@end
@implementation TDot
- (void)setBackgroundColor:(UIColor *)c { self.writes++; [super setBackgroundColor:c]; }
@end
@interface SBIconView : UIView
@property (nonatomic, strong) TDot *dot;
@end
@implementation SBIconView @end
@interface DMFinderIconView : UIView
@property (nonatomic, strong) TDot *dot;
@end
@implementation DMFinderIconView
- (void)updateDot { gTFinderDots++; DMDockStyleDot(self.dot, self, 4); }   // (as FinderIcon.m's)
@end
static TDot *TMakeDot(UIView *in) {
    TDot *d = [[TDot alloc] initWithFrame:CGRectMake(20, 56, 4, 4)];
    d.backgroundColor = [UIColor labelColor]; d.writes = 0;   // (as RunningIndicator.m makes it)
    [in addSubview:d];
    return d;
}

typedef struct { __unsafe_unretained SBFloatingDockWindow *win; __unsafe_unretained SBFloatingDockView *dock; __unsafe_unretained SBFloatingDockPlatterView *platter;
                 __unsafe_unretained MTMaterialView *bg; __unsafe_unretained UIView *native, *shadow; __unsafe_unretained CALayer *appleMask, *backdrop;
                 __unsafe_unretained NSArray<SBIconView *> *icons; __unsafe_unretained DMFinderIconView *finder; } TDock;
static NSMutableArray *gTKeep;   // (keeps the world alive)
static NSMutableArray<SBFloatingDockWindow *> *gTWindows;
static NSArray *TAllWindows(id self, SEL _cmd, BOOL internal, BOOL visible) { gTWalks++; return gTWindows; }
static TDock TMakeDock(BOOL tv) {
    TDock t;
    SBFloatingDockWindow *w = [[SBFloatingDockWindow alloc] initWithFrame:tv ? CGRectMake(0, 0, 1920, 1080) : CGRectMake(0, 0, 1194, 834)];
    w.hidden = NO;
    SBFloatingDockView *dock = [[SBFloatingDockView alloc] initWithFrame:CGRectMake(100, 720, 900, 96)];
    [w addSubview:dock];
    SBFloatingDockPlatterView *p = [[SBFloatingDockPlatterView alloc] initWithFrame:dock.bounds];
    [dock addSubview:p]; dock.mainPlatterView = p;
    UIView *shadow = [[UIView alloc] initWithFrame:CGRectInset(p.bounds, -10, -10)];
    MTMaterialView *bg = [[MTMaterialView alloc] initWithFrame:p.bounds];
    bg.layer.cornerRadius = 31; bg.layer.cornerCurve = kCACornerCurveContinuous;
    CALayer *backdrop = [CALayer layer]; backdrop.frame = bg.bounds; [bg.layer addSublayer:backdrop];
    [p addSubview:shadow]; [p addSubview:bg];
    p.tBackground = bg; p.tShadow = shadow;
    UIView *list = [[UIView alloc] initWithFrame:p.bounds]; [p addSubview:list];
    NSMutableArray *icons = [NSMutableArray array];
    for (int i = 0; i < 3; i++) {
        SBIconView *iv = [[SBIconView alloc] initWithFrame:CGRectMake(20 + 90 * i, 10, 70, 76)];
        [list addSubview:iv]; iv.dot = TMakeDot(iv); [icons addObject:iv];
    }
    UIView *native = [[UIView alloc] initWithFrame:CGRectMake(560, 18, 1, 60)];
    native.backgroundColor = [UIColor colorWithWhite:0.5 alpha:1];
    [native.layer setValue:@"plusD" forKey:@"compositingFilter"];
    CALayer *appleMask = [CALayer layer]; appleMask.frame = native.bounds; appleMask.backgroundColor = [UIColor whiteColor].CGColor;
    native.layer.mask = appleMask;   // (a mask of Apple's own, which must be what it has again after ours)
    [p addSubview:native]; dock.tDivider = native;
    DMFinderIconView *finder = [[DMFinderIconView alloc] initWithFrame:CGRectMake(740, 10, 70, 70)];
    finder.dot = TMakeDot(finder); [p addSubview:finder];
    [gTKeep addObjectsFromArray:@[w, dock, p, bg, shadow, native, appleMask, backdrop, icons, finder]];
    [gTWindows addObject:w];
    t.win = w; t.dock = dock; t.platter = p; t.bg = bg; t.native = native; t.shadow = shadow; t.appleMask = appleMask; t.backdrop = backdrop; t.icons = icons; t.finder = finder;
    return t;
}
static NSString *gTDomain, *gTBarDomain;
static void TSet(NSString *key, id value) { CFPreferencesSetValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, (__bridge CFStringRef)gTDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost); }
static void TSetBar(id value) { CFPreferencesSetValue(CFSTR("backgroundColor"), (__bridge CFPropertyListRef)value, (__bridge CFStringRef)gTBarDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost); }
static void TTurn(void) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.03]]; }
// One layout of a Dock, as Dock.x's hooks run: SBFloatingDockView's (the second divider, then the dividers' marks), then its platter's (Dock Style,
// then Dock Background) -- the order UIKit lays them out in; the site checks hold the hooks to it.
static void TLayout(TDock t) {
    gTPlatterLayouts++;
    DMSecondDividerAttach(t.dock);
    DMDockColorDividers(t.dock);
    DMDockStyleApply(t.platter);
    DMDockColorApply(t.platter);
}
// DMRelayoutDock: each Dock view laid out (its own hook: the second divider, the dividers' marks); its platter only if its bounds change, which a
// colour or a style never does -- so the Dock Style walk is what puts a new look and colour on the platter.
static void TRelayoutDocks(void) {
    for (SBFloatingDockWindow *w in gTWindows) for (UIView *d in w.subviews) if ([d isKindOfClass:[SBFloatingDockView class]]) { DMSecondDividerAttach(d); DMDockColorDividers(d); }
}
// Settings' prefsChanged, as Dock.x's DMPrefsChanged: the keys read (DMLoadPrefs), every Dock laid out (DMRelayoutDock), then the Dock Style walk.
static int gTStyle = MSBDDockStyleDefault;
static void TPrefsChanged(BOOL tweakOn) {
    DMDockStyleSetChoice(tweakOn ? gTStyle : MSBDDockStyleDefault);
    DMDockColorLoad(tweakOn);
    TRelayoutDocks();
    DMDockStyleRefreshAll();
}
void DMRunningIndicatorResyncAll(void) {   // (RunningIndicator.m's: every app icon's dot drawn again, each through DMDockStyleDot)
    gTResyncs++;
    for (SBFloatingDockWindow *w in gTWindows) {
        NSMutableArray<UIView *> *todo = [NSMutableArray arrayWithObject:w];
        while (todo.count) {
            UIView *v = todo.lastObject; [todo removeLastObject];
            if ([v isKindOfClass:[SBIconView class]]) { DMDockStyleDot(((SBIconView *)v).dot, v, 4); continue; }
            [todo addObjectsFromArray:v.subviews];
        }
    }
}
static UIView *TFind(UIView *root, Class c) {
    if ([root isKindOfClass:c]) return root;
    for (UIView *s in root.subviews) { UIView *f = TFind(s, c); if (f) return f; }
    return nil;
}
static UIView *TOurs(TDock t) { return TFind(t.win, objc_getClass("DMDockColorView")); }
static BOOL TColorIs(UIColor *c, double r, double g, double b, double a) {
    CGFloat cr = -1, cg = -1, cb = -1, ca = -1;
    if (![c getRed:&cr green:&cg blue:&cb alpha:&ca]) return NO;
    return fabs(cr - r) < 0.003 && fabs(cg - g) < 0.003 && fabs(cb - b) < 0.003 && fabs(ca - a) < 0.003;
}
static BOOL TGrey(UIColor *c, double w, double a) { return TColorIs(c, w, w, w, a); }
static BOOL TLabel(UIColor *c) { return [c isEqual:[UIColor labelColor]]; }
static UIView *TSecond(TDock t) { for (UIView *v in t.native.superview.subviews) if (v != t.native && v.frame.size.width == 1.0 && CGRectGetMinX(v.frame) == CGRectGetMinX(gDivider2Rect)) return v; return nil; }
static UIView *TLine(TDock t) {   // (ours over Apple's divider: right above it, at its place)
    NSUInteger i = [t.native.superview.subviews indexOfObject:t.native];
    UIView *next = i + 1 < t.native.superview.subviews.count ? t.native.superview.subviews[i + 1] : nil;
    return next && next != TSecond(t) && CGRectEqualToRect(next.frame, t.native.frame) ? next : nil;
}
static BOOL TDividersApple(TDock t) {   // (Apple's divider as Apple left it -- its own mask -- no line of ours; the second divider in its look)
    UIView *mine = TSecond(t);
    return t.native.layer.mask == t.appleMask && !TLine(t) && mine && [[mine.layer valueForKey:@"compositingFilter"] isEqual:@"plusD"] && [mine.backgroundColor isEqual:t.native.backgroundColor];
}
static BOOL TDividersOurs(TDock t, double w, double a) {
    UIView *mine = TSecond(t), *line = TLine(t);
    CALayer *m = t.native.layer.mask;
    return m && m != t.appleMask && !m.contents && !m.sublayers.count && !m.backgroundColor && line && TGrey(line.backgroundColor, w, a) && !line.userInteractionEnabled
        && mine && TGrey(mine.backgroundColor, w, a) && ![mine.layer valueForKey:@"compositingFilter"] && !mine.layer.filters.count;
}
static BOOL TDots(TDock t, BOOL (^ok)(UIColor *)) {
    for (SBIconView *iv in t.icons) if (!ok(iv.dot.backgroundColor)) return NO;
    return ok(t.finder.dot.backgroundColor);
}
static int TDotWrites(TDock t) { int n = t.finder.dot.writes; for (SBIconView *iv in t.icons) n += iv.dot.writes; return n; }
static void TMode(TDock t, UIUserInterfaceStyle s) { t.win.overrideUserInterfaceStyle = s; [t.win setNeedsLayout]; [t.win layoutIfNeeded]; TTurn(); }
static void TColor(NSString *hex, double a) { TSet(@kMSBDDockBackgroundKey, @"color"); TSet(@kMSBDDockBackgroundColorKey, hex); TSet(@kMSBDDockBackgroundOpacityKey, @(a)); }

static void SAutomatic(void) {
    TDock t = TMakeDock(NO);
    NSArray *subs = [t.bg.subviews copy], *layers = [t.bg.layer.sublayers copy];
    TPrefsChanged(YES);
    NSArray *psubs = [t.platter.subviews copy];   // (with the second divider: stock 1.8.7.5)
    for (int i = 0; i < 5; i++) TLayout(t);
    DMRunningIndicatorResyncAll(); [t.finder updateDot]; TTurn();
    int reads = gTDividerReads; DMDockColorDividers(t.dock);
    Check(gTBgReads == 0, @"Automatic (never set): Apple's material is never asked for, at any layout or the Dock Style walk (P7)");
    Check([t.bg.subviews isEqualToArray:subs] && [t.bg.layer.sublayers isEqualToArray:layers] && [t.platter.subviews isEqualToArray:psubs] && !TOurs(t), @"  ... nothing of ours is added anywhere");
    Check(TDividersApple(t) && t.bg.layer.mask == nil && t.bg.alpha == 1 && !t.bg.hidden, @"  ... Apple's material, its divider (its own mask) and the second divider's copy of it as they were: stock");
    Check(TDotWrites(t) == 0 && TDots(t, ^BOOL(UIColor *c) { return TLabel(c); }), @"  ... no dot is written: today's labelColor dots");
    Check(gTDividerReads == reads, @"  ... the dividers' call reads nothing (our colour was never on: not even Apple's divider is asked for)");
    TColor(@"#FFFFFF", 1.0); TPrefsChanged(NO); for (int i = 0; i < 3; i++) TLayout(t);
    Check(gTBgReads == 0 && !TOurs(t) && TDividersApple(t), @"Color stored with the Dock part off: Automatic, nothing asked or drawn");
    TSet(@kMSBDDockBackgroundKey, @NO); TPrefsChanged(YES); for (int i = 0; i < 3; i++) TLayout(t);
    Check(gTBgReads == 0 && !TOurs(t) && TDividersApple(t), @"false stored (the crash guard's step 1 sets a noted Color back so): Automatic, nothing asked or drawn");
}
static void SInside(void) {
    TDock t = TMakeDock(NO);
    TMode(t, UIUserInterfaceStyleDark);
    TColor(@"#FFFFFF", 1.0); TPrefsChanged(YES); TTurn();
    UIView *cv = TOurs(t);
    Check(cv && cv.superview == t.bg && t.bg.subviews.lastObject == cv && t.bg.layer.sublayers.lastObject == cv.layer && [t.bg.layer.sublayers containsObject:t.backdrop],
          @"B1: our colour is a view INSIDE Apple's material, over what it holds (its own layer stays under ours)");
    Check(CGRectEqualToRect(cv.frame, t.bg.bounds) && cv.autoresizingMask == (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight) && !cv.userInteractionEnabled,
          @"  ... filling it, with a flexible mask (a resize follows the material's own animation), taking no touch");
    Check(cv.layer.cornerRadius == 31 && [cv.layer.cornerCurve isEqualToString:kCACornerCurveContinuous] && cv.layer.maskedCorners == t.bg.layer.maskedCorners, @"  ... its corners copied from the material's (31 pt, continuous)");
    Check(TColorIs(cv.backgroundColor, 1, 1, 1, 1), @"  ... the colour at its opacity (white, 100 %: solid)");
    Check(t.bg.layer.mask == nil && t.bg.alpha == 1 && !t.bg.hidden && CGRectEqualToRect(t.bg.frame, t.platter.bounds) && t.shadow.layer.mask == nil, @"  ... nothing of Apple's material or shadow masked, moved or restyled");
    Check(TDividersOurs(t, 0, 0.25), @"marks (Dark Mode, white 100 %: ours dark): Apple's divider hidden by an empty mask of ours, a line of ours at its place, black 0.25; the second divider the same, no compositing filter (B3)");
    Check(TDots(t, ^BOOL(UIColor *c) { return TGrey(c, 0, 1); }) && gTFinderDots >= 1, @"  ... the running dots black, the apps' and Finder's, on the next turn of the run loop");
    t.bg.frame = CGRectMake(0, 0, 600, 80);
    Check(CGRectEqualToRect(cv.frame, t.bg.bounds), @"the material resized (an app added): ours with it at once, with no layout of ours");
    t.bg.alpha = 0.2; t.bg.hidden = YES; t.bg.transform = CGAffineTransformMakeScale(0.5, 0.5); TLayout(t);
    Check(cv.superview == t.bg && cv.alpha == 1 && !cv.hidden && CGAffineTransformIsIdentity(cv.transform), @"  ... its fade, hidden state and transform: never copied, ours is inside it and goes with it");
    t.bg.alpha = 1; t.bg.hidden = NO; t.bg.transform = CGAffineTransformIdentity;
    MTMaterialView *fresh = [[MTMaterialView alloc] initWithFrame:t.platter.bounds]; fresh.layer.cornerRadius = 24;
    [t.bg removeFromSuperview]; [t.platter insertSubview:fresh atIndex:1]; t.platter.tBackground = fresh; [gTKeep addObject:fresh];
    TLayout(t);
    Check(cv.superview == fresh && cv.layer.cornerRadius == 24 && CGRectEqualToRect(cv.frame, fresh.bounds), @"iPadOS replaces its material: ours goes into the new one at the next layout, its corners");
}
static void SLight(void) {
    TDock t = TMakeDock(NO);
    TMode(t, UIUserInterfaceStyleLight);
    TColor(@"#242225", 0.7); TPrefsChanged(YES); TTurn();
    Check(TDividersOurs(t, 1, 0.30) && TDots(t, ^BOOL(UIColor *c) { return TGrey(c, 1, 1); }), @"Light Mode, #242225 70 % (the menu bar's default): ours light -- white dots, divider lines white 0.30");
    int w = TDotWrites(t);
    TMode(t, UIUserInterfaceStyleDark);
    Check(TDividersApple(t), @"  ... to Dark Mode (our view's trait change): iPadOS's own answer -- Apple's divider has its own mask again, our line gone, the second divider Apple's look");
    Check(TDots(t, ^BOOL(UIColor *c) { return TLabel(c); }) && TDotWrites(t) == w + 4, @"  ... the dots labelColor again, each written once");
    TMode(t, UIUserInterfaceStyleLight);
    Check(TDividersOurs(t, 1, 0.30) && TDots(t, ^BOOL(UIColor *c) { return TGrey(c, 1, 1); }), @"  ... and back to Light Mode: ours again");
}
static void SOwn(void) {
    TDock t = TMakeDock(NO);
    TMode(t, UIUserInterfaceStyleLight);
    TColor(@"#FFFFFF", 1.0); TPrefsChanged(YES); TTurn();
    Check(TOurs(t).superview == t.bg && TDividersApple(t) && TDotWrites(t) == 0 && TDots(t, ^BOOL(UIColor *c) { return TLabel(c); }),
          @"Light Mode, white 100 %: our colour is drawn, the answer is iPadOS's own (dark): Apple's divider, the second divider and the dots untouched");
}
static void SFrosted(void) {
    TDock t = TMakeDock(NO);
    TMode(t, UIUserInterfaceStyleLight);
    gTStyle = MSBDDockStyleFrosted; TColor(@"#000000", 0.3); TPrefsChanged(YES); TTurn();
    UIView *sv = TFind(t.platter, objc_getClass("DMDockStyleView")), *cv = TOurs(t), *draw = TFind(sv, objc_getClass("DMDockStyleDraw")), *blur = TFind(sv, [UIVisualEffectView class]);
    NSUInteger ic = [sv.subviews indexOfObject:cv], id_ = [sv.subviews indexOfObject:draw], ib = [sv.subviews indexOfObject:blur];
    Check(sv && cv && cv.superview == sv && blur && ib < ic && ic < id_, @"Frosted + Color (P5): our colour takes the place of Frosted's tint -- over its blur, under its border");
    Check([[draw valueForKey:@"noTint"] boolValue] && CGRectEqualToRect(cv.frame, sv.bounds) && cv.layer.cornerRadius == MSBD_FROSTED_CORNER, @"  ... Frosted draws its border only then; ours at its size and 6 pt corners");
    Check(t.bg.layer.mask != nil && ![t.bg.subviews containsObject:cv], @"  ... Apple's material hidden by Dock Style as before, ours not in it");
    Check(TDividersApple(t) && TDotWrites(t) == 0, @"  ... black 30 % in Light Mode over Frosted's lighter blur (142 to 245): iPadOS's own marks (on iPadOS's material it would be ours, white)");
    TSet(@kMSBDDockBackgroundColorKey, @"#FF3B30"); TSet(@kMSBDDockBackgroundOpacityKey, @0.9); DMDockColorChanged(); TTurn();
    Check(TColorIs(cv.backgroundColor, 1, 0x3b / 255.0, 0x30 / 255.0, 0.9) && cv.superview == sv, @"  ... a new colour from the colour well: on Frosted at once (its view's colour, no redraw)");
    TMode(t, UIUserInterfaceStyleDark);
    Check(TDividersOurs(t, 0, 0.25), @"  ... #FF3B30 90 % in Dark Mode over Frosted: ours, dark");
    gTStyle = MSBDDockStyleDefault; TPrefsChanged(YES); TTurn();
    Check(cv.superview == t.bg && !TFind(t.platter, objc_getClass("DMDockStyleView")), @"Frosted to Default: our colour goes inside iPadOS's material");
    gTStyle = MSBDDockStyleFrosted; TPrefsChanged(YES); TTurn();
    sv = TFind(t.platter, objc_getClass("DMDockStyleView")); draw = TFind(sv, objc_getClass("DMDockStyleDraw"));
    TSet(@kMSBDDockBackgroundKey, @"auto"); TPrefsChanged(YES); TTurn();
    Check(![[draw valueForKey:@"noTint"] boolValue] && !TOurs(t) && TDividersApple(t), @"Frosted, then Automatic: Frosted's own tint again, ours gone, Apple's marks");
}
static void SGlass(void) {
    TDock t = TMakeDock(NO);
    TMode(t, UIUserInterfaceStyleDark);
    gTStyle = MSBDDockStyleGlass; TColor(@"#FFFFFF", 1.0); TPrefsChanged(YES); TTurn();
    Check(!TOurs(t) && TDividersApple(t), @"Glass Shelf + Color: nothing of ours (the shelf keeps its glass); its dividers iPadOS's (P8: marks follow what is drawn, not the setting)");
    BOOL lights = YES; for (SBIconView *iv in t.icons) if (!iv.dot.layer.contents) lights = NO;
    Check(lights, @"  ... the dots are the shelf's lights, as without a colour");
    gTStyle = MSBDDockStyleDefault; TPrefsChanged(YES); TTurn();
    BOOL back = YES; for (SBIconView *iv in t.icons) if (iv.dot.layer.contents || !TGrey(iv.dot.backgroundColor, 0, 1)) back = NO;
    Check(TOurs(t).superview == t.bg && TDividersOurs(t, 0, 0.25) && back, @"  ... to Default: ours inside the material, the lights gone and the dots black (white 100 % in Dark Mode)");
}
static void SDrag(void) {
    TDock t = TMakeDock(NO), tv = TMakeDock(YES);
    TMode(t, UIUserInterfaceStyleDark); TMode(tv, UIUserInterfaceStyleDark);
    TSet(@kMSBDDockBackgroundKey, @"auto"); TPrefsChanged(YES); TTurn();
    int walks = gTWalks, layouts = gTPlatterLayouts;
    TColor(@"#FFFFFF", 1.0); DMDockColorChanged(); TTurn();   // (the colour well picked while Automatic: Settings stores Color with it, the light note)
    Check(TOurs(t) && TOurs(tv) && gTWalks == walks + 1 && gTPlatterLayouts == layouts, @"B4: Color switched on by the light note: every Dock's platter once (one walk of the windows), no layout");
    walks = gTWalks; int resyncs = gTResyncs, reads = gTDividerReads;
    TSet(@kMSBDDockBackgroundColorKey, @"#FF3B30"); DMDockColorChanged();
    Check(TColorIs(TOurs(t).backgroundColor, 1, 0x3b / 255.0, 0x30 / 255.0, 1) && TColorIs(TOurs(tv).backgroundColor, 1, 0x3b / 255.0, 0x30 / 255.0, 1),
          @"  ... a new colour: on both Docks at once (the iPad's and the TV's)");
    TTurn();
    Check(gTWalks == walks && gTPlatterLayouts == layouts && gTResyncs == resyncs && gTDividerReads == reads, @"  ... no walk, no layout, and the answer unchanged (ours, dark): no dot or divider touched");
    for (int i = 0; i < 10; i++) { TSet(@kMSBDDockBackgroundOpacityKey, @(1.0 - i * 0.02)); DMDockColorChanged(); }
    TTurn();
    Check(gTWalks == walks && gTResyncs == resyncs && TColorIs(TOurs(t).backgroundColor, 1, 0x3b / 255.0, 0x30 / 255.0, 0.82), @"  ... a drag of the slider (10 notes): the colour follows each, nothing else");
    TSet(@kMSBDDockBackgroundOpacityKey, @0.2); DMDockColorChanged();
    Check(TDividersApple(t) && TDividersApple(tv), @"  ... to 20 % (#FF3B30, Dark: iPadOS's own answer): the dividers Apple's at once");
    TTurn();
    Check(gTResyncs == resyncs + 1 && TDots(t, ^BOOL(UIColor *c) { return TLabel(c); }) && TDots(tv, ^BOOL(UIColor *c) { return TLabel(c); }), @"  ... the dots once, on the next turn, for both Docks");
    Check(gTPlatterLayouts == layouts && gTWalks == walks, @"  ... still no layout of the Dock and no walk (no DMLoadPrefs, no DMRelayoutDock: the site checks)");
}
static void SFirstTime(void) {
    TDock t = TMakeDock(NO);
    TSetBar(@"#FF0000"); TSet(@kMSBDDockBackgroundKey, @"color"); TPrefsChanged(YES); TTurn();
    Check(TColorIs(TOurs(t).backgroundColor, 1, 0, 0, 0.7), @"never stored: the Dock's colour is Status Bar Background's (#FF0000), at 0.7 (decision 3)");
    TSet(@kMSBDDockBackgroundColorKey, @"#FF0000");   // (Settings stores it the first time Color is chosen: the C3 rows)
    TSetBar(@"#00FF00"); TPrefsChanged(YES); DMDockColorChanged();
    Check(TColorIs(TOurs(t).backgroundColor, 1, 0, 0, 0.7), @"  ... once stored, a new menu bar colour does not change the Dock's (no live link)");
    TSet(@kMSBDDockBackgroundColorKey, nil); TSetBar(nil); TPrefsChanged(YES);
    Check(TColorIs(TOurs(t).backgroundColor, 0x24 / 255.0, 0x22 / 255.0, 0x25 / 255.0, 0.7), @"  ... neither stored: #242225, as the menu bar's own");
}
static void STV(void) {
    TDock t = TMakeDock(NO), tv = TMakeDock(YES);
    TMode(t, UIUserInterfaceStyleDark); TMode(tv, UIUserInterfaceStyleDark);
    TColor(@"#34C759", 0.5); TPrefsChanged(YES); TTurn();
    Check(TOurs(tv).superview == tv.bg && TColorIs(TOurs(tv).backgroundColor, 0x34 / 255.0, 0xc7 / 255.0, 0x59 / 255.0, 0.5) && TColorIs(TOurs(t).backgroundColor, 0x34 / 255.0, 0xc7 / 255.0, 0x59 / 255.0, 0.5),
          @"the TV's Dock (decision 4): the iPad's colour, in its own material, from the same keys");
    Check(TDividersOurs(tv, 0, 0.25) && TDots(tv, ^BOOL(UIColor *c) { return TGrey(c, 0, 1); }), @"  ... its marks worked out for its own platter (ours, dark)");
}
static void SBack(void) {
    TDock t = TMakeDock(NO);
    TMode(t, UIUserInterfaceStyleDark);
    NSArray *subs = [t.bg.subviews copy], *layers = [t.bg.layer.sublayers copy], *psubs = nil;
    TPrefsChanged(YES); TTurn(); psubs = [t.platter.subviews copy];   // (stock, with the second divider)
    UIView *mineBefore = TSecond(t); UIColor *nativeColor = t.native.backgroundColor;
    TColor(@"#FFFFFF", 1.0); TPrefsChanged(YES); TTurn();
    Check(TOurs(t) && TDividersOurs(t, 0, 0.25), @"Color on (Dark, white 100 %: ours)");
    TSet(@kMSBDDockBackgroundKey, @"auto"); TPrefsChanged(YES); TTurn();
    Check(!TOurs(t) && [t.bg.subviews isEqualToArray:subs] && [t.bg.layer.sublayers isEqualToArray:layers] && [t.platter.subviews isEqualToArray:psubs], @"back to Automatic: our view gone, the material's views and layers as before");
    Check(TDividersApple(t) && TSecond(t) == mineBefore && [t.native.backgroundColor isEqual:nativeColor] && [[t.native.layer valueForKey:@"compositingFilter"] isEqual:@"plusD"],
          @"  ... Apple's divider never restyled and its own mask back; the second divider Apple's look again (B3)");
    Check(TDots(t, ^BOOL(UIColor *c) { return TLabel(c); }), @"  ... the dots labelColor");
    int reads = gTBgReads, dreads = gTDividerReads, w = TDotWrites(t);
    DMDockColorApply(t.platter); DMDockColorDividers(t.dock); DMRunningIndicatorResyncAll(); TTurn();
    Check(gTBgReads == reads && gTDividerReads == dreads && TDotWrites(t) == w, @"  ... and from then on nothing is read or written: the platter's record went with it");
}
static void SDotOnce(void) {
    TDock t = TMakeDock(NO);
    TMode(t, UIUserInterfaceStyleDark);
    TColor(@"#FFFFFF", 1.0); TPrefsChanged(YES); TTurn();
    int w = TDotWrites(t);
    for (int i = 0; i < 10; i++) { DMRunningIndicatorResyncAll(); [t.finder updateDot]; }
    Check(w == 4 && TDotWrites(t) == w, @"P7: each dot coloured once (4 dots), not at every pass of the 0.75 s poll (10 passes: no write)");
    TSet(@kMSBDDockBackgroundKey, @"auto"); TPrefsChanged(YES); TTurn();
    int w2 = TDotWrites(t);
    for (int i = 0; i < 10; i++) DMRunningIndicatorResyncAll();
    Check(w2 == w + 4 && TDotWrites(t) == w2, @"  ... labelColor put back once (P7), then nothing written");
}
// The second divider has one writer (Dock.x DMSecondDividerLookOf): Apple's look copied, or ours while our marks are on that Dock, never one written
// over the other at each layout; ours is our line's, the same strength (review of DOCKCOLOR: an iPadOS whose divider carries part of its look in its
// alpha left the second line weaker than ours; and a Dock laid out inside an animation, as when an app is added, faded the second divider from
// Apple's look to ours each time, since Apple's look was copied first).
static NSCountedSet *gTWrites;   // (look writes on views and layers, while counted)
static IMP gTSetBG, gTSetAlpha, gTSetFilters;
static void TSetBG(UIView *v, SEL c, UIColor *x) { [gTWrites addObject:v]; ((void (*)(id, SEL, id))gTSetBG)(v, c, x); }
static void TSetAlpha(UIView *v, SEL c, CGFloat x) { [gTWrites addObject:v]; ((void (*)(id, SEL, CGFloat))gTSetAlpha)(v, c, x); }
static void TSetFilters(CALayer *l, SEL c, NSArray *x) { [gTWrites addObject:l]; ((void (*)(id, SEL, id))gTSetFilters)(l, c, x); }
static void SSecondLook(void) {
    gTWrites = [NSCountedSet set];
    gTSetBG = method_setImplementation(class_getInstanceMethod([UIView class], @selector(setBackgroundColor:)), (IMP)TSetBG);
    gTSetAlpha = method_setImplementation(class_getInstanceMethod([UIView class], @selector(setAlpha:)), (IMP)TSetAlpha);
    gTSetFilters = method_setImplementation(class_getInstanceMethod([CALayer class], @selector(setFilters:)), (IMP)TSetFilters);
    TDock t = TMakeDock(NO);
    TMode(t, UIUserInterfaceStyleDark);
    t.native.alpha = 0.5;   // (part of Apple's look in its divider's alpha)
    TPrefsChanged(YES); TTurn();
    UIView *mine = TSecond(t);
    Check(mine && fabs(mine.alpha - 0.5) < 0.001 && TDividersApple(t), @"Automatic: the second divider copies Apple's divider, its alpha too (0.5 here), as before");
    TColor(@"#FFFFFF", 1.0); TPrefsChanged(YES); TTurn();
    UIView *line = TLine(t);
    Check(TDividersOurs(t, 0, 0.25) && line.alpha == 1 && mine.alpha == 1, @"our marks (Dark, white 100 %): our line and the second divider the same strength, black 0.25 at alpha 1 both, whatever Apple's divider's alpha");
    [gTWrites removeAllObjects];
    for (int i = 0; i < 3; i++) TLayout(t);
    Check(![gTWrites countForObject:mine] && ![gTWrites countForObject:mine.layer] && ![gTWrites countForObject:line], @"  ... 3 more layouts: nothing written on the second divider or our line (one writer, values written only when they differ)");
    [UIView animateWithDuration:0.5 animations:^{ TLayout(t); }];
    Check(![mine.layer animationForKey:@"backgroundColor"] && ![mine.layer animationForKey:@"opacity"] && !line.layer.animationKeys.count && TDividersOurs(t, 0, 0.25),
          @"  ... a layout inside an animation (an app added to the Dock): nothing of the dividers' look animates, ours stays as it is");
    [mine.layer removeAllAnimations]; [line.layer removeAllAnimations];
    gDivider2Alone = YES; t.native.alpha = 0; TLayout(t);
    Check(line.alpha == 0 && mine.alpha == 1 && TGrey(mine.backgroundColor, 0, 0.25), @"  ... no recents (Apple's line hidden by its alpha, the second divider the only one): our line hidden with Apple's, the second divider shown in our marks");
    gDivider2Alone = NO; t.native.alpha = 0.5; TLayout(t);
    TSet(@kMSBDDockBackgroundKey, @"auto"); TPrefsChanged(YES); TTurn();
    Check(TDividersApple(t) && fabs(mine.alpha - 0.5) < 0.001, @"back to Automatic: the second divider Apple's look again, its alpha 0.5 too");
    TColor(@"#FFFFFF", 1.0); TPrefsChanged(YES); TTurn();
    [gTWrites removeAllObjects];
    t.native.backgroundColor = [UIColor colorWithWhite:0.7 alpha:1];   // (Apple's restyle, then what Dock.x's hook runs after it: the site checks hold it)
    DMDockSecondDividerLook(t.dock); DMDockColorDividers(t.dock);
    Check(TDividersOurs(t, 0, 0.25) && mine.alpha == 1 && ![gTWrites countForObject:mine], @"  ... Color again, then Apple's restyle: the second divider keeps ours, nothing written over it");
    method_setImplementation(class_getInstanceMethod([UIView class], @selector(setBackgroundColor:)), gTSetBG);
    method_setImplementation(class_getInstanceMethod([UIView class], @selector(setAlpha:)), gTSetAlpha);
    method_setImplementation(class_getInstanceMethod([CALayer class], @selector(setFilters:)), gTSetFilters);
}
#if DEBUG
static void SDebugWord(void) {
    TDock t = TMakeDock(NO);
    TColor(@"#FF3B30", 0.5); TPrefsChanged(YES); TTurn();
    [gTLog removeAllObjects];
    DMDockColorDebug("dockcolor");
    NSString *all = [gTLog componentsJoinedByString:@"\n"];
    Check([all containsString:@"material MTMaterialView in SBFloatingDockPlatterView"] && [all containsString:@"(OURS)"] && [all containsString:@"Apple's divider UIView"]
          && [all containsString:@"its filters: none, sublayers:"] && [all containsString:@"second divider yes: colour"] && [all containsString:@", alpha 1.00, filter"],
          @"debug \"dockcolor\": per platter, the material's class and place, its own filters, its layers with ours among them, the dividers (the second one's alpha)");
    t.bg.alpha = 0.6;
    DMDockColorDebug("dockcolorsibling");
    UIView *cv = TOurs(t);
    Check(cv.superview == t.platter && [t.platter.subviews indexOfObject:cv] == [t.platter.subviews indexOfObject:t.bg] + 1 && CGRectEqualToRect(cv.frame, t.bg.frame) && fabs(cv.alpha - 0.6) < 0.001,
          @"  ... \"dockcolorsibling\": the fallback, a sibling right above the material copying its frame, corners and alpha (for the first iPad to compare)");
    DMDockColorDebug("dockcolorinside");
    Check(cv.superview == t.bg && cv.alpha == 1, @"  ... \"dockcolorinside\": back inside the material (B1)");
}
#endif
static BOOL TScenario(const char *name) {
    NSDictionary<NSString *, void (^)(void)> *all = @{ @"automatic": ^{ SAutomatic(); }, @"inside": ^{ SInside(); }, @"light": ^{ SLight(); }, @"own": ^{ SOwn(); },
        @"frosted": ^{ SFrosted(); }, @"glass": ^{ SGlass(); }, @"drag": ^{ SDrag(); }, @"firsttime": ^{ SFirstTime(); }, @"tv": ^{ STV(); }, @"back": ^{ SBack(); },
        @"dotonce": ^{ SDotOnce(); }, @"secondlook": ^{ SSecondLook(); },
#if DEBUG
        @"debugword": ^{ SDebugWord(); },
#endif
    };
    if (!strcmp(name, "list")) { for (NSString *k in [all.allKeys sortedArrayUsingSelector:@selector(compare:)]) printf("%s\n", k.UTF8String); exit(0); }
    void (^s)(void) = all[@(name)];
    if (!s) return NO;
    gTLog = [NSMutableArray array]; gTKeep = [NSMutableArray array]; gTWindows = [NSMutableArray array];
    gTDomain = @TDC_DOMAIN; gTBarDomain = @TDC_BAR_DOMAIN;
    SEL allSel = @selector(allWindowsIncludingInternalWindows:onlyVisibleWindows:);
    Method m = class_getClassMethod([UIWindow class], allSel);
    if (m) method_setImplementation(m, (IMP)TAllWindows); else class_addMethod(object_getClass([UIWindow class]), allSel, (IMP)TAllWindows, "@@:cc");
    // (Frosted's blur, a UIVisualEffectView, asks Mac Catalyst's app delegate when it goes into a window, which a test without an app has not: it
    //  moves as a plain view here -- what is tested is where things are, not how the blur draws)
    for (NSString *sel in @[@"willMoveToWindow:", @"didMoveToWindow"]) {
        Method plain = class_getInstanceMethod([UIView class], NSSelectorFromString(sel));
        if (plain) class_replaceMethod([UIVisualEffectView class], NSSelectorFromString(sel), method_getImplementation(plain), method_getTypeEncoding(plain));
    }
    for (NSString *k in @[@kMSBDDockBackgroundKey, @kMSBDDockBackgroundColorKey, @kMSBDDockBackgroundOpacityKey]) TSet(k, nil);
    TSetBar(nil);
    gDivider2Rect = CGRectMake(660, 18, 1, 60); gDivider2Alone = NO;
    printf("== %s\n", name);
    s();
    for (NSString *k in @[@kMSBDDockBackgroundKey, @kMSBDDockBackgroundColorKey, @kMSBDDockBackgroundOpacityKey]) TSet(k, nil);
    TSetBar(nil);
    CFPreferencesSynchronize((__bridge CFStringRef)gTDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize((__bridge CFStringRef)gTBarDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    return YES;
}
#endif

int main(int argc, char **argv) {
    @autoreleasepool {
        const char *what = argc > 1 ? argv[1] : "rule";
        if (!strcmp(what, "rule")) Rule();
#if TDC_DOCK
        else if (TScenario(what)) {}
#endif
        else { printf("FAIL  no scenario %s\n", what); return 1; }
        printf("%s: %d checks, %d failed\n", what, gChecks, gFails);
    }
    return gFails ? 1 : 0;
}
