// FitQuestionPlace.h -- where Fit to Window's questions draw their panels and their title (the side question for a third window, the half-and-quarter
// trade), plain C on CoreGraphics so the Mac test (tools/test-fitpanels.c) runs this very code; StatusBar.x DMSidePanel, DMShowSidePrompt and
// DMSwapHalfWithQuarter draw with it (1.8.3 item 6).
//  - A panel is a picture of where the window will go: the WINDOW's frame for that layout (its title bar and app, as drawn), 12 pt in on every side.
//    Every engine shares that frame (StatusBar.x DMLayoutFrameWindow: the layout cut from the desktop). The panels used the ENGINE's frame instead
//    (DMLayoutFrame), which is the window itself on Stage Manager, Zetsu, MilkyWay4 and Aerial 3.0, but Aerial 5.x's stage on Aerial 5.x: the window
//    grown by Aerial's own margins, 6 pt at each side and 9 pt more below. So Aerial 5's panels stood 6 pt further out and 9 pt taller than Stage
//    Manager's (iPad 2, Dock at Left: {62.5, 32, 468 x 733} against {68.5, 32, 456 x 724}, regression-1.8.2.2-ipad2.md F1). The title and the No Fit
//    seam matched already: the stage's top and its middle are the window's.
//  - The title stands 16 pt under the top of the desktop (the Fill layout's window).
#ifndef MSBD_FIT_QUESTION_PLACE_H
#define MSBD_FIT_QUESTION_PLACE_H
#include <CoreGraphics/CoreGraphics.h>

#define kMSBDFitPanelInset 12.0   // (the panel inside the window's frame)
#define kMSBDFitTitleDrop 16.0    // (the title under the desktop's top)

// The panel for a layout, from the window's frame at that layout (null or empty: null, nothing is drawn there).
static inline CGRect MSBDFitQuestionPanel(CGRect window) {
    if (CGRectIsNull(window) || CGRectIsEmpty(window)) return CGRectNull;
    return CGRectInset(window, kMSBDFitPanelInset, kMSBDFitPanelInset);
}
// The title's top, from the window's frame at Fill (the desktop).
static inline CGFloat MSBDFitQuestionTitleY(CGRect fill) { return CGRectIsNull(fill) ? kMSBDFitTitleDrop : fill.origin.y + kMSBDFitTitleDrop; }

#endif
