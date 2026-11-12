// Mac test of common/PointerRegion.h (1.8.7, the iPad 2's AirPlay B pass: rows 14 and 6.6): the iPad's own region in backboardd's pointer space, learned
// from the iPad's hover, and a push at the iPad's bottom edge right after the pointer left another display.
#include <stdio.h>
#include "../common/PointerRegion.h"
static int fails = 0, checks = 0;
static void Expect(const char *what, double got, double want) {
    checks++;
    if (!(fabs(got - want) < 1e-6 || (isnan(got) && isnan(want)))) { fails++; printf("FAIL %s: got %g, want %g\n", what, got, want); }
}
int main(void) {
    MSBDPtrRegion r; double x = 0, y = 0;
    // the iPad alone: the origin, as before 1.8.7 (an A12Z: 1024 x 1366 native)
    MSBDPtrRegionReset(&r, 0);
    Expect("alone: known", r.known, 1);
    Expect("alone: a place on the iPad is the iPad's", MSBDPtrOnIPad(&r, 500, 700, 1024, 1366, &x, &y), 1);
    Expect("  ... the same point", x * 10000 + y, 500 * 10000 + 700);
    Expect("alone: a negative place is not (as before)", MSBDPtrOnIPad(&r, -5, 10, 1024, 1366, &x, &y), 0);
    Expect("alone: no reading is taken (nothing to learn)", MSBDPtrRegionLearn(&r, 100, 100, 50, 50), 0);
    Expect("  ... the origin stays", r.ox * 10000 + r.oy, 0);
    // the A12Z with its HDMI TV above (read 11 Nov 18:58-19:31): the iPad at x -1440..-416, the TV over -416..1024
    MSBDPtrRegionReset(&r, 1);
    Expect("TV attached: not known yet", r.known, 0);
    Expect("  ... a place is neither the iPad's nor another's yet (-1: the iPad's own hover decides)", MSBDPtrOnIPad(&r, -880, 716, 1024, 1366, &x, &y), -1);
    Expect("a first reading waits", MSBDPtrRegionLearn(&r, -880.2, 716.1, 559.9, 716.0), 0);
    Expect("  ... still not known", r.known, 0);
    Expect("a second that agrees: learned", MSBDPtrRegionLearn(&r, -880.0, 716.0, 560.0, 716.0), 1);
    Expect("  ... at x -1440", r.ox, -1440);
    Expect("  ... and y 0", r.oy, 0);
    Expect("the iPad's top edge (the TV's bottom, -420): on the iPad", MSBDPtrOnIPad(&r, -420, 716, 1024, 1366, &x, &y), 1);
    Expect("  ... its own x 1020 (4 pt under its top in landscape)", x, 1020);
    Expect("the line the two share (-416): the iPad's top", MSBDPtrOnIPad(&r, -416, 716, 1024, 1366, &x, &y), 1);
    Expect("  ... x 1024", x, 1024);
    Expect("on the TV (-275): not the iPad's", MSBDPtrOnIPad(&r, -275, 716, 1024, 1366, &x, &y), 0);
    Expect("the TV's top (1020: was read as the iPad's top before): not the iPad's", MSBDPtrOnIPad(&r, 1020, 716, 1024, 1366, &x, &y), 0);
    Expect("the iPad's bottom (-1440): the iPad's", MSBDPtrOnIPad(&r, -1440, 716, 1024, 1366, &x, &y), 1);
    Expect("  ... x 0", x, 0);
    Expect("beyond the iPad's side (y 1400): not the iPad's", MSBDPtrOnIPad(&r, -900, 1400, 1024, 1366, &x, &y), 0);
    Expect("not a number: not the iPad's", MSBDPtrOnIPad(&r, NAN, 1, 1024, 1366, &x, &y), 0);
    // the iPad 2 over AirPlay (read 11 Nov 14:00): the iPad at -1080..-312 (768 x 1024 native)
    MSBDPtrRegionReset(&r, 1);
    MSBDPtrRegionLearn(&r, -700, 300, 380, 300); MSBDPtrRegionLearn(&r, -700, 300, 380, 300);
    Expect("iPad 2: learned at -1080", r.ox, -1080);
    Expect("iPad 2: -314 (row 10.2b's place) is 2 pt under the iPad's top", MSBDPtrOnIPad(&r, -314, 300, 768, 1024, &x, &y) * 1000 + (768 - x), 1002);
    Expect("iPad 2: the TV's -100: not the iPad's", MSBDPtrOnIPad(&r, -100, 300, 768, 1024, &x, &y), 0);
    // readings that do not agree (a pointer that moved): not taken until two do
    MSBDPtrRegionReset(&r, 1);
    MSBDPtrRegionLearn(&r, -880, 716, 560, 716);
    Expect("disagreeing second (4 pt): not learned", MSBDPtrRegionLearn(&r, -876, 716, 560, 716), 0);
    Expect("  ... not known", r.known, 0);
    Expect("a third agreeing with the second: learned", MSBDPtrRegionLearn(&r, -876, 716, 560, 716), 1);
    Expect("  ... at the second's", r.ox, -1436);
    // the arrangement changed in Settings while attached: two readings of the new place move it
    MSBDPtrRegionLearn(&r, -500, 716, 580, 716);
    Expect("a moved region needs two readings", r.ox, -1436);
    Expect("  ... the second moves it", MSBDPtrRegionLearn(&r, -500, 716, 580, 716), 1);
    Expect("  ... to -1080", r.ox, -1080);
    Expect("the same again: no change", MSBDPtrRegionLearn(&r, -500, 716, 580, 716) + MSBDPtrRegionLearn(&r, -500, 716, 580, 716), 0);
    // a reading a point off the known place (half points rounded the other way, A12Z d23: -1440 / -1439 / -1440): kept
    MSBDPtrRegionReset(&r, 1);
    MSBDPtrRegionLearn(&r, -848.41, 602.78, 591.59, 5.78); MSBDPtrRegionLearn(&r, -848.41, 602.78, 591.59, 5.78);
    Expect("A12Z d23: learned at {-1440, 597} (the iPad centred under the 2560 pt TV)", r.ox * 10000 + r.oy, -1440 * 10000 + 597);
    Expect("  ... a reading at -1439.49 (rounds to -1439): no change", MSBDPtrRegionLearn(&r, -513.43, 895.75, 926.06, 298.75) + MSBDPtrRegionLearn(&r, -513.43, 895.75, 926.06, 298.75), 0);
    Expect("  ... the origin kept", r.ox, -1440);
    // the display goes: the origin again
    MSBDPtrRegionReset(&r, 0);
    Expect("unplugged: the origin, known", r.known * 10 + (r.ox == 0 && r.oy == 0), 11);
    // a push at the bottom edge after the pointer left another display (MSBDPtrArrivedFromOther)
    Expect("began 0.4 s after the pointer left the TV: from the TV", MSBDPtrArrivedFromOther(10.0, 10.4), 1);
    Expect("began 0.99 s after: from the TV", MSBDPtrArrivedFromOther(10.0, 10.99), 1);
    Expect("began 1.2 s after: the user's own push", MSBDPtrArrivedFromOther(10.0, 11.2), 0);
    Expect("the pointer never on another display: ours", MSBDPtrArrivedFromOther(0.0, 5.0), 0);
    Expect("the pointer on the other display after it began: not that", MSBDPtrArrivedFromOther(10.0, 9.9), 0);
    printf("test-pointerregion: %d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
