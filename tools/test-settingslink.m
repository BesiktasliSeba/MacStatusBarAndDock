// Mac test of the links into our Settings pages for iPadOS 18's SwiftUI root (common/SettingsRoot.h MSBDSettingsLinkForRoot), and of how SpringBoard
// opens Settings on our pages (MSBDPageOpenFor: a window exactly when Open Apps as Windows is on; MSBDPageLink).
#import <Foundation/Foundation.h>
#include "../common/SettingsRoot.h"
static int fails = 0, checks = 0;
static void Expect(NSString *link, BOOL swiftUI, NSString *want) {
    NSString *got = MSBDSettingsLinkForRoot(link, swiftUI);
    checks++;
    if (!(got == want || [got isEqualToString:want])) { fails++; printf("FAIL %s (swiftUI %d): got %s, want %s\n", link.UTF8String, swiftUI, got.UTF8String, want.UTF8String); }
}
int main(void) {
    @autoreleasepool {
        // 15-17 (or not recorded): every link as it is
        Expect(@"prefs:root=DOCK_MAGNIFICATION&path=DOWNLOADS", NO, @"prefs:root=DOCK_MAGNIFICATION&path=DOWNLOADS");
        Expect(@"prefs:root=MAC_STATUS_BAR", NO, @"prefs:root=MAC_STATUS_BAR");
        // 18: our two pages through General
        Expect(@"prefs:root=DOCK_MAGNIFICATION&path=DOWNLOADS", YES, @"prefs:root=General&path=MSBD_PL_DockMagnificationPrefs/DOWNLOADS");
        Expect(@"prefs:root=DOCK_MAGNIFICATION&path=FINDER", YES, @"prefs:root=General&path=MSBD_PL_DockMagnificationPrefs/FINDER");
        Expect(@"prefs:root=DOCK_MAGNIFICATION", YES, @"prefs:root=General&path=MSBD_PL_DockMagnificationPrefs");
        Expect(@"prefs:root=MAC_STATUS_BAR", YES, @"prefs:root=General&path=MSBD_PL_MacStatusBarPrefs");
        Expect(@"prefs:root=MAC_STATUS_BAR#Show%20Seconds", YES, @"prefs:root=General&path=MSBD_PL_MacStatusBarPrefs#Show%20Seconds");
        Expect(@"prefs:root=MAC_STATUS_BAR%23Show%20Seconds", YES, @"prefs:root=General&path=MSBD_PL_MacStatusBarPrefs%23Show%20Seconds");
        Expect(@"prefs:root=MAC_STATUS_BAR&path=GO_APPS#x", YES, @"prefs:root=General&path=MSBD_PL_MacStatusBarPrefs/GO_APPS#x");
        // our Keyboard and Pointer pages (the sidebar's rows on 15-17; rows of the same identifiers at the top of General on 18)
        Expect(@"prefs:root=MAC_KEYBOARD", NO, @"prefs:root=MAC_KEYBOARD");
        Expect(@"prefs:root=MAC_POINTER", NO, @"prefs:root=MAC_POINTER");
        Expect(@"prefs:root=MAC_KEYBOARD", YES, @"prefs:root=General&path=MAC_KEYBOARD");
        Expect(@"prefs:root=MAC_POINTER", YES, @"prefs:root=General&path=MAC_POINTER");
        Expect(@"prefs:root=MAC_POINTER#Pointer%20Style", YES, @"prefs:root=General&path=MAC_POINTER#Pointer%20Style");
        Expect(@"prefs:root=MAC_KEYBOARD%23Tab%20Key%20Toggles%20Mute", YES, @"prefs:root=General&path=MAC_KEYBOARD%23Tab%20Key%20Toggles%20Mute");
        Expect(@"prefs:root=MAC_POINTER&path=X", YES, @"prefs:root=General&path=MAC_POINTER/X");
        Expect(@"prefs:root=MAC_KEYBOARDS", YES, @"prefs:root=MAC_KEYBOARDS");
        Expect(@"prefs:root=MAC_POINTER_STYLE", YES, @"prefs:root=MAC_POINTER_STYLE");
        // 1.6.0: the window rows moved to the Windows & Multitasking page (MAC_WINDOWS): old links to them on the Status Bar page go there, on every version
        Expect(@"prefs:root=MAC_STATUS_BAR&path=WINDOW_ENGINE", NO, @"prefs:root=MAC_WINDOWS&path=WINDOW_ENGINE");
        Expect(@"prefs:root=MAC_STATUS_BAR#Mac%20Switcher", NO, @"prefs:root=MAC_WINDOWS#Mac%20Switcher");
        Expect(@"prefs:root=MAC_STATUS_BAR%23Enable%20Windowing", NO, @"prefs:root=MAC_WINDOWS%23Enable%20Windowing");
        Expect(@"prefs:root=MAC_STATUS_BAR#Windows%20Behind%20Full-Screen%20Apps", NO, @"prefs:root=MAC_WINDOWS#Windows%20Behind%20Full-Screen%20Apps");
        Expect(@"prefs:root=MAC_STATUS_BAR#Show%20Seconds", NO, @"prefs:root=MAC_STATUS_BAR#Show%20Seconds");
        Expect(@"prefs:root=MAC_STATUS_BAR&path=GO_APPS", NO, @"prefs:root=MAC_STATUS_BAR&path=GO_APPS");
        Expect(@"prefs:root=MAC_WINDOWS", NO, @"prefs:root=MAC_WINDOWS");
        Expect(@"prefs:root=MAC_STATUS_BAR&path=WINDOW_ENGINE", YES, @"prefs:root=General&path=MAC_WINDOWS/WINDOW_ENGINE");
        Expect(@"prefs:root=MAC_STATUS_BAR#Turn%20Off%20Traffic%20Lights", YES, @"prefs:root=General&path=MAC_WINDOWS#Turn%20Off%20Traffic%20Lights");
        Expect(@"prefs:root=MAC_STATUS_BAR%23Hide%20Multitasking%20Dots", YES, @"prefs:root=General&path=MAC_WINDOWS%23Hide%20Multitasking%20Dots");
        Expect(@"prefs:root=MAC_WINDOWS", YES, @"prefs:root=General&path=MAC_WINDOWS");
        Expect(@"prefs:root=MAC_WINDOWS&path=WINDOW_ENGINE", YES, @"prefs:root=General&path=MAC_WINDOWS/WINDOW_ENGINE");
        Expect(@"prefs:root=MAC_WINDOWSX", YES, @"prefs:root=MAC_WINDOWSX");
        Expect(@"prefs:root=MAC_STATUS_BAR#Show%20Seconds", YES, @"prefs:root=General&path=MSBD_PL_MacStatusBarPrefs#Show%20Seconds");
        // 18: anything else as it is
        Expect(@"prefs:root=General&path=About", YES, @"prefs:root=General&path=About");
        Expect(@"prefs:root=MAC_STATUS_BAR_OTHER", YES, @"prefs:root=MAC_STATUS_BAR_OTHER");
        Expect(@"prefs:root=DOCK_MAGNIFICATIONX&path=A", YES, @"prefs:root=DOCK_MAGNIFICATIONX&path=A");
        Expect(@"prefs:root=MAC_STATUS_BAR&other=1", YES, @"prefs:root=MAC_STATUS_BAR&other=1");
        Expect(@"https://example.com", YES, @"https://example.com");
        Expect(nil, YES, nil);
        // Our pages opened from SpringBoard (Take Me There, the notices, Choose Engine, Edit Go Menu…): Settings follows Open Apps as Windows on every
        // iPadOS version and engine (KT 28 Oct 2026; 1.6.0~rc3 opened them full screen on 15-17 whatever the setting) -- a window exactly when it is on
        for (int root = 0; root < 2; root++) for (int windowed = 0; windowed < 2; windowed++) for (int sm = 0; sm < 2; sm++) {
            MSBDPageOpen way = MSBDPageOpenFor(root, windowed, sm);
            BOOL link = way == MSBDPageOpenLinkAsWindow || way == MSBDPageOpenLinkFullScreen;
            checks++;
            if (MSBDPageOpenIsWindow(way) != (BOOL)windowed || link != (BOOL)root || (way == MSBDPageOpenFullScreenThenAsk) != (!root && !windowed && sm)) {
                fails++; printf("FAIL page open (SwiftUI root %d, Open Apps as Windows %d, Stage Manager %d): way %d\n", root, windowed, sm, way);
            }
        }
        // ... and the page opener's places as Settings' links on 18, through General
        NSArray *places = @[@"prefs:root=General&path=MSBD_PL_MacStatusBarPrefs", @"prefs:root=General&path=MSBD_PL_MacStatusBarPrefs/GO_APPS",
                            @"prefs:root=General&path=MAC_WINDOWS/WINDOW_ENGINE", @"prefs:root=General&path=MAC_WINDOWS"];
        for (uint32_t target = 0; target < places.count; target++) Expect(MSBDPageLink(target), YES, places[target]);
        Expect(MSBDPageLink(2), NO, @"prefs:root=MAC_WINDOWS&path=WINDOW_ENGINE");
    }
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
