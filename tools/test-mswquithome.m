// test-mswquithome.m: the Mac Switcher's Home tick (statusbar/MacSwitcherButton.h DMMSWHomeTick, the real function, cut out of the source by
// test-mswquithome.sh into hometick.inc) run tick by tick through state sequences: the view open over an app, the apps in front as SpringBoard
// reports them (nil: the Home Screen), apps quit from the view (gMSWQuitHere), the view's own Home and a desktop switch. Plain Foundation.
// 1.8.8.4 review: the view stays after a quit from it (its Home is the view's own), and closes again on a Home by another way or an app quitting
// by itself, whatever the ticks saw in between (a tick with no app in front between the quit app and the next window left the view as one opened
// over the Home Screen for good: a real Home never closed it).
#import <Foundation/Foundation.h>
#include <stdio.h>
#include "../statusbar/MSWFlick.h"
#include "../statusbar/SMWindowKey.h"

// ---- what the tick reads and calls, as stand-ins
static double gNow = 1000.0;
static double HTNow(void) { return gNow; }
#define CACurrentMediaTime() HTNow()
static int gCloses, gFocusAgain, gMarks;
static NSMutableArray<NSString *> *gLog;
static void HTLog(NSString *s) { [gLog addObject:s ?: @""]; }
#define DMLog(...) HTLog(__VA_ARGS__)
#define DM_FEATURE_MARK(name) gMarks++
@interface SBApplication : NSObject
@property (nonatomic, copy) NSString *bundleIdentifier;
@end
@implementation SBApplication
@end
@interface DMMSWTile : NSObject
@property (nonatomic, copy) NSString *bundle;
@end
@implementation DMMSWTile
@end
static BOOL gOpen, gMSWClosing, gMSWSwitching;
static double gMSWOwnHomeAt = -100;
static NSMutableSet<NSString *> *gMSWQuitHere;
static NSMutableArray<DMMSWTile *> *gMSWTiles;
static NSString *gFront;   // (the app SpringBoard has in front; nil: the Home Screen)
static SBApplication *DMFrontApp(void) { if (!gFront) return nil; SBApplication *a = [SBApplication new]; a.bundleIdentifier = gFront; return a; }
static BOOL DMMSWIsOpen(void) { return gOpen; }
static void DMMSWClose(DMMSWTile *pick, BOOL animated) { gCloses++; gOpen = NO; [gMSWQuitHere removeAllObjects]; [gMSWTiles removeAllObjects]; }
static void DMMSWFocusAgain(NSString *why) { gFocusAgain++; }

#include "hometick.inc"

static int fails = 0, n = 0;
static void check(const char *what, BOOL ok) { n++; if (!ok) { fails++; printf("FAIL  %s (closes %d, focus again %d)\n", what, gCloses, gFocusAgain); } else printf("PASS  %s\n", what); }
static void tick(void) { gNow += 0.2; DMMSWHomeTick(); }   // (the 0.2 s watcher)
static void front(NSString *b) { gFront = b; tick(); }
static void tiles(NSArray<NSString *> *keys) { [gMSWTiles removeAllObjects]; for (NSString *k in keys) { DMMSWTile *t = [DMMSWTile new]; t.bundle = k; [gMSWTiles addObject:t]; } }
// The view opens over `over` (nil: the Home Screen) with these windows in it; the tick before the open saw it closed.
static void openOver(NSString *over, NSArray<NSString *> *keys) {
    gOpen = NO; gMSWClosing = NO; gMSWSwitching = NO; gMSWOwnHomeAt = -100; gFront = over;
    gMSWQuitHere = [NSMutableSet set]; gMSWTiles = [NSMutableArray array]; gLog = [NSMutableArray array];
    gCloses = gFocusAgain = gMarks = 0;
    tick();
    tiles(keys); gOpen = YES;
    tick();
}
// A window flicked up in the view (MacSwitcher.h DMMSWFlickQuit): its thumbnails leave the view at once, its app is marked as quit from it.
static void flick(NSString *bundle) {
    NSMutableArray<DMMSWTile *> *keep = [NSMutableArray array];
    for (DMMSWTile *t in gMSWTiles) if (![DMSMKeyBundle(t.bundle) isEqualToString:bundle]) [keep addObject:t];
    gMSWTiles = keep;
    [gMSWQuitHere addObject:bundle];
}

int main(void) { @autoreleasepool {
    NSString *clock = @"com.apple.mobiletimer", *calc = @"com.apple.calculator", *tv = @"com.apple.tips";
    NSString *clockW = @"com.apple.mobiletimer|sceneID:com.apple.mobiletimer-A", *calcW = @"com.apple.calculator|sceneID:com.apple.calculator-B";

    openOver(clock, @[clockW]);
    front(nil);
    check("opened over an app, a Home by the gesture (no app in front): the view closes", gCloses == 1);

    openOver(clock, @[clockW]);
    front(clock); front(nil);
    check("opened over an app that then quits by itself: the view closes", gCloses == 1);

    openOver(calc, @[calcW]);
    flick(calc); front(calc); front(nil); front(nil); front(nil);
    check("the desktop's last window quit from the view: its Home is the view's own, the view stays and takes the keyboard focus again (once)",
          gOpen && gCloses == 0 && gFocusAgain == 1 && gMarks == 1);

    openOver(clock, @[clockW, calcW]);
    flick(clock); front(clock); front(nil); front(calc); front(calc);
    check("the front window's app quit, a tick with no app in front, then this desktop's next window in front: the view stays", gOpen && gCloses == 0);
    front(nil);
    check("... then a Home by the gesture: the view closes, as over that window (was: never closed after such a tick)", gCloses == 1);

    openOver(clock, @[clockW, calcW]);
    flick(clock); front(nil); front(calc); front(nil);
    check("the front window's app quit, a tick with no app in front, then the next window's app quits by itself: the view closes", gCloses == 1);

    openOver(clock, @[clockW, calcW]);
    flick(clock); front(clock); front(calc); front(nil);
    check("the front window's app quit, the next window in front at once, then a Home by the gesture: the view closes", gCloses == 1);

    openOver(clock, @[clockW, calcW]);
    flick(clock); flick(calc); front(clock); front(nil); front(calc); front(nil); front(nil);
    check("both windows flicked fast, a tick with no app in front between their quits: the view stays and takes the focus again after each Home",
          gOpen && gCloses == 0 && gFocusAgain == 2);

    openOver(clock, @[clockW]);
    flick(clock); front(nil); front(tv); front(tv); front(nil); front(nil);
    check("the last window quit, then an app that is no window of this view in front for a moment (another display's): the view stays", gOpen && gCloses == 0);

    openOver(clock, @[clockW, calcW]);
    flick(calc); front(clock); front(clock); front(nil);
    check("a window behind quit from the view, then the app in front goes Home by the gesture: the view closes", gCloses == 1);

    openOver(clock, @[clockW]);
    gMSWOwnHomeAt = gNow; front(nil); front(nil);
    check("the view's own Home (a full-screen app sent to another desktop): the view stays", gOpen && gCloses == 0);

    openOver(clock, @[clockW]);
    gMSWSwitching = YES; front(nil); front(nil);
    check("a desktop switch under way: the view stays", gOpen && gCloses == 0);

    openOver(nil, @[clockW]);
    front(nil); front(nil);
    check("opened over the Home Screen (Aerial, Zetsu, MilkyWay4 windows): no Home closes it", gOpen && gCloses == 0);

    printf("test-mswquithome (the Home tick): %d pass, %d fail\n", n - fails, fails);
    return fails ? 1 : 0;
} }
