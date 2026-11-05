// MSBDMacTileModule.h -- our Mac tiles on iPadOS 18 as Control Center's own modules (1.8.1 item 1, plans/cc18tiles-1.8.1.md): each bundle (MacConnectivity,
// MacDisplay, MacSound, MacNowPlaying; one small .m each: MSBD_MAC_TILE_CLASS, MSBD_MAC_TILE_ROLE, MSBD_MAC_TILE_SIZES) is only this class. The tile, its
// state and its pages are the status bar part's (statusbar/CC18Tiles.h), found with dlsym; without that part the module shows nothing.
#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include "../common/CCModuleList.h"
// (Control Center's own protocol, declared here by name as in MSBDRAMCPUModule.m: its loader takes only a class that adopts it -- without it the tile stays a blank placeholder)
@protocol CCUIContentModule <NSObject>
@optional
- (UIViewController *)contentViewController;
- (void)setContentModuleContext:(id)context;
@end
@interface MSBD_MAC_TILE_CLASS : NSObject <CCUIContentModule>
@end
@implementation MSBD_MAC_TILE_CLASS {
    UIViewController *_content;
    id _context;   // (held, as RAM & CPU's: Control Center keeps no other hold on it)
}
- (UIViewController *)contentViewController {
    if (_content) return _content;
    UIViewController *(*make)(int) = (UIViewController *(*)(int))dlsym(RTLD_DEFAULT, kMSBDCCMacTileHostFn);
    _content = make ? make(MSBD_MAC_TILE_ROLE) : nil;
    if (!_content) _content = [UIViewController new];
    return _content;
}
- (void)setContentModuleContext:(id)context { _context = context; }
- (unsigned long long)supportedGridSizeClasses { return MSBD_MAC_TILE_SIZES; }
- (BOOL)expandsGridSizeClassesForAccessibility { return NO; }
@end
