// SidebarScroll.h -- Settings' sidebar (the main list, iPadOS 15-17): a scroll that one of our parts made on purpose, which MacSettings' cold-launch
// correction leaves alone.
// The correction (macsettings/MacSettings.x, -[PSUIPrefsListController viewWillAppear:]) puts the sidebar back at its top a few times in the first
// 0.6 s of each launch: a stale offset that Settings put back cut a row in half at the top. A page of ours opened from SpringBoard when Settings was
// not running (the welcome alert's "Take Me There", the crash notice's "Open Settings", "Edit Go Menu…", the engine notices:
// statusbar/macstatusbarsettings/StatusBarSettingsRow.x, OpenPage) scrolls the sidebar to its row, and the correction undid that 0.1 s later: the
// page opened with its row selected below the part of the list on screen (M1 15.6.1, 1.6.0; traced: the only offset change after ours was the
// correction's). The two parts are separate libraries in Settings, so the mark is an associated object under a selector's name (one per process).
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static inline const void *MSBDSidebarScrollKey(void) { return (const void *)sel_registerName("msbdSidebarScrolledOnPurpose"); }
static inline void MSBDSidebarMarkScrolled(UIScrollView *list) {
    if (list) objc_setAssociatedObject(list, MSBDSidebarScrollKey(), @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static inline BOOL MSBDSidebarScrolledOnPurpose(UIScrollView *list) {
    return list && objc_getAssociatedObject(list, MSBDSidebarScrollKey()) != nil;
}
