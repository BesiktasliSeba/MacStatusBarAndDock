// PageDotsOwner.h -- whose page dots Hide Page Dots hides (macsettings/PageDots.x, MacPageDots; Mac-tested: tools/test-pagedots.sh). Plain C.
// The Home Screen's page dots are an SBIconListPageControl made by the folder view whose pages they show, which is also the control's delegate:
// SBRootFolderView for the Home Screen's pages, the open folder's view for a folder -- SpringBoard's own classes (SpringBoardHome). iPadOS 18's
// Control Center lays its pages out with the same folder views (ControlCenterUI.IconListRootFolderView, a subclass of SBRootFolderView), so the
// page glyphs on its right edge (heart, music, antenna) are an SBIconListPageControl too, and hiding every page control hid them with the Home
// Screen's dots (1.7.1 item 12; read on the A12Z, 18.5: the Home Screen's control's delegate SBRootFolderView, Control Center's
// ControlCenterUI.IconListRootFolderView, in SBControlCenterWindow). So the dots are hidden only where that folder view is SpringBoard's own; a
// folder view another framework made keeps its page control as iPadOS shows it.
#pragma once
#include <string.h>

// ownerImage: the image (class_getImageName) of the class of the page control's delegate; NULL when it has none or its image is unknown.
// Returns 1 for the Home Screen's dots (hidden), 0 for another part's (left alone).
static inline int MSBDPageDotsHomeScreens(const char *ownerImage) {
    if (!ownerImage || !*ownerImage) return 1;   // (no owner known: hidden, as before 1.7.1)
    const char *name = strrchr(ownerImage, '/');
    name = name ? name + 1 : ownerImage;
    // (SpringBoardHome: its folder views, 13 and later; SpringBoard: the app's own classes -- SpringBoard.app's executable, or 18's
    //  SpringBoard.framework)
    return !strcmp(name, "SpringBoardHome") || !strcmp(name, "SpringBoard");
}

// The hidden flag a page control's -setHidden: stores (1.8.1 item 5). iPadOS shows the Home Screen's dots again through -setHidden: on paths that
// lay nothing out after it, so the -layoutSubviews hide alone left them on the screen until the control's next layout (read in the M1's 15.6.1
// SpringBoardHome and UIKitCore):
//  - a turn of the screen: SBRootFolderController hides the dots for the turn and shows them at its end (-setPageControlHidden:NO, through
//    SBFolderView to the control); the turn had laid the control out already;
//  - the page editor closing: SBRootFolderView takes its page control back and sets it visible (-elementBorrowedAssertionDidInvalidate:);
//  - UIPageControl itself, with hidesForSinglePage: a new page count (-setNumberOfPages:, edit mode's extra page) or hidesForSinglePage changing
//    sets hidden from the count;
//  - another tweak: ClassicFolders3 hides the Home Screen's page control while its folder is open and sets it visible when the folder closes --
//    the M1's dots, seen now and then: they stayed until the next page swipe.
// hide: Hide Page Dots is on and no other tweak does it; ownerImage: as MSBDPageDotsHomeScreens. Only a KNOWN owner keeps the dots hidden here: a
// control whose folder view is not known yet stores what iPadOS asks, and its first layout decides, as before (so another part's page control,
// such as iPadOS 18's Control Center glyphs, is never held hidden by an early call). requested: what iPadOS asks for.
static inline int MSBDPageDotsStoreHidden(int hide, const char *ownerImage, int requested) {
    if (!hide || !ownerImage || !*ownerImage) return requested;
    return MSBDPageDotsHomeScreens(ownerImage) ? 1 : requested;
}
