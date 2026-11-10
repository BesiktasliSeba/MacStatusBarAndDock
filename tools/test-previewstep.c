// test-previewstep.c: moving between previews with the arrows and swipes (common/PreviewStep.h, 1.8.4.2 item 3), as Space-preview on a Mac: the
// list moves by Up and Down, the icon view by Left and Right and by a row with Up and Down; a swipe by one; the ends hold.
#include <stdio.h>
#include "../common/PreviewStep.h"
static int fails = 0;
static void check(const char *what, int ok) { printf("%s  %s\n", ok ? "PASS" : "FAIL", what); if (!ok) fails = 1; }
int main(void) {
    // ---- the list: 5 items
    check("the list: Down from the 2nd: the 3rd; Up: the 1st", MSBDPreviewStep(MSBD_STEP_DOWN, 0, 1, 1, 5) == 2 && MSBDPreviewStep(MSBD_STEP_UP, 0, 1, 1, 5) == 0);
    check("  ... Left and Right do nothing (a Mac's list folds folders with them)", MSBDPreviewStep(MSBD_STEP_LEFT, 0, 1, 2, 5) == -1 && MSBDPreviewStep(MSBD_STEP_RIGHT, 0, 1, 2, 5) == -1);
    check("  ... the columns given don't matter in the list", MSBDPreviewStep(MSBD_STEP_DOWN, 0, 4, 1, 5) == 2);
    check("  ... Up at the first, Down at the last: nothing", MSBDPreviewStep(MSBD_STEP_UP, 0, 1, 0, 5) == -1 && MSBDPreviewStep(MSBD_STEP_DOWN, 0, 1, 4, 5) == -1);
    check("  ... nothing selected: Down the first, Up the last", MSBDPreviewStep(MSBD_STEP_DOWN, 0, 1, -1, 5) == 0 && MSBDPreviewStep(MSBD_STEP_UP, 0, 1, -1, 5) == 4);
    check("  ... the selected item gone from the list (index past the end): as nothing selected", MSBDPreviewStep(MSBD_STEP_DOWN, 0, 1, 9, 5) == 0);
    check("  ... an empty folder: nothing", MSBDPreviewStep(MSBD_STEP_DOWN, 0, 1, -1, 0) == -1 && MSBDPreviewStep(MSBD_STEP_SWIPE_NEXT, 1, 4, 0, 0) == -1);
    // ---- the icon view: 10 items, 4 to a row (rows: 0-3, 4-7, 8-9)
    check("icons: Right from the 2nd: the 3rd; Left: the 1st", MSBDPreviewStep(MSBD_STEP_RIGHT, 1, 4, 1, 10) == 2 && MSBDPreviewStep(MSBD_STEP_LEFT, 1, 4, 1, 10) == 0);
    check("  ... Right at a row's end goes on to the next row's first, as on a Mac", MSBDPreviewStep(MSBD_STEP_RIGHT, 1, 4, 3, 10) == 4);
    check("  ... Down: the item below (2nd -> 6th); Up: the one above (6th -> 2nd)", MSBDPreviewStep(MSBD_STEP_DOWN, 1, 4, 1, 10) == 5 && MSBDPreviewStep(MSBD_STEP_UP, 1, 4, 5, 10) == 1);
    check("  ... Up in the first row: nothing", MSBDPreviewStep(MSBD_STEP_UP, 1, 4, 2, 10) == -1);
    check("  ... Down from the 8th (nothing below it in the short last row): the last item", MSBDPreviewStep(MSBD_STEP_DOWN, 1, 4, 7, 10) == 9);
    check("  ... Down in the last row: nothing", MSBDPreviewStep(MSBD_STEP_DOWN, 1, 4, 8, 10) == -1 && MSBDPreviewStep(MSBD_STEP_DOWN, 1, 4, 9, 10) == -1);
    check("  ... Right at the last, Left at the first: nothing", MSBDPreviewStep(MSBD_STEP_RIGHT, 1, 4, 9, 10) == -1 && MSBDPreviewStep(MSBD_STEP_LEFT, 1, 4, 0, 10) == -1);
    check("  ... one icon to a row (a narrow window): Up and Down by one", MSBDPreviewStep(MSBD_STEP_DOWN, 1, 1, 3, 10) == 4 && MSBDPreviewStep(MSBD_STEP_UP, 1, 1, 3, 10) == 2);
    check("  ... columns not known (0): one to a row", MSBDPreviewStep(MSBD_STEP_DOWN, 1, 0, 3, 10) == 4);
    // ---- swipes: by one, either view
    check("a swipe to the left: the next item; to the right: the one before (list and icons)",
          MSBDPreviewStep(MSBD_STEP_SWIPE_NEXT, 0, 1, 2, 5) == 3 && MSBDPreviewStep(MSBD_STEP_SWIPE_PREV, 0, 1, 2, 5) == 1
          && MSBDPreviewStep(MSBD_STEP_SWIPE_NEXT, 1, 4, 3, 10) == 4 && MSBDPreviewStep(MSBD_STEP_SWIPE_PREV, 1, 4, 4, 10) == 3);
    check("  ... at the ends: nothing", MSBDPreviewStep(MSBD_STEP_SWIPE_NEXT, 0, 1, 4, 5) == -1 && MSBDPreviewStep(MSBD_STEP_SWIPE_PREV, 1, 4, 0, 10) == -1);
    check("anything else: nothing", MSBDPreviewStep(0, 0, 1, 2, 5) == -1 && MSBDPreviewStep(99, 1, 4, 2, 10) == -1);
    if (fails) { printf("test-previewstep (compiled): FAILED\n"); return 1; }
    printf("test-previewstep (compiled): all checks pass\n"); return 0;
}
