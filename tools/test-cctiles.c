// test-cctiles.c -- Mac test of common/CCTileLogic.h (1.8.0 P3, our own Control Center's Mac tiles): the sliders' knob, touch, drag and
// VoiceOver steps, the per cent and the speaker's waves, Connectivity's rows (Airplane Mode, Wi-Fi, Bluetooth: their order, lines, colours,
// places and the names' one size), the wide tiles' and Now Playing's parts, Now Playing's two lines, a tile at Control Center Size. Sizes as
// Apple's grid gives them on the 17.5 (unit 69 pt, spacing 15 pt: the block 153 x 153, a wide tile 321 x 69) and the M1 (the block 142 x 142),
// and Menu Bar Size's three scales. Run by test-cctiles.sh.
#include <stdio.h>
#include <string.h>
#include "../common/CCTileLogic.h"
#include "../common/CCLayout.h"
static int fails = 0, checks = 0;
static int near(double a, double b) { return fabs(a - b) < 0.001; }
#define CHECK(cond, what) do { checks++; if (cond) printf("PASS  %s\n", what); else { fails++; printf("FAIL  %s\n", what); } } while (0)
static int inside(CGRect in, CGRect out) {   // (in lies within out)
    return in.origin.x >= out.origin.x - 0.001 && in.origin.y >= out.origin.y - 0.001 && CGRectGetMaxX(in) <= CGRectGetMaxX(out) + 0.001 && CGRectGetMaxY(in) <= CGRectGetMaxY(out) + 0.001
        && in.size.width >= 0 && in.size.height >= 0;
}
int main(void) {
    // ---- the sliders ----
    double x0 = 0, x1 = 297, d = 24;   // (a wide tile's slider on the 17.5: 321 less 12 pt each side, 24 pt tall)
    CHECK(near(MSBDCCTSliderKnobX(0, x0, x1, d), 12) && near(MSBDCCTSliderKnobX(1, x0, x1, d), 285), "the knob: inside the track at 0 and at 1 (its centre half a knob in)");
    CHECK(near(MSBDCCTSliderKnobX(0.5, x0, x1, d), 148.5), "  ... in the middle at a half");
    CHECK(near(MSBDCCTSliderKnobX(-3, x0, x1, d), 12) && near(MSBDCCTSliderKnobX(7, x0, x1, d), 285) && near(MSBDCCTSliderKnobX(NAN, x0, x1, d), 12), "  ... a value out of range (or not a number) clamped");
    CHECK(near(MSBDCCTSliderKnobX(0.3, 0, 10, 24), 5), "  ... a track shorter than its knob: the knob in its middle");
    int round = 1;
    for (double v = 0; v <= 1.0001; v += 0.125) round &= near(MSBDCCTSliderValueAt(MSBDCCTSliderKnobX(v, x0, x1, d), x0, x1, d), v);
    CHECK(round, "a touch on the knob's centre reads back its value (0 ... 1)");
    CHECK(near(MSBDCCTSliderValueAt(2, x0, x1, d), 0) && near(MSBDCCTSliderValueAt(296, x0, x1, d), 1), "  ... a touch past either end: 0 or 1");
    CHECK(near(MSBDCCTSliderValueAt(5, 0, 10, 24), 0) && near(MSBDCCTSliderValueAt(NAN, x0, x1, d), 0), "  ... a track shorter than its knob, or no touch: 0");
    CHECK(near(MSBDCCTSliderDragged(0.5, 273.0 / 4, x0, x1, d), 0.75), "a drag of a quarter of the knob's travel adds a quarter (the knob does not jump to the finger)");
    CHECK(near(MSBDCCTSliderDragged(0.5, -1000, x0, x1, d), 0) && near(MSBDCCTSliderDragged(0.5, 1000, x0, x1, d), 1), "  ... clamped at both ends");
    CHECK(near(MSBDCCTSliderDragged(0.4, 50, 0, 20, 24), 0.4) && near(MSBDCCTSliderDragged(0.4, NAN, x0, x1, d), 0.4), "  ... no travel, or no distance: unchanged");
    CHECK(near(MSBDCCTSliderStep(0.5, 1, 16), 9.0 / 16) && near(MSBDCCTSliderStep(0.5, 0, 16), 7.0 / 16), "VoiceOver's step: one sixteenth up or down from a notch");
    CHECK(near(MSBDCCTSliderStep(0.53, 1, 16), 9.0 / 16) && near(MSBDCCTSliderStep(0.53, 0, 16), 8.0 / 16), "  ... between two notches: to the next one that way");
    CHECK(near(MSBDCCTSliderStep(1, 1, 16), 1) && near(MSBDCCTSliderStep(0, 0, 16), 0), "  ... never past the ends");
    CHECK(near(MSBDCCTSliderStep(0.5, 1, 0), 9.0 / 16), "  ... no step count: sixteen (the volume buttons')");
    CHECK(MSBDCCTPercent(0.654) == 65 && MSBDCCTPercent(0.655) == 66 && MSBDCCTPercent(1) == 100 && MSBDCCTPercent(-1) == 0 && MSBDCCTPercent(NAN) == 0, "the per cent: rounded, 0 ... 100");
    CHECK(MSBDCCTVolumeWaves(0) == 0 && MSBDCCTVolumeWaves(0.00005) == 0 && MSBDCCTVolumeWaves(0.2) == 1 && MSBDCCTVolumeWaves(0.5) == 2 && MSBDCCTVolumeWaves(0.9) == 3 && MSBDCCTVolumeWaves(1) == 3,
          "the speaker: muted at 0, then one, two, three waves");
    // ---- Connectivity ----
    CHECK(kMSBDCCTRowAirplane == 0 && kMSBDCCTRowWiFi == 1 && kMSBDCCTRowBluetooth == 2 && kMSBDCCTRows == 3, "Connectivity's rows: Airplane Mode at the top, then Wi-Fi and Bluetooth (KT 3 Nov: no AirDrop row)");
    CHECK(!MSBDCCTRowHasPage(kMSBDCCTRowAirplane) && MSBDCCTRowHasPage(kMSBDCCTRowWiFi) && MSBDCCTRowHasPage(kMSBDCCTRowBluetooth), "  ... Wi-Fi and Bluetooth open a page, Airplane Mode none (nor in Apple's module)");
    CHECK(MSBDCCTRowTint(kMSBDCCTRowAirplane) == kMSBDCCTTintOrange && MSBDCCTRowTint(kMSBDCCTRowWiFi) == kMSBDCCTTintBlue && MSBDCCTRowTint(kMSBDCCTRowBluetooth) == kMSBDCCTTintBlue,
          "  ... Airplane Mode's button Apple's orange when on, the others macOS's blue");
    CHECK(MSBDCCTAirplaneLine(1, 1) == 1 && MSBDCCTAirplaneLine(1, 0) == 0, "Airplane Mode's line: On, Off");
    CHECK(MSBDCCTAirplaneLine(0, 1) == 3 && MSBDCCTAirplaneLine(0, 0) == 3, "  ... Unavailable while its setting is not read (not yet, or not readable here)");
    CHECK(MSBDCCTWiFiLine(0, 0, 0) == 0 && MSBDCCTWiFiLine(0, 1, 1) == 0, "Wi-Fi's line: Off when off (whatever it last knew)");
    CHECK(MSBDCCTWiFiLine(1, 0, 0) == 1 && MSBDCCTWiFiLine(1, 1, 0) == 1, "  ... Not Connected when on without a network (or without its name)");
    CHECK(MSBDCCTWiFiLine(1, 1, 1) == 2, "  ... the network's name when joined");
    CHECK(MSBDCCTBluetoothLine(0, 1) == 3 && MSBDCCTBluetoothLine(1, 1) == 1 && MSBDCCTBluetoothLine(1, 0) == 0, "Bluetooth's line: Unavailable (its daemon not attached), On, Off");
    const double ks[3] = { 1.0, 1.125, 1.25 };
    const struct { double w, h; const char *where; } blocks[3] = { { 153, 153, "the 17.5's block (153 x 153)" }, { 142, 142, "the M1's (142 x 142)" }, { 186, 186, "a larger iPad's (186 x 186)" } };
    // the names' widths at their own size (13 pt x k, semibold: the Mac's system font, the face iPadOS draws them in)
    const double nat13[kMSBDCCTRows] = { 91.2, 33.5, 61.4 }, nat15[kMSBDCCTRows] = { 103.3, 37.9, 69.6 }, nat16[kMSBDCCTRows] = { 109.4, 40.1, 73.7 };
    for (int b = 0; b < 3; b++) for (int s = 0; s < 3; s++) {
        MSBDCCTConnRow r[kMSBDCCTRows];
        MSBDCCTConnLayout(blocks[b].w, blocks[b].h, ks[s], 1.0, r);
        CGRect tile = CGRectMake(0, 0, blocks[b].w, blocks[b].h);
        int ok = 1;
        for (int i = 0; i < kMSBDCCTRows; i++) {
            CGRect row = r[i].row;
            ok &= inside(row, tile) && inside(r[i].circle, row) && inside(r[i].title, row) && inside(r[i].line, row) && inside(r[i].chevron, row);
            ok &= r[i].title.size.width > 40 && CGRectGetMaxX(r[i].circle) < r[i].title.origin.x;
            ok &= MSBDCCTRowHasPage(i) ? CGRectGetMaxX(r[i].title) < r[i].chevron.origin.x && r[i].chevron.size.width > 0 : r[i].chevron.size.width == 0 && near(CGRectGetMaxX(r[i].title), blocks[b].w - 8);
            ok &= near(r[i].circle.size.width, r[i].circle.size.height) && r[i].circle.size.width >= 26;
            ok &= CGRectGetMaxY(r[i].title) <= r[i].line.origin.y + 0.001;
            if (i) ok &= near(row.origin.y, CGRectGetMaxY(r[i - 1].row)) && near(r[i].title.origin.x, r[0].title.origin.x);   // (the three rows follow on, equal; one column of names)
        }
        char what[200]; snprintf(what, sizeof what, "Connectivity's rows in %s at scale %.3f: each row's button, words (and chevron) in it, side by side, one column of names; Airplane Mode's name to the trailing margin", blocks[b].where, ks[s]);
        CHECK(ok, what);
        const double *nat = s == 0 ? nat13 : s == 1 ? nat15 : nat16;
        double f = MSBDCCTTextFit(nat, r);
        int fits = 1;
        for (int i = 0; i < kMSBDCCTRows; i++) fits &= nat[i] * f <= r[i].title.size.width + 0.001 || f == kMSBDCCTTextMinFit;
        snprintf(what, sizeof what, "  ... the three names at one size (%.2f of theirs) at which each fits its room, or the floor", f);
        CHECK(fits && f <= 1.0 && f >= kMSBDCCTTextMinFit, what);
    }
    { MSBDCCTConnRow r[kMSBDCCTRows]; MSBDCCTConnLayout(153, 153, 1.0, 1.0, r);
      CHECK(near(r[0].circle.size.width, 28) && near(r[0].circle.origin.x, 12) && near(r[0].row.origin.y, 10) && near(CGRectGetMaxY(r[2].row), 143), "  ... the 17.5 at Small: 28 pt buttons, 12 pt in, the rows between 10 pt margins");
      CHECK(near(MSBDCCTTextFit(nat13, r), 1.0), "  ... there every name at its own 13 pt (\"Airplane Mode\" 91 pt in 93)"); }
    { MSBDCCTConnRow r[kMSBDCCTRows]; MSBDCCTConnLayout(142, 142, 1.125, 1.0, r);
      CHECK(near(CGRectGetMaxX(r[kMSBDCCTRowBluetooth].chevron), 134) && r[kMSBDCCTRowBluetooth].title.size.width >= 68, "  ... the M1's block at Medium: the chevron 8 pt in, 68 pt for \"Bluetooth\" (it fits at the label's smallest scale)");
      CHECK(near(r[kMSBDCCTRowAirplane].title.size.width, 81), "  ... Airplane Mode's name has the chevron's room too: 81 pt");
      CHECK(near(MSBDCCTTextFit(nat15, r), 0.78), "  ... the names at 0.78 of Medium's 15 pt there (\"Airplane Mode\" wants 103 pt), all three alike");
      MSBDCCTConnRow g[kMSBDCCTRows]; MSBDCCTConnLayout(142, 142, 1.125, 0.78, g);
      int kept = 1;
      for (int i = 0; i < kMSBDCCTRows; i++) kept &= near(g[i].title.size.width, r[i].title.size.width) && g[i].title.size.height < r[i].title.size.height && near(CGRectGetMaxY(g[i].title), g[i].line.origin.y)
          && near((g[i].title.origin.y + CGRectGetMaxY(g[i].line)) / 2.0, CGRectGetMidY(g[i].row)) && inside(g[i].line, g[i].row);
      CHECK(kept, "  ... laid out at that size: the same rooms, the two lines lower and kept together in the middle of each row");
      CHECK(near(MSBDCCTLineFit(0.78), 0.78 * 13.0 / 11.0) && 12.0 * MSBDCCTLineFit(0.78) < 15.0 * 0.78 && 12.0 * MSBDCCTLineFit(0.78) > 12.0 * 0.78,
            "  ... the second lines there no larger than the names (10.9 of 11.7 pt), but no smaller than they need (not 9.4)");
      CHECK(near(MSBDCCTLineFit(1.0), 1.0) && near(MSBDCCTLineFit(0.9), 1.0) && near(MSBDCCTLineFit(NAN), 1.0), "  ... at their own size while the names are no smaller than them"); }
    { MSBDCCTConnRow r[kMSBDCCTRows]; MSBDCCTConnLayout(142, 142, 1.25, 1.0, r);
      CHECK(near(MSBDCCTTextFit(nat16, r), 0.70), "  ... at Large there: 0.70 (77 pt for 109)"); }
    { MSBDCCTConnRow r[kMSBDCCTRows]; MSBDCCTConnLayout(153, 100, 1.25, 1.0, r);
      CHECK(r[0].circle.size.height <= r[0].row.size.height - 4 + 0.001, "  ... a block too low for its buttons: they shrink to the row (never over the next one)"); }
    { MSBDCCTConnRow r[kMSBDCCTRows]; MSBDCCTConnLayout(142, 142, 1.0, 1.0, r);
      const double huge[kMSBDCCTRows] = { 1000, 10, 10 }, none[kMSBDCCTRows] = { 0, NAN, -5 };
      CHECK(near(MSBDCCTTextFit(huge, r), kMSBDCCTTextMinFit), "  ... never under the floor (a label's own shrink-to-fit takes over below it)");
      CHECK(near(MSBDCCTTextFit(none, r), 1.0), "  ... no widths told: their own size"); }
    {   // a tile at Control Center Size: laid out at size 1 (its bounds over the size) and put at the size (CCTiles.h, CCLayout.h MSBDCCScaleRect)
        double z = 0.6;
        MSBDCCTConnRow r[kMSBDCCTRows]; MSBDCCTConnLayout(153, 153, 1.125, 1.0, r);
        CGRect tile = CGRectMake(0, 0, 153 * z, 153 * z);
        int ok = 1;
        for (int i = 0; i < kMSBDCCTRows; i++) {
            CGRect row = MSBDCCScaleRect(r[i].row, z), c = MSBDCCScaleRect(r[i].circle, z), t = MSBDCCScaleRect(r[i].title, z);
            ok &= inside(row, tile) && inside(c, row) && inside(t, row) && near(c.size.width / tile.size.width, r[i].circle.size.width / 153.0) && near(t.origin.x / tile.size.width, r[i].title.origin.x / 153.0);
        }
        CHECK(ok, "Connectivity at Control Center Size 0.6: every part inside the block and in the same proportion as at 1");
        MSBDCCTWideLayout L = MSBDCCTWideFrames(321, 69, 1.125);
        CGRect sl = MSBDCCScaleRect(L.slider, z);
        CHECK(near(sl.origin.x, 12 * z) && near(CGRectGetMaxX(sl), 309 * z) && inside(sl, CGRectMake(0, 0, 321 * z, 69 * z)), "  ... a wide tile's slider the same, 12 pt x 0.6 in");
    }
    // ---- the wide tiles ----
    for (int s = 0; s < 3; s++) {
        MSBDCCTWideLayout L = MSBDCCTWideFrames(321, 69, ks[s]);
        CGRect tile = CGRectMake(0, 0, 321, 69);
        int ok = inside(L.title, tile) && inside(L.chevron, tile) && inside(L.chevronHit, tile) && inside(L.slider, tile);
        ok &= L.slider.origin.y >= CGRectGetMaxY(L.title) && near(L.slider.origin.x, 12) && near(CGRectGetMaxX(L.slider), 309) && L.slider.size.height >= 20;
        ok &= CGRectContainsRect(L.chevronHit, L.chevron) && CGRectGetMaxX(L.title) <= L.chevron.origin.x && L.chevronHit.size.height <= 69.0 / 2 + 6 + 0.001;
        char what[160]; snprintf(what, sizeof what, "a wide tile (321 x 69) at scale %.3f: the title and chevron above the slider, all inside, the chevron's touch area around it, the slider 12 pt in", ks[s]);
        CHECK(ok, what);
    }
    { MSBDCCTWideLayout L = MSBDCCTWideFrames(321, 50, 1.25); CHECK(CGRectGetMaxY(L.slider) <= 50 - 8 + 0.001, "  ... a low tile: the slider gets shorter, never past the bottom margin"); }
    // ---- Now Playing ----
    for (int s = 0; s < 3; s++) {
        MSBDCCTNowLayout L = MSBDCCTNowFrames(321, 69, ks[s]);
        CGRect tile = CGRectMake(0, 0, 321, 69);
        int ok = inside(L.art, tile) && inside(L.title, tile) && inside(L.line, tile) && inside(L.play, tile) && inside(L.next, tile);
        ok &= near(L.art.size.width, L.art.size.height) && near(L.art.size.width, 45) && CGRectGetMaxX(L.art) < L.title.origin.x && CGRectGetMaxX(L.title) <= L.play.origin.x;
        ok &= near(CGRectGetMaxX(L.play), L.next.origin.x) && L.play.size.width >= 44 && L.title.size.width > 120 && CGRectGetMaxY(L.title) <= L.line.origin.y + 0.001;
        char what[160]; snprintf(what, sizeof what, "Now Playing (321 x 69) at scale %.3f: the artwork, its two lines, play / pause and next side by side, inside", ks[s]);
        CHECK(ok, what);
    }
    int f = -1, sl = -1;
    MSBDCCTNowLines(0, 0, 0, 0, &f, &sl); CHECK(f == 5 && sl == 0, "its lines: nothing playing: \"Not Playing\" alone");
    MSBDCCTNowLines(1, 1, 1, 1, &f, &sl); CHECK(f == 1 && sl == 2, "  ... the title, then the artist");
    MSBDCCTNowLines(1, 1, 0, 1, &f, &sl); CHECK(f == 1 && sl == 3, "  ... no artist: the album");
    MSBDCCTNowLines(1, 1, 0, 0, &f, &sl); CHECK(f == 1 && sl == 4, "  ... neither: the app");
    MSBDCCTNowLines(1, 0, 1, 0, &f, &sl); CHECK(f == 4 && sl == 2, "  ... no title: the app, then the artist");
    MSBDCCTNowLines(1, 0, 0, 0, &f, &sl); CHECK(f == 4 && sl == 0, "  ... the app alone");
    MSBDCCTNowLines(0, 1, 0, 0, NULL, NULL); CHECK(1, "  ... asked without places for the answers: nothing written");
    printf("%s: %d of %d checks passed\n", fails ? "FAIL" : "PASS", checks - fails, checks);
    return fails ? 1 : 0;
}
