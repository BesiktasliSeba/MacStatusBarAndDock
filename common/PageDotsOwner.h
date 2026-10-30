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
