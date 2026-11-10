// PreviewStep.h -- moving between previews (1.8.4.2 item 3, KT 8 Nov 2026), as Space-preview on a Mac: with Quick Look open, the arrow keys move
// the selection in the Finder window behind it and the preview follows. In the list Up and Down move (Left and Right don't: a Mac's list uses
// them to fold folders); in the icon view Left and Right move by one, Up and Down by a row. A swipe moves by one in either view (a swipe to the
// left shows the next item, as a page turns). At either end the selection stays. Plain C, so the Mac test (tools/test-previewstep.c) runs this
// very code; Finder.h (DMQuickLookWindow -dm_handleKey:, its swipes; DMFinderWindow -dm_previewStep:) feeds it.
#ifndef MSBD_PREVIEW_STEP_H
#define MSBD_PREVIEW_STEP_H

enum { MSBD_STEP_UP = 1, MSBD_STEP_DOWN, MSBD_STEP_LEFT, MSBD_STEP_RIGHT, MSBD_STEP_SWIPE_NEXT, MSBD_STEP_SWIPE_PREV };

// The item selected after `move` (MSBD_STEP_*), from `index` (-1: none selected) among `count`, `columns` to a row in the icon view (icons 1).
// -1: the move does nothing here (the selection, and the preview, stay as they are).
static inline long MSBDPreviewStep(int move, int icons, long columns, long index, long count) {
    if (count <= 0) return -1;
    if (columns < 1) columns = 1;
    long by;
    switch (move) {
        case MSBD_STEP_UP: by = icons ? -columns : -1; break;
        case MSBD_STEP_DOWN: by = icons ? columns : 1; break;
        case MSBD_STEP_LEFT: if (!icons) return -1; by = -1; break;
        case MSBD_STEP_RIGHT: if (!icons) return -1; by = 1; break;
        case MSBD_STEP_SWIPE_NEXT: by = 1; break;
        case MSBD_STEP_SWIPE_PREV: by = -1; break;
        default: return -1;
    }
    if (index < 0 || index >= count) return by > 0 ? 0 : count - 1;   // (nothing selected: the first item, or the last going back)
    long to = index + by;
    if (to < 0) return -1;
    if (to >= count) {   // (down from a row above the last, short one, with nothing right below: the last item, as on a Mac)
        if (icons && by == columns && index / columns < (count - 1) / columns) return count - 1;
        return -1;
    }
    return to;
}
#endif
