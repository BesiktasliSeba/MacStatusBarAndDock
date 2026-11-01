// DMIconTheme.h -- the Dock's items as app icons an icon theme can change (1.7.5 item 7): what FinderIcon.m, Launchpad.m, Downloads.m and
// TrashIcon.m call (IconTheme.m, over common/IconTheme.h). Each view registers its item's own drawing once, then shows DMIconThemePicture at its
// size; nil = the path is off here (iPadOS 18, SpringBoard's classes not as read): the view draws its picture itself, as before.
#import <UIKit/UIKit.h>
#import "../common/IconThemeIDs.h"
typedef UIImage *(^DMIconDrawer)(CGSize size, CGFloat scale, CGFloat radius, BOOL masked);
void DMIconThemeSetDrawer(MSBDIconItem item, DMIconDrawer drawer);
// The item's picture at that size, with the screen's scale and SpringBoard's Dock corner (themed: a theme's picture, not ours shaped by an engine).
UIImage *DMIconThemePicture(MSBDIconItem item, CGSize size, BOOL *themed);
BOOL DMIconThemeOn(void);
// Bumped (and DMIconThemeChangedNotification posted) when a theme engine refreshed its icons: ask again.
NSUInteger DMIconThemeGeneration(void);
extern NSString *const DMIconThemeChangedNotification;
