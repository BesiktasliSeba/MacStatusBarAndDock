// IconThemeIDs.h -- the Dock's own items as icons an icon theme can change, like any app's (1.7.5 item 7, KT 31 Oct: "fully compatible with
// SnowBoard theming like any icon is"). Foundation only: the rules both libraries share, run as they are by the Mac test (tools/test-icontheme.sh).
// Each item is an icon of SpringBoard's own app icon class with a bundle identifier of its own (common/IconTheme.h): a theme names its picture by
// that identifier (IconBundles/<id>-large.png), and SnowBoard's whole chain applies to it -- theme order, masks, corner radius, effects, per-app
// choices, refresh. These identifiers are public (README: for theme makers) and never change.
#pragma once
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MSBDIconItem) {
    MSBDIconFinder = 0,           // Finder, the Dock's first item
    MSBDIconLaunchpad,            // Launchpad (the App Library icon drawn as Launchpad): the grid style
    MSBDIconLaunchpadClassic,     // Launchpad in the classic round style
    MSBDIconDownloads,            // the Downloads stack: its folder
    MSBDIconTrashEmpty,           // the Trash, empty
    MSBDIconTrashFull,            // the Trash with something in it
    MSBDIconActivityMonitor,      // Activity Monitor (App Library, its search, the Dock)
    MSBDIconItemCount
};

// The identifier a theme names the item's picture by; also the icon's bundle identifier in SpringBoard.
static inline NSString *MSBDIconID(MSBDIconItem item) {
    switch (item) {
        case MSBDIconFinder:           return @"com.besiktasliseba.finder";
        case MSBDIconLaunchpad:        return @"com.besiktasliseba.macstatusbar.launchpad";
        case MSBDIconLaunchpadClassic: return @"com.besiktasliseba.macstatusbar.launchpad.classic";
        case MSBDIconDownloads:        return @"com.besiktasliseba.macstatusbar.downloads";
        case MSBDIconTrashEmpty:       return @"com.besiktasliseba.macstatusbar.trash";
        case MSBDIconTrashFull:        return @"com.besiktasliseba.macstatusbar.trash.full";
        case MSBDIconActivityMonitor:  return @"com.besiktasliseba.macstatusbar.activitymonitor";   // (since 1.7.2: never renamed)
        default:                       return nil;
    }
}

// The identifiers asked for an item's picture, in order: the first one a theme has a picture for wins; none -> the first one's own (our drawing,
// as the theme engine shapes an app's own icon). Finder still answers to com.apple.finder (published in 1.2: "com.apple.finder or
// com.besiktasliseba.finder"); the classic Launchpad to the plain Launchpad picture, so one theme picture serves both styles. The full Trash has
// no fallback: a theme's empty bin must never stand for a full Trash.
static inline NSArray<NSString *> *MSBDIconLookup(MSBDIconItem item) {
    switch (item) {
        case MSBDIconFinder:           return @[MSBDIconID(MSBDIconFinder), @"com.apple.finder"];
        case MSBDIconLaunchpadClassic: return @[MSBDIconID(MSBDIconLaunchpadClassic), MSBDIconID(MSBDIconLaunchpad)];
        default:                       { NSString *i = MSBDIconID(item); return i ? @[i] : @[]; }
    }
}

// Which item an identifier of the lookup draws by default (an alias draws its item's own picture).
static inline MSBDIconItem MSBDIconItemForID(NSString *ident) {
    if ([ident isEqualToString:@"com.apple.finder"]) return MSBDIconFinder;
    for (NSInteger i = 0; i < MSBDIconItemCount; i++) if ([MSBDIconID((MSBDIconItem)i) isEqualToString:ident]) return (MSBDIconItem)i;
    return MSBDIconItemCount;
}

// The Trash's look -> its item (the Eject sign during a drag of drives stays our drawing: it is not the Trash's picture).
static inline MSBDIconItem MSBDIconTrashItem(BOOL full) { return full ? MSBDIconTrashFull : MSBDIconTrashEmpty; }
static inline MSBDIconItem MSBDIconLaunchpadItem(BOOL classic) { return classic ? MSBDIconLaunchpadClassic : MSBDIconLaunchpad; }

// The item's name (the icon's display name: labels, VoiceOver, a theme engine's lists).
static inline NSString *MSBDIconName(MSBDIconItem item) {
    switch (item) {
        case MSBDIconFinder:           return @"Finder";
        case MSBDIconLaunchpad:
        case MSBDIconLaunchpadClassic: return @"Launchpad";
        case MSBDIconDownloads:        return @"Downloads";
        case MSBDIconTrashEmpty:
        case MSBDIconTrashFull:        return @"Trash";
        case MSBDIconActivityMonitor:  return @"Activity Monitor";
        default:                       return nil;
    }
}

// Whether the item's own picture leaves part of its square transparent (the bin, the round rocket): its unmasked picture then marks its canvas
// (MSBDIconCanvasMarks), as a theme engine crops a picture's transparent margins before masking it (SnowBoard: +croppedInsetsForImage:) and would
// otherwise blow the drawing up to the tile's size. Tiles fill their square: nothing to mark.
static inline BOOL MSBDIconHasMargins(MSBDIconItem item) {
    return item == MSBDIconTrashEmpty || item == MSBDIconTrashFull || item == MSBDIconLaunchpadClassic;
}
// The two marks, in pixels of a w x h bitmap: one pixel in the top-left and one in the bottom-right corner, alpha 1/255 (invisible; a mask cuts
// those corners anyway). Any alpha > 0 in a first or last row / column keeps that side's crop at zero.
typedef struct { int x0, y0, x1, y1; } MSBDCanvasMarks;
static inline MSBDCanvasMarks MSBDIconCanvasMarks(int w, int h) {
    MSBDCanvasMarks m = { 0, 0, w > 0 ? w - 1 : 0, h > 0 ? h - 1 : 0 };
    return m;
}
// The crop SnowBoard's rule gives an alpha bitmap (first / last rows and columns with any alpha > 0): what the marks must keep at zero. For the Mac
// test; insets as {top, left, bottom, right}.
typedef struct { int top, left, bottom, right; } MSBDAlphaInsets;
static inline MSBDAlphaInsets MSBDIconAlphaInsets(const unsigned char *alpha, int w, int h) {
    MSBDAlphaInsets in = { 0, 0, 0, 0 };
    if (!alpha || w <= 0 || h <= 0) return in;
    int top = -1, bottom = -1, left = -1, right = -1;
    for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) if (alpha[y * w + x]) {
        if (top < 0) top = y;
        bottom = y;
        if (left < 0 || x < left) left = x;
        if (x > right) right = x;
    }
    if (top < 0) return in;   // (nothing drawn: nothing to crop)
    in.top = top; in.left = left; in.bottom = h - 1 - bottom; in.right = w - 1 - right;
    return in;
}

// "Ours or the theme's" for one request (MSBDIconThemePicture): our data source drew during it, or the engine handed back a picture it made from
// ours before (its own cache) -> ours; anything else came from a theme (its picture, a per-app choice). The first themed identifier in the lookup
// wins; none themed -> the first identifier's (our picture as the engine shaped it).
static inline NSUInteger MSBDIconPick(const BOOL *themed, NSUInteger n) {
    for (NSUInteger i = 0; i < n; i++) if (themed[i]) return i;
    return 0;
}

// The shapes SpringBoard's icon classes must have for the path (read on 15.6.1 / 16.7.7 / 17.5.1: SBIconImageInfo = {CGSize size; double scale;
// double continuousCornerRadius}): method type strings without their offsets (digits dropped), as the runtime reports them.
#define kMSBDIconImageInfoType "{SBIconImageInfo={CGSize=dd}dd}"
static inline NSString *MSBDIconBareTypes(const char *enc) {
    if (!enc) return nil;
    NSMutableString *s = [NSMutableString string];
    for (const char *p = enc; *p; p++) if (*p < '0' || *p > '9') [s appendFormat:@"%c", *p];
    return s;
}
static inline BOOL MSBDIconTypesAre(const char *enc, NSString *want) { NSString *b = MSBDIconBareTypes(enc); return b && [b isEqualToString:want]; }
// The image methods (-iconImageWithInfo:, -generateIconImageWithInfo:, -unmaskedIconImageWithInfo:) and the data source's
// (-icon:imageWithInfo:, -icon:unmaskedImageWithInfo:).
static inline NSString *MSBDIconImageMethodTypes(void) { return @"@@:" kMSBDIconImageInfoType; }
static inline NSString *MSBDIconSourceMethodTypes(void) { return @"@@:@" kMSBDIconImageInfoType; }

// The iPadOS versions the path runs on: 15 to 17, where SnowBoard themes (KT 1 Nov: on 18 our own pictures stay, nothing changes there).
static inline BOOL MSBDIconThemeOS(NSInteger major) { return major >= 15 && major <= 17; }

// Darwin notifications after which a theme engine's pictures may differ (its themes, their order, a per-app choice, the light / dark set):
// SnowBoard posts this one when its refresh is done.
#define kMSBDIconThemeSnowBoardRefreshed "com.spark.snowboard.refreshComplete"
