// test-docklevelowner.m -- see test-docklevelowner.sh. One owner for the Dock window's level (1.8.8.2): the real code cut out of
// statusbar/Desktop.h (DMDesktopDockUnder, MSBDDockLevelAfterKeyboard, DMKeyboardForTheDock) and the Downloads panel's restore lines out of
// dock/Downloads.m (-restoreHostWindowIfIdle's level part), run on the Mac (Mac Catalyst, headless) with stand-ins of SpringBoard's windows:
//  - Rename from the stack's item menu: the panel raised the Dock to 1036, our keyboard rule took it to -3, the panel closes, the keyboard goes:
//    the Dock stays under the keyboard until it goes, then back at the panel's saved 25 (before: 25 at the panel's close, over the keyboard);
//  - the panel closing with nothing of ours holding the Dock: its saved level at once, as before; another Dock window (the TV's) than the one
//    held: its own level at once; the keyboard going before the panel closes: the panel's level back, then the saved one;
//  - the keyboard is the Dock's own (the panel's search field, the Dock's window key): the rule's question says so; not for another key window.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static NSMutableArray<NSString *> *gLog;
static void DMLog(NSString *s) { if (!gLog) gLog = [NSMutableArray array]; [gLog addObject:s]; }
static BOOL DMTestFlag(const char *path) { (void)path; return NO; }
static NSArray<UIWindow *> *gWindows;
static NSArray<UIWindow *> *DMAllWindows(void) { return gWindows; }
static BOOL gKey[8];
@interface SBFloatingDockWindow : UIWindow
@property (nonatomic) int tag2;
@end
@implementation SBFloatingDockWindow
- (BOOL)isKeyWindow { return gKey[self.tag2]; }
@end
@interface TOtherWindow : UIWindow
@property (nonatomic) int tag2;
@end
@implementation TOtherWindow
- (BOOL)isKeyWindow { return gKey[self.tag2]; }
@end
#include "dl-desk.inc"    // (Desktop.h: the reasons, DMDesktopDockIsUnder, DMDesktopDockUnder, MSBDDockLevelAfterKeyboard, DMKeyboardForTheDock)
@interface TPanel : NSObject   // (the Downloads panel's two properties the restore lines read)
@property (nonatomic, strong) UIWindow *hostWindow;
@property (nonatomic) CGFloat savedLevel;
@end
@implementation TPanel
- (void)restoreLevel {
#include "dl-restore.inc"   // (dock/Downloads.m -restoreHostWindowIfIdle: its level lines)
}
@end

static int gFails, gChecks;
static void Check(BOOL ok, NSString *what) { gChecks++; if (!ok) gFails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }

int main(int argc, char **argv) {
    @autoreleasepool {
        (void)argc; (void)argv;
        SBFloatingDockWindow *dock = [[SBFloatingDockWindow alloc] initWithFrame:CGRectMake(0, 0, 768, 1024)]; dock.tag2 = 1;
        SBFloatingDockWindow *tv = [[SBFloatingDockWindow alloc] initWithFrame:CGRectMake(0, 0, 1920, 1080)]; tv.tag2 = 2;
        TOtherWindow *layer = [[TOtherWindow alloc] initWithFrame:CGRectMake(0, 0, 768, 1024)]; layer.tag2 = 3;
        dock.hidden = NO; tv.hidden = NO; layer.hidden = NO;
        gWindows = @[layer, dock, tv];
        TPanel *panel = [TPanel new];
        Check(dlsym(RTLD_DEFAULT, "MSBDDockLevelAfterKeyboard") != NULL, @"the panel finds the keyboard rule's hand-over by name (dlsym, as dock/Downloads.m does)");

        // Rename from the stack's item menu: the panel raised the Dock, the rename's keyboard took it under, the panel closes, the keyboard goes
        dock.windowLevel = 1036; tv.windowLevel = 25; panel.hostWindow = dock; panel.savedLevel = 25;
        DMDesktopDockUnder(@"keyboard", YES, -3.0);
        BOOL under = fabs(dock.windowLevel + 3.0) < 0.01;
        [panel restoreLevel];
        BOOL stays = fabs(dock.windowLevel + 3.0) < 0.01;
        DMDesktopDockUnder(@"keyboard", NO, -3.0);
        Check(under && stays && fabs(dock.windowLevel - 25.0) < 0.01,
              [NSString stringWithFormat:@"Rename from the stack: the keyboard rule's -3 kept when the panel closes (the Dock stays under the keyboard), the panel's saved 25 when the keyboard goes (now %.0f)", dock.windowLevel]);
        BOOL said = NO; for (NSString *l in gLog) if ([l containsString:@"the Downloads panel closed while the Dock is under the Home Screen (keyboard): it stays at -3, back to 25 (not 1036)"]) said = YES;
        Check(said, @"  ... its line says so");

        // nothing of ours holds the Dock: the panel's saved level at once, as before
        dock.windowLevel = 1036; panel.savedLevel = 25; [panel restoreLevel];
        Check(fabs(dock.windowLevel - 25.0) < 0.01, @"the panel closing with nothing of ours holding the Dock: its saved level at once (as before)");

        // the TV's Dock is the panel's, the iPad's is held: the TV's set at once, the iPad's untouched
        dock.windowLevel = 25; tv.windowLevel = 1036; panel.hostWindow = tv; panel.savedLevel = 25;
        gWindows = @[layer, dock, tv];
        DMDesktopDockUnder(@"keyboard", YES, -3.0);
        BOOL heldIpad = fabs(dock.windowLevel + 3.0) < 0.01;
        [panel restoreLevel];
        BOOL tvOwn = fabs(tv.windowLevel - 25.0) < 0.01 && fabs(dock.windowLevel + 3.0) < 0.01;
        DMDesktopDockUnder(@"keyboard", NO, -3.0);
        Check(heldIpad && tvOwn && fabs(dock.windowLevel - 25.0) < 0.01, @"the panel of another Dock window (the TV's) than the one held: its own level at once; the held one back when the keyboard goes");

        // the keyboard goes while the panel is still open, then the panel closes
        dock.windowLevel = 1036; tv.windowLevel = 25; panel.hostWindow = dock; panel.savedLevel = 25;
        gWindows = @[layer, dock, tv];
        DMDesktopDockUnder(@"keyboard", YES, -3.0);
        DMDesktopDockUnder(@"keyboard", NO, -3.0);
        BOOL panelLevel = fabs(dock.windowLevel - 1036.0) < 0.01;
        [panel restoreLevel];
        Check(panelLevel && fabs(dock.windowLevel - 25.0) < 0.01, @"the keyboard gone before the panel closes: the panel's level back while it is open (1036), its saved one when it closes");

        // a desktop menu and the keyboard both hold it: the panel's level kept for when the last one goes
        dock.windowLevel = 1036; panel.savedLevel = 25;
        DMDesktopDockUnder(@"menu", YES, -3.0); DMDesktopDockUnder(@"keyboard", YES, -3.0);
        [panel restoreLevel];
        DMDesktopDockUnder(@"keyboard", NO, -3.0);
        BOOL stillUnder = fabs(dock.windowLevel + 3.0) < 0.01;
        DMDesktopDockUnder(@"menu", NO, -3.0);
        Check(stillUnder && fabs(dock.windowLevel - 25.0) < 0.01, @"two reasons hold it: under until the last goes, then the panel's saved level");

        // whose keyboard: the Dock's own window key (the panel's search field) or another window
        memset(gKey, 0, sizeof gKey); gKey[1] = YES;
        BOOL dockKey = DMKeyboardForTheDock();
        memset(gKey, 0, sizeof gKey); gKey[3] = YES;
        BOOL layerKey = DMKeyboardForTheDock();
        memset(gKey, 0, sizeof gKey); gKey[1] = YES; dock.hidden = YES;
        BOOL hiddenKey = DMKeyboardForTheDock();
        dock.hidden = NO; memset(gKey, 0, sizeof gKey);
        Check(dockKey && !layerKey && !hiddenKey && !DMKeyboardForTheDock(),
              @"the keyboard is the Dock's own when its window is the key window (the panel's search field); not for our layer's or the typing window's field, nor a hidden Dock window");
        printf("test-docklevelowner: %d checks, %d fail\n", gChecks, gFails);
        return gFails ? 1 : 0;
    }
}
