// test-displayscale.c -- Mac test of More Space's rules (1.8.7 commit 13; common/DisplayScale.h): the scales listed in iPadOS's mask, the row only with
// a choice, Apple's names and the choices' titles, the overscan tip, and the timing of the record kept before a change. tools/test-displayscale.sh
// runs it, checks the sites, then made-to-fail copies of the rules.
#include <stdio.h>
#include <string.h>
#include "../common/DisplayScale.h"

static int fails = 0, passes = 0;
#define EXPECT(c, msg) do { if (c) passes++; else { fails++; printf("FAIL  %s\n", msg); } } while (0)

int main(void) {
    int out[16];
    // ---- the mask
    EXPECT(MSBDDispScaleListed(2, out, 16) == 1 && out[0] == 1, "mask 2 (the A12Z's 4K TV and the iPad 2's 1080p TV, S2): scale 1 only");
    EXPECT(!MSBDDispScaleRowWanted(2), "... one scale: no Resolution row");
    EXPECT(!MSBDDispScaleRowWanted(0), "nothing read: no row");
    EXPECT(MSBDDispScaleListed(1, out, 16) == 0 && !MSBDDispScaleIsListed(1, 0), "bit 0 (scale 0) is never a scale: SpringBoardServices asserts on it");
    EXPECT(MSBDDispScaleListed(2 | 4 | 8, out, 16) == 3 && out[0] == 1 && out[1] == 2 && out[2] == 3, "three listed: in order");
    EXPECT(MSBDDispScaleRowWanted(2 | 8), "two listed: the row");
    EXPECT(MSBDDispScaleListed(1ULL << 16, out, 16) == 0, "a bit past 15: not a scale");
    EXPECT(MSBDDispScaleCanSet(2 | 4, 1, 2) && !MSBDDispScaleCanSet(2 | 4, 1, 1) && !MSBDDispScaleCanSet(2 | 4, 1, 3) && !MSBDDispScaleCanSet(2 | 4, 1, 0),
           "a scale is set only when listed and not in use (an unlisted value is never made)");
    // ---- Apple's names
    char n[32];
    const char *desc = "<SBSDisplayModeSettings: 0xd6611b080; scale: .Standard; overscan: .None>";
    EXPECT(MSBDDispScaleFieldName(desc, "scale", n, sizeof n) && strcmp(n, "Standard") == 0, "the scale's name from the settings' description (S2's line)");
    EXPECT(MSBDDispScaleFieldName(desc, "overscan", n, sizeof n) && strcmp(n, "None") == 0, "the overscan's name");
    EXPECT(!MSBDDispScaleFieldName(desc, "zoom", n, sizeof n) && n[0] == 0, "a field not there: none");
    EXPECT(!MSBDDispScaleFieldName(NULL, "scale", n, sizeof n), "no description: none");
    EXPECT(MSBDDispScaleFieldName("scale: .MoreSpaceVeryLongNameThatGoesOnAndOn;", "scale", n, 8) && strlen(n) == 7, "a long name is cut to the buffer");
    EXPECT(strcmp(MSBDDispScaleTitle("Standard"), "Default") == 0, ".Standard is Default");
    EXPECT(strcmp(MSBDDispScaleTitle("LargerText"), "Larger Text") == 0 && strcmp(MSBDDispScaleTitle("Zoomed"), "Larger Text") == 0, "Larger / Zoom: Larger Text");
    EXPECT(strcmp(MSBDDispScaleTitle("MoreSpace"), "More Space") == 0 && strcmp(MSBDDispScaleTitle("Dense"), "More Space") == 0, "Space / Dense: More Space");
    EXPECT(MSBDDispScaleTitle("Native") == NULL && MSBDDispScaleTitle("") == NULL && MSBDDispScaleTitle(NULL) == NULL, "any other name: Apple's own is shown");
    // ---- the overscan tip
    EXPECT(MSBDDispOverscanTip("None") && !MSBDDispOverscanTip("Scale") && !MSBDDispOverscanTip(NULL), "the tip where iPadOS does not shrink the picture (.None)");
    // ---- the record kept before a change
    EXPECT(MSBDDispScaleAtStart(0, 1000, 990) == kMSBDDispScaleStartNothing, "no record: nothing at the start");
    EXPECT(MSBDDispScaleAtStart(1, 1000, 1000 - 30) == kMSBDDispScaleStartRevert, "a start 30 s after an unresolved change: the old scale back");
    EXPECT(MSBDDispScaleAtStart(1, 1000, 1000 - 120) == kMSBDDispScaleStartRevert, "... at 2 min: back");
    EXPECT(MSBDDispScaleAtStart(1, 1000, 1000 - 121) == kMSBDDispScaleStartDrop, "... later than 2 min: the record dropped, nothing set");
    EXPECT(MSBDDispScaleAtStart(1, 1000, 1000 + 50) == kMSBDDispScaleStartDrop, "a record from the future (the clock set back): dropped");
    EXPECT(!MSBDDispScaleRevertsNow(0, 1014, 1000) && MSBDDispScaleRevertsNow(0, 1015, 1000) && !MSBDDispScaleRevertsNow(1, 1030, 1000), "no answer in 15 s: reverted; answered: never");
    EXPECT(!MSBDDispScaleDropNow(1059, 1000) && MSBDDispScaleDropNow(1060, 1000), "an unresolved record dropped after 60 s of running");
    // ---- a set's outcome read back (review: the completion's parameters are never read)
    EXPECT(MSBDDispScaleSetTook(1, 2, 2) && !MSBDDispScaleSetTook(1, 1, 2), "a set took when the display reads the scale asked for, not when it still reads the old one");
    EXPECT(MSBDDispScaleSetTook(0, 0, 2), "... a display not listed after the tries: unknown, counted as done (the question is still asked)");
    // ---- the start's revert keeps its record until it is taken (review)
    long at = 1000;
    EXPECT(!MSBDDispScaleStartRevertDrop(0, 0, 0, 0, 1, at + 3, at), "a start with the display not listed yet (3 s in): the record kept, tried again when it connects");
    EXPECT(MSBDDispScaleStartRevertDrop(1, 1, 2 | 4, 1, 1, at + 3, at), "... the old scale set back: the record goes");
    EXPECT(!MSBDDispScaleStartRevertDrop(0, 1, 2 | 4, 2, 1, at + 3, at), "... listed, the set refused: kept, tried again");
    EXPECT(MSBDDispScaleStartRevertDrop(0, 1, 2 | 4, 1, 1, at + 3, at), "... listed and already at the old scale: nothing to set back, the record goes");
    EXPECT(MSBDDispScaleStartRevertDrop(0, 1, 2 | 8, 3, 2, at + 3, at), "... listed and the old scale no longer listed: the record goes (it is never made)");
    EXPECT(!MSBDDispScaleStartRevertDrop(0, 0, 0, 0, 1, at + MSBD_DISP_SCALE_CRASH_WINDOW, at), "... not listed at 2 min: still kept");
    EXPECT(MSBDDispScaleStartRevertDrop(0, 0, 0, 0, 1, at + MSBD_DISP_SCALE_CRASH_WINDOW + 1, at), "... past 2 min: the record goes");
    EXPECT(MSBDDispScaleRevertDone(1, 0, 0, 0, 1) && !MSBDDispScaleRevertDone(0, 0, 0, 0, 1) && MSBDDispScaleRevertDone(0, 1, 2 | 4, 1, 1), "the question's revert: done when taken, or nothing left to take back");
    printf("test-displayscale: %d passed, %d failed\n", passes, fails);
    return fails ? 1 : 0;
}
