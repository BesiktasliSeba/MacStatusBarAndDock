// DesktopWallpaper.h -- Settings > Desktop > Desktop Picture (1.8.6, KT 9-10 Nov): the rules shared by SpringBoard (statusbar/DesktopWallpaper.h) and
// Settings (statusbar/macstatusbarprefs/MSBWallpaperController.m). Foundation only, tested on the Mac (tools/test-desktopwallpaper.sh).
//  - One picture behind the Home Screen's FIRST page (where the desktop is); the other pages, the App Library and the Lock Screen keep iPadOS's own.
//    Unset ("None", the default): nothing of ours is drawn and nothing changes.
//  - The choice is three preference values of our domain: the gallery's id (for its tick), the light picture's path and, where the picture has one, the
//    dark one's (followed with the iPad's Light / Dark appearance). SpringBoard reads only the paths, and only from the three places below.
//  - Never Apple's wallpaper store: iPadOS's own pictures are READ from /Library/Wallpaper, never copied, never written; KT's own wallpaper stays as it is.
//  - Sources: Mac Wallpapers, the pictures the user puts in On My iPad > MacStatusBar&Dock > Wallpapers (from a Mac by AirDrop and the Files app,
//    or with Add from Files: we ship none -- Apple's macOS pictures are Apple's); iPadOS's still wallpapers on this iPad (found at run time:
//    MSBDWallpaperStill); one picture from Photos (a copy, made smaller, beside our files in the preferences folder).
#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

#define kMSBDWallpaperIDKey     "desktopWallpaper"          // (the gallery's id: "mac:<file>", "ios:<light path>", "photo"; absent = None)
#define kMSBDWallpaperPathKey   "desktopWallpaperPath"      // (the picture SpringBoard shows; absent = None)
#define kMSBDWallpaperDarkKey   "desktopWallpaperDarkPath"  // (the same picture for Dark appearance, when it has one)
#define kMSBDWallpaperNotify    "com.besiktasliseba.macstatusbar.wallpaper"
#define kMSBDWallpaperMacSub    @"MacStatusBar&Dock/Wallpapers"                                // (in On My iPad: the Mac Wallpapers folder, the user's)
#define kMSBDWallpaperSystemDir @"/Library/Wallpaper"                                          // (iPadOS's own, read only)
#define kMSBDWallpaperPhotoDir  @"/var/jb/var/mobile/Library/Preferences"                     // (the copy of the picture from Photos, beside our other files there)
#define kMSBDWallpaperPhotoPrefix @"MacStatusBarAndDock-DesktopPicture-"                       // (+ the time it was picked + .jpg: a new name per pick)

// On My iPad: the Files app's own storage, the app group group.com.apple.FileProvider.LocalStorage (its container's metadata names it; the same
// place Finder's On My iPad is, statusbar/Finder.h DMFinderOnMyIPad). nil where it isn't there.
// Looked up when first needed and kept once found; not found (the containers not readable yet, early after a boot) is tried again after 30 s,
// never kept for good (review 1.8.6 L7).
static inline NSString *MSBDWallpaperOnMyIPad(void) {
    static NSString *found; static CFAbsoluteTime triedAt;
    if (found) return found;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (triedAt > 0 && now - triedAt < 30.0) return nil;
    triedAt = now;
    NSString *root = @"/var/mobile/Containers/Shared/AppGroup";
    for (NSString *uuid in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:root error:nil]) {
        NSString *dir = [root stringByAppendingPathComponent:uuid];
        NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:[dir stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"]];
        if ([meta[@"MCMMetadataIdentifier"] isEqual:@"group.com.apple.FileProvider.LocalStorage"]) { found = [dir stringByAppendingPathComponent:@"File Provider Storage"]; break; }
    }
    return found;
}
// The Mac Wallpapers folder (On My iPad > MacStatusBar&Dock > Wallpapers), or nil.
static inline NSString *MSBDWallpaperMacDir(void) { NSString *m = MSBDWallpaperOnMyIPad(); return m ? [m stringByAppendingPathComponent:kMSBDWallpaperMacSub] : nil; }

static inline BOOL MSBDWallpaperIsPictureFile(NSString *p) { return [@[@"jpg", @"jpeg", @"png", @"heic"] containsObject:p.pathExtension.lowercaseString]; }
// A path SpringBoard may show: a picture file in one of the three places (macDir: the Mac Wallpapers folder, directly in it), no way out of them
// (a ".." or "." component is refused).
static inline BOOL MSBDWallpaperPathAllowedIn(NSString *p, NSString *macDir) {
    if (![p isKindOfClass:[NSString class]] || !p.length || ![p isAbsolutePath]) return NO;
    for (NSString *c in p.pathComponents) if ([c isEqualToString:@".."] || [c isEqualToString:@"."]) return NO;
    if (!MSBDWallpaperIsPictureFile(p)) return NO;
    if ([p hasPrefix:[kMSBDWallpaperSystemDir stringByAppendingString:@"/"]]) return YES;
    if ([p.stringByDeletingLastPathComponent isEqualToString:kMSBDWallpaperPhotoDir]) return [p.lastPathComponent hasPrefix:kMSBDWallpaperPhotoPrefix];
    if (macDir.length && [p.stringByDeletingLastPathComponent isEqualToString:macDir]) return ![p.lastPathComponent hasPrefix:@"."];
    return NO;
}
// (the Mac Wallpapers folder is looked up only for a path that could be in it: nothing at all for None, iPadOS's own or the Photos copy -- L7)
static inline BOOL MSBDWallpaperPathAllowed(NSString *p) {
    if (![p isKindOfClass:[NSString class]] || !p.length || ![p isAbsolutePath]) return NO;
    if ([p hasPrefix:[kMSBDWallpaperSystemDir stringByAppendingString:@"/"]] || [p.stringByDeletingLastPathComponent isEqualToString:kMSBDWallpaperPhotoDir]) return MSBDWallpaperPathAllowedIn(p, nil);
    return MSBDWallpaperPathAllowedIn(p, MSBDWallpaperMacDir());
}

// The part of a picture shown on a screen of the given size: the whole screen covered, the picture's centre kept, nothing stretched (as a Mac's
// "Fill Screen"). In the picture's pixels. A picture or a screen with no size: the whole picture.
static inline CGRect MSBDWallpaperFillRect(double iw, double ih, double sw, double sh) {
    if (iw <= 0 || ih <= 0 || sw <= 0 || sh <= 0) return CGRectMake(0, 0, iw > 0 ? iw : 0, ih > 0 ? ih : 0);
    double s = MAX(sw / iw, sh / ih);   // (the picture scaled so both sides reach the screen's)
    double cw = MIN(iw, sw / s), ch = MIN(ih, sh / s);
    return CGRectMake(floor((iw - cw) / 2.0), floor((ih - ch) / 2.0), round(cw), round(ch));
}
// iPadOS's own stills are made to be turned (17.5.1, the Flat packages' main.caml, 10 Nov): a square picture (3416 px) drawn at its own pixels
// around the screen's centre, the screen's corners just inside a circle -- the picture's corners are black and never shown (12.9-inch: a 3414 px
// diagonal in the 3416 px circle). Such a picture shows the largest rectangle of the screen's shape that fits in that circle, centred; seen with
// "Fill Screen" its black corners showed (w01 on the 17.5). Which: a square picture of iPadOS's own folder whose side reaches the screen's diagonal
// (sw, sh: the screen's pixels; review 1.8.6 L3: a square only as large as the screen's long side is an ordinary picture, shown Fill Screen -- the
// circle rule would zoom it by a quarter). With no screen size given: any square there. In the picture's pixels.
static inline BOOL MSBDWallpaperIsTurnable(NSString *path, double iw, double ih, double sw, double sh) {
    if (![path hasPrefix:[kMSBDWallpaperSystemDir stringByAppendingString:@"/"]] || iw <= 0 || fabs(iw - ih) >= 1.0) return NO;
    return sw <= 0 || sh <= 0 || iw >= 0.97 * hypot(sw, sh);
}
static inline CGRect MSBDWallpaperCircleRect(double side, double sw, double sh) {
    if (side <= 0 || sw <= 0 || sh <= 0) return CGRectMake(0, 0, side > 0 ? side : 0, side > 0 ? side : 0);
    double f = side / hypot(sw, sh), w = round(sw * f), h = round(sh * f);
    return CGRectMake(floor((side - w) / 2.0), floor((side - h) / 2.0), w, h);
}
// The part of the picture a screen shows, for either kind.
static inline CGRect MSBDWallpaperPart(NSString *path, double iw, double ih, double sw, double sh) {
    return MSBDWallpaperIsTurnable(path, iw, ih, sw, sh) ? MSBDWallpaperCircleRect(iw, sw, sh) : MSBDWallpaperFillRect(iw, ih, sw, sh);
}
// The pixel size a picture is decoded at for a screen: the screen's own pixels, never more than the part shown has.
static inline CGSize MSBDWallpaperDecodeSize(CGRect part, double spw, double sph) {
    if (part.size.width <= 0 || part.size.height <= 0 || spw <= 0 || sph <= 0) return CGSizeZero;
    double s = MIN(1.0, MAX(spw / part.size.width, sph / part.size.height));   // (the part has the screen's shape: one factor fits both sides)
    return CGSizeMake(round(part.size.width * s), round(part.size.height * s));
}

// ---- iPadOS's own wallpapers, as stills -------------------------------------------------------------------------------------------------------
// iPadOS 17 (17.5.1, read 10 Nov): /Library/Wallpaper/Collections/<collection>.wallpaperCollection/Wallpapers/<n>.<name>[-<w>w-<h>h@2x][~ipad].wallpaper,
// each with its pictures as HEIC files in a Core Animation package (<...>.ca/assets/). A still is a wallpaper whose pictures are ONE picture, or one
// picture in a light and a dark version (iPadOS_17_Flat: J120.HEIC + J120-Dark.HEIC). Layered ones (Lake, iPadOS 17: sky, mountains, floating shapes
// put together live) and drawn ones (Bokeh, Stripe: no picture at all, made by code) are not stills and are left out: shown as one of their layers
// they would not be the wallpaper Apple made. Masks and thumbnails are not pictures of the wallpaper.
// Each wallpaper is offered once: of the same wallpaper in several screen sizes, the one made for this screen's points (or the largest).
typedef struct { NSString *__unsafe_unretained light, *__unsafe_unretained dark; } MSBDWallpaperPair;
static inline BOOL MSBDWallpaperIsPicture(NSString *file) {
    NSString *ext = file.pathExtension.lowercaseString, *n = file.lastPathComponent.stringByDeletingPathExtension.lowercaseString;
    if (![@[@"heic", @"png", @"jpg", @"jpeg"] containsObject:ext]) return NO;
    return [n rangeOfString:@"mask"].location == NSNotFound && [n rangeOfString:@"thumb"].location == NSNotFound && [n rangeOfString:@"preview"].location == NSNotFound;
}
// The name without its appearance: "J120-Dark" -> "J120", "Red Light" -> "Red"; *isDark says which it was.
static inline NSString *MSBDWallpaperBaseName(NSString *file, BOOL *isDark, BOOL *isLight) {
    NSString *n = file.lastPathComponent.stringByDeletingPathExtension;
    if (isDark) *isDark = NO; if (isLight) *isLight = NO;
    for (NSString *suf in @[@"-Dark", @" Dark", @"_Dark", @"-dark"]) if ([n hasSuffix:suf]) { if (isDark) *isDark = YES; return [n substringToIndex:n.length - suf.length]; }
    for (NSString *suf in @[@"-Light", @" Light", @"_Light", @"-light"]) if ([n hasSuffix:suf]) { if (isLight) *isLight = YES; return [n substringToIndex:n.length - suf.length]; }
    return n;
}
// The still among one wallpaper's files (full paths): light and dark (dark nil when it has none), or both nil when it is not a still.
static inline NSArray<NSString *> *MSBDWallpaperStill(NSArray<NSString *> *files) {
    NSMutableArray *pics = [NSMutableArray array];
    for (NSString *f in files) if (MSBDWallpaperIsPicture(f)) [pics addObject:f];
    if (pics.count == 1) return @[pics[0]];
    if (pics.count != 2) return nil;
    BOOL d0, l0, d1, l1;
    NSString *b0 = MSBDWallpaperBaseName(pics[0], &d0, &l0), *b1 = MSBDWallpaperBaseName(pics[1], &d1, &l1);
    if (![b0 isEqualToString:b1] || d0 == d1) return nil;   // (two different pictures: layers)
    return d0 ? @[pics[1], pics[0]] : @[pics[0], pics[1]];
}
// iPadOS 15/16 (16.7.7, read 10 Nov on the iPad 2): /Library/Wallpaper/Stills/iPad/<id>.<name>-<w>w-<h>h@2x~ipad.wallpaper/ with a Wallpaper.plist that
// names the pictures: assets > lockAndHome (or home) > default / dark > fullSizeImageFileName, the wallpaper's "name", "offloaded" when iPadOS keeps
// only the thumbnails on the iPad (the full picture comes from Apple when chosen in Settings: WWDC 2021, the Desert and Lake sets there). The file
// names carry the id and the screen size ("7411.WWDC_2022_Light-768w-1024h@2x~ipad.heic"), so the light/dark pair is the plist's, not guessed from
// names. present: the bundle's file names. Returns light [, dark] as full paths, or nil (offloaded, or not described as stills).
static inline NSArray<NSString *> *MSBDWallpaperStillFromInfo(NSDictionary *info, NSString *dir, NSArray<NSString *> *present) {
    if (![info isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *assets = [info[@"assets"] isKindOfClass:[NSDictionary class]] ? info[@"assets"] : nil;
    NSDictionary *set = [assets[@"lockAndHome"] isKindOfClass:[NSDictionary class]] ? assets[@"lockAndHome"] : ([assets[@"home"] isKindOfClass:[NSDictionary class]] ? assets[@"home"] : nil);
    NSString *(^file)(NSString *) = ^NSString *(NSString *k) {
        NSDictionary *a = [set[k] isKindOfClass:[NSDictionary class]] ? set[k] : nil;
        NSString *f = [a[@"fullSizeImageFileName"] isKindOfClass:[NSString class]] ? a[@"fullSizeImageFileName"] : nil;
        if (a[@"representedType"] && ![a[@"representedType"] isEqual:@"Still"]) return nil;
        return (f.length && ![f containsString:@"/"] && MSBDWallpaperIsPicture(f) && [present containsObject:f]) ? [dir stringByAppendingPathComponent:f] : nil;
    };
    NSString *light = file(@"default");
    if (!light) return nil;
    NSString *dark = file(@"dark");
    return dark ? @[light, dark] : @[light];
}

// A wallpaper's name as Settings shows it: "7570.iPadOS_17_Flat-1024w-1366h@2x~ipad.wallpaper" -> "iPadOS 17"; "7560.Lake_Flat-..." -> "Lake".
// (The "Flat" ones are the still forms of the layered wallpapers of the same name: the word is dropped.)
static inline NSString *MSBDWallpaperDisplayName(NSString *bundle) {
    NSString *n = bundle.lastPathComponent.stringByDeletingPathExtension;
    NSRange dot = [n rangeOfString:@"."];
    if (dot.location != NSNotFound && dot.location > 0 && [[n substringToIndex:dot.location] rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound)
        n = [n substringFromIndex:dot.location + 1];
    NSRange tilde = [n rangeOfString:@"~"]; if (tilde.location != NSNotFound) n = [n substringToIndex:tilde.location];
    NSRegularExpression *size = [NSRegularExpression regularExpressionWithPattern:@"-[0-9]+w-[0-9]+h(@[0-9]x)?$" options:0 error:nil];
    n = [size stringByReplacingMatchesInString:n options:0 range:NSMakeRange(0, n.length) withTemplate:@""];
    n = [n stringByReplacingOccurrencesOfString:@"_" withString:@" "];
    for (NSString *suf in @[@" Flat", @" flat"]) if ([n hasSuffix:suf]) n = [n substringToIndex:n.length - suf.length];
    return [n stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}
// The screen size a wallpaper bundle was made for, in points ("-1024w-1366h"), or zero.
static inline CGSize MSBDWallpaperMadeFor(NSString *bundle) {
    NSRegularExpression *size = [NSRegularExpression regularExpressionWithPattern:@"-([0-9]+)w-([0-9]+)h" options:0 error:nil];
    NSString *n = bundle.lastPathComponent;
    NSTextCheckingResult *m = [size firstMatchInString:n options:0 range:NSMakeRange(0, n.length)];
    if (!m) return CGSizeZero;
    return CGSizeMake([[n substringWithRange:[m rangeAtIndex:1]] doubleValue], [[n substringWithRange:[m rangeAtIndex:2]] doubleValue]);
}
// Of the same wallpaper in several sizes, which bundle to offer for a screen of these points (portrait w x h): the one made for it, else the largest.
static inline BOOL MSBDWallpaperBetterFit(NSString *candidate, NSString *current, double sw, double sh) {
    if (!current) return YES;
    CGSize a = MSBDWallpaperMadeFor(candidate), b = MSBDWallpaperMadeFor(current);
    double lo = MIN(sw, sh), hi = MAX(sw, sh);
    BOOL aFits = MIN(a.width, a.height) == lo && MAX(a.width, a.height) == hi, bFits = MIN(b.width, b.height) == lo && MAX(b.width, b.height) == hi;
    if (aFits != bFits) return aFits;
    return a.width * a.height > b.width * b.height;
}
// Mac Wallpapers: the pictures in the folder, by name (as the Files app sorts), each shown with its file name; hidden files and anything that is
// not a picture are left out.
static inline NSArray<NSString *> *MSBDWallpaperMacList(NSArray<NSString *> *names) {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *n in names) if ([n isKindOfClass:[NSString class]] && n.length && ![n hasPrefix:@"."] && ![n containsString:@"/"] && MSBDWallpaperIsPictureFile(n)) [out addObject:n];
    return [out sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}
static inline NSString *MSBDWallpaperMacName(NSString *file) { return file.lastPathComponent.stringByDeletingPathExtension; }
// Add from Files: the name the picture gets in the folder -- its own, or "<name> 2", "<name> 3"... when one of that name is there (nothing is
// replaced, as the Files app does).
static inline NSString *MSBDWallpaperImportName(NSString *name, NSArray<NSString *> *existing) {
    NSString *base = name.lastPathComponent.stringByDeletingPathExtension, *ext = name.pathExtension;
    if (!base.length) base = @"Picture";
    NSMutableSet *have = [NSMutableSet set];
    for (NSString *e in existing) [have addObject:e.lowercaseString];
    NSString *cand = ext.length ? [base stringByAppendingPathExtension:ext] : base;
    for (int i = 2; [have containsObject:cand.lowercaseString] && i < 10000; i++) {
        NSString *b = [NSString stringWithFormat:@"%@ %d", base, i];
        cand = ext.length ? [b stringByAppendingPathExtension:ext] : b;
    }
    return cand;
}
