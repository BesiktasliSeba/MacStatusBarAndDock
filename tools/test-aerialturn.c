// Mac test of statusbar/AerialTurn.h: Aerial 5's windows keep their turn while it fades them around iPadOS's App Switcher (1.8.1 item 7), and on 15 their frame.
// The writes are those read on the iPad 2 (16.7.7, Aerial 5.1, landscape 3, the layer trace a5wintrace_): the fade's 0.9, 0.92 and 1, Aerial's own turn, the frames.
#include <stdio.h>
#include "../statusbar/AerialTurn.h"
static int checks, fails;
#define CHECK(c, what) do { checks++; if (c) printf("PASS  %s\n", what); else { fails++; printf("FAIL  %s\n", what); } } while (0)
int main(void) {
    CHECK(MSBDA5PlainScale(0.9, 0, 0, 0.9) && MSBDA5PlainScale(0.92, 0, 0, 0.92) && MSBDA5PlainScale(1, 0, 0, 1), "the fade's writes are plain scales");
    CHECK(!MSBDA5PlainScale(6.123233995736766e-17, 1, -1, 6.123233995736766e-17), "Aerial's own turn to 3 is not");
    CHECK(!MSBDA5PlainScale(0, -1, 1, 0) && !MSBDA5PlainScale(-1, 0, 0, -1), "nor its turns to 4 and 2");
    CHECK(MSBDA5KeepsTurn(true, 3, 0.92, 0, 0, 0.92) && MSBDA5KeepsTurn(true, 3, 1, 0, 0, 1) && MSBDA5KeepsTurn(true, 3, 0.9, 0, 0, 0.9), "landscape, in the fade: the scale keeps the turn");
    CHECK(MSBDA5KeepsTurn(true, 4, 1, 0, 0, 1) && MSBDA5KeepsTurn(true, 2, 1, 0, 0, 1), "the other turned orientations too");
    CHECK(!MSBDA5KeepsTurn(true, 1, 0.92, 0, 0, 0.92), "upright: nothing to keep, Aerial's scale as it is");
    CHECK(!MSBDA5KeepsTurn(false, 3, 1, 0, 0, 1), "no fade (the iPad turning to upright, say): Aerial's write as it is");
    CHECK(!MSBDA5KeepsTurn(true, 3, 6.123233995736766e-17, 1, -1, 6.123233995736766e-17), "Aerial's own turn during the fade goes through");
    double a, b, c, d;
    MSBDA5TurnFor(3, &a, &b, &c, &d); CHECK(a == 0 && b == 1 && c == -1 && d == 0, "the turn for 3");
    MSBDA5TurnFor(4, &a, &b, &c, &d); CHECK(a == 0 && b == -1 && c == 1 && d == 0, "the turn for 4");
    MSBDA5TurnFor(2, &a, &b, &c, &d); CHECK(a == -1 && b == 0 && c == 0 && d == -1, "the turn for 2");
    MSBDA5TurnFor(1, &a, &b, &c, &d); CHECK(a == 1 && b == 0 && c == 0 && d == 1, "upright: none");
    CHECK(MSBDA5SameTransform(6.123233995736766e-17, 1, -1, 6.123233995736766e-17, 0, 1, -1, 0), "Aerial's turn is the same as ours, its near-zero terms aside");
    CHECK(!MSBDA5FrameGoes(true, 3, 0, 0, 1024, 768, 768, 1024), "in the fade: the frame of a window with no turn is not written");
    CHECK(!MSBDA5FrameGoes(true, 3, 0, 0, 921.6, 691.2, 768, 1024), "  ... nor the one scaled to 0.9");
    CHECK(MSBDA5FrameGoes(true, 3, 0, 0, 768, 1024, 768, 1024), "  ... the native screen's is (Aerial's own turn)");
    CHECK(MSBDA5FrameGoes(true, 1, 0, 0, 921.6, 691.2, 768, 1024), "upright: every frame as Aerial writes it");
    CHECK(MSBDA5FrameGoes(false, 3, 0, 0, 1024, 768, 768, 1024), "no fade: every frame as Aerial writes it");
    // 15: no turn; the write read on the M1 (15.6.1, Aerial 5.1, landscape 3): {{0, 0}, {1074.6, 750.6}} under the fade's 0.9, the bounds {1194, 834}.
    #define S15 0.90000000000000002, 0, 0, 0.90000000000000002
    CHECK(!MSBDA5FrameGoesNoTurn(true, S15, 0, 0, 1074.5999999999999, 750.59999999999991, 1194, 833.99999999999989), "15, in the fade: the scaled frame at the origin is not written");
    CHECK(!MSBDA5FrameGoesNoTurn(true, 0.92, 0, 0, 0.92, 0, 0, 1098.48, 767.28, 1194, 834), "  ... nor under the way back's 0.92");
    CHECK(!MSBDA5FrameGoesNoTurn(true, S15, 0, 0, 750.6, 1074.6, 834, 1194), "  ... nor in portrait");
    CHECK(MSBDA5FrameGoesNoTurn(true, S15, 0, 0, 1194, 834, 1194, 834), "  ... another frame (the screen's) goes through as before");
    CHECK(MSBDA5FrameGoesNoTurn(true, S15, 0, 0, 834, 1194, 1194, 834), "  ... a turn's goes through as before");
    CHECK(MSBDA5FrameGoesNoTurn(true, S15, 59.7, 41.7, 1074.6, 750.6, 1194, 834), "  ... the frame where it already is, too");
    CHECK(MSBDA5FrameGoesNoTurn(true, 1, 0, 0, 1, 0, 0, 1194, 834, 1194, 834), "15, in the fade at 1: every frame as Aerial writes it");
    CHECK(MSBDA5FrameGoesNoTurn(false, S15, 0, 0, 1074.6, 750.6, 1194, 834), "15, no fade: every frame as Aerial writes it");
    CHECK(MSBDA5FrameGoesNoTurn(true, 0, 1, -1, 0, 0, 0, 834, 1194, 1194, 834), "15: only a plain scale holds a frame back, not any transform");
    printf("%s: %d checks, %d failed\n", fails ? "FAILED" : "ok", checks, fails);
    return fails ? 1 : 0;
}
