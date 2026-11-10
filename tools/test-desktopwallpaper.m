// Mac test of Desktop Picture's rules (common/DesktopWallpaper.h, 1.8.6): the paths SpringBoard may show, the part of a picture a screen shows and
// its pixel size, iPadOS's still wallpapers among its bundles (the file lists as read on the 17.5.1, 10 Nov), their names, the size picked, the Mac
// Wallpapers folder's list and Add from Files' names.
#import "../common/DesktopWallpaper.h"
#include <stdio.h>
static int fails = 0;
#define CHECK(name, cond) do { if (cond) printf("PASS  %s\n", name); else { printf("FAIL  %s\n", name); fails++; } } while (0)
static BOOL near(CGRect r, double x, double y, double w, double h) { return fabs(r.origin.x - x) < 1 && fabs(r.origin.y - y) < 1 && fabs(r.size.width - w) < 1 && fabs(r.size.height - h) < 1; }
int main(void) { @autoreleasepool {
    NSString *mac = @"/var/mobile/Containers/Shared/AppGroup/45185D92-B5BF-455E-9C03-611C961B44B6/File Provider Storage/MacStatusBar&Dock/Wallpapers";
#define OK(p) MSBDWallpaperPathAllowedIn(p, mac)
    CHECK("path: a Mac Wallpapers picture (On My iPad > MacStatusBar&Dock > Wallpapers)", OK([mac stringByAppendingPathComponent:@"Big Sur.heic"]) && OK([mac stringByAppendingPathComponent:@"Yosemite 4.JPG"]));
    CHECK("path: in a folder inside it, or a hidden file: refused", !OK([mac stringByAppendingPathComponent:@"x/Big Sur.heic"]) && !OK([mac stringByAppendingPathComponent:@".hidden.jpg"]));
    CHECK("path: elsewhere in On My iPad: refused", !OK([mac.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"a.jpg"]));
    CHECK("path: no Mac Wallpapers folder known: its pictures refused", !MSBDWallpaperPathAllowedIn([mac stringByAppendingPathComponent:@"a.jpg"], nil));
    CHECK("path: iPadOS's own (read only)", OK(@"/Library/Wallpaper/Collections/iPadOS_17~ipad.wallpaperCollection/Wallpapers/7570.iPadOS_17_Flat-1024w-1366h@2x~ipad.wallpaper/7570.iPadOS_17_Flat_Background-1024w-1366h@2x~ipad.ca/assets/J120.HEIC"));
    CHECK("path: the copy from Photos", OK(@"/var/jb/var/mobile/Library/Preferences/MacStatusBarAndDock-DesktopPicture-1762770000.jpg"));
    CHECK("path: another file in the preferences folder: refused", !OK(@"/var/jb/var/mobile/Library/Preferences/com.apple.springboard.jpg"));
    CHECK("path: a subfolder of the preferences folder: refused", !OK(@"/var/jb/var/mobile/Library/Preferences/x/MacStatusBarAndDock-DesktopPicture-1.jpg"));
    CHECK("path: out of a folder with ..: refused", !OK([mac stringByAppendingString:@"/../../../../../../var/mobile/a.jpg"]) && !OK(@"/Library/Wallpaper/../../var/mobile/a.jpg"));
    CHECK("path: not a picture: refused", !OK([mac stringByAppendingPathComponent:@"notes.txt"]));
    CHECK("path: relative, empty, the crash guard's none: refused", !OK(@"Wallpapers/a.jpg") && !OK(@"") && !OK(@"none") && !OK((NSString *)(id)@1));
    CHECK("path: anywhere else: refused", !OK(@"/var/mobile/Media/DCIM/100APPLE/IMG_0001.JPG"));
    // the part shown: a square picture, portrait 12.9" (2048x2732 px) and landscape
    CHECK("fill: square on portrait: the full height, the centre's width", near(MSBDWallpaperFillRect(2732, 2732, 2048, 2732), 342, 0, 2048, 2732));
    CHECK("fill: square on landscape: the full width, the centre's height", near(MSBDWallpaperFillRect(2732, 2732, 2732, 2048), 0, 342, 2732, 2048));
    CHECK("fill: a 4:3 landscape photo on portrait: the middle strip", near(MSBDWallpaperFillRect(4032, 3024, 2048, 2732), 882, 0, 2267, 3024));
    CHECK("fill: no size: the whole picture", near(MSBDWallpaperFillRect(100, 50, 0, 0), 0, 0, 100, 50));
    CGSize d = MSBDWallpaperDecodeSize(MSBDWallpaperFillRect(2732, 2732, 2048, 2732), 2048, 2732);
    CHECK("decode: the screen's pixels (one picture of 2048x2732, not the square)", d.width == 2048 && d.height == 2732);
    d = MSBDWallpaperDecodeSize(MSBDWallpaperFillRect(4032, 3024, 2048, 2732), 2048, 2732);
    CHECK("decode: a larger photo comes down to the screen's pixels", fabs(d.width - 2048) < 2 && fabs(d.height - 2732) < 2);
    d = MSBDWallpaperDecodeSize(MSBDWallpaperFillRect(800, 600, 2048, 2732), 2048, 2732);
    CHECK("decode: a small picture is never made larger than it is", d.width <= 800 && d.height <= 600 && d.height == 600);
    // iPadOS's turnable stills (3416 px squares shown at their pixels, the screen inside the circle)
    NSString *j = @"/Library/Wallpaper/Collections/iPadOS_17~ipad.wallpaperCollection/Wallpapers/x.wallpaper/x.ca/assets/J120.HEIC";
    CHECK("turnable: a square of iPadOS's own folder; not a Mac picture or a photo, not a non-square", MSBDWallpaperIsTurnable(j, 3416, 3416, 2048, 2732) && !MSBDWallpaperIsTurnable(j, 3000, 2000, 2048, 2732)
          && !MSBDWallpaperIsTurnable(@"/var/jb/var/mobile/Library/Preferences/MacStatusBarAndDock-DesktopPicture-1.jpg", 3000, 3000, 2048, 2732));
    CHECK("turnable: a square only as large as the screen's long side is not (Fill Screen; review 1.8.6 L3); no screen given: any square there",
          !MSBDWallpaperIsTurnable(j, 2732, 2732, 2048, 2732) && MSBDWallpaperIsTurnable(j, 2732, 2732, 0, 0));
    CGRect fillSq = MSBDWallpaperPart(j, 2732, 2732, 2048, 2732);
    CHECK("a 2732 px square of iPadOS's folder on the 12.9-inch: Fill Screen (its full height)", fabs(fillSq.size.height - 2732) < 1);
    {   // iPadOS 15/16: the bundle's Wallpaper.plist names the pictures (16.7.7's WWDC 2022 and WWDC 2021, read 10 Nov)
        NSString *b = @"/Library/Wallpaper/Stills/iPad/7410.WWDC_2022-768w-1024h@2x~ipad.wallpaper";
        NSDictionary *info = @{@"name": @"WWDC 2022", @"assets": @{@"lockAndHome": @{
            @"default": @{@"fullSizeImageFileName": @"7411.WWDC_2022_Light-768w-1024h@2x~ipad.heic", @"representedType": @"Still"},
            @"dark": @{@"fullSizeImageFileName": @"7412.WWDC_2022_Dark-768w-1024h@2x~ipad.heic", @"representedType": @"Still"}}}};
        NSArray *present = @[@"7411.WWDC_2022_Light-768w-1024h@2x~ipad.heic", @"7412.WWDC_2022_Dark-768w-1024h@2x~ipad.heic", @"7410.WWDC_2022.thumbnail-768w-1024h@2x~ipad.heic", @"Wallpaper.plist"];
        NSArray *st = MSBDWallpaperStillFromInfo(info, b, present);
        CHECK("15/16 stills: light and dark from the bundle's Wallpaper.plist (names with ids and sizes)", st.count == 2 && [st[0] hasSuffix:@"7411.WWDC_2022_Light-768w-1024h@2x~ipad.heic"] && [st[1] hasSuffix:@"7412.WWDC_2022_Dark-768w-1024h@2x~ipad.heic"]);
        CHECK("15/16 stills: offloaded (only thumbnails on the iPad) is not offered", !MSBDWallpaperStillFromInfo(info, b, @[@"7410.WWDC_2022.thumbnail-768w-1024h@2x~ipad.heic", @"Wallpaper.plist"]));
        CHECK("17+: a bundle plist naming an animation, no picture file, gives nothing here (the package's pictures are read instead)",
              !MSBDWallpaperStillFromInfo(@{@"assets": @{@"lockAndHome": @{@"default": @{@"backgroundAnimationFileName": @"7570.iPadOS_17_Flat_Background-1024w-1366h@2x~ipad.ca", @"type": @"LayeredAnimation"}}}}, b, @[@"7570.iPadOS_17_Flat_Background-1024w-1366h@2x~ipad.ca"]));
        CHECK("15/16 stills: a name with a path in it is refused", !MSBDWallpaperStillFromInfo(@{@"assets": @{@"lockAndHome": @{@"default": @{@"fullSizeImageFileName": @"../x.heic"}}}}, b, @[@"../x.heic"]));
    }
    CGRect cr = MSBDWallpaperCircleRect(3416, 2048, 2732);
    CHECK("turnable on the 12.9-inch portrait: about its own pixels, centred, the corners inside the circle", fabs(cr.size.width - 2049) < 3 && fabs(cr.size.height - 2733) < 3 && fabs(cr.origin.x - 683) < 3
          && hypot(cr.size.width, cr.size.height) <= 3416.5);
    cr = MSBDWallpaperPart(j, 3416, 3416, 2732, 2048);
    CHECK("turnable in landscape: the same circle, turned", fabs(cr.size.width - 2733) < 3 && fabs(cr.size.height - 2049) < 3 && hypot(cr.size.width, cr.size.height) <= 3416.5);
    cr = MSBDWallpaperPart(@"/x/MacStatusBar&Dock/Wallpapers/Big Sur.heic", 6016, 6016, 2048, 2732);
    CHECK("a square Mac picture: Fill Screen, not the circle", fabs(cr.size.height - 6016) < 1);
    // iPadOS 17.5.1's bundles (file lists as on the iPad)
    NSString *flat = @"/Library/Wallpaper/Collections/iPadOS_17~ipad.wallpaperCollection/Wallpapers/7570.iPadOS_17_Flat-1024w-1366h@2x~ipad.wallpaper";
    NSArray *s = MSBDWallpaperStill(@[[flat stringByAppendingString:@"/Info.plist"], [flat stringByAppendingString:@"/x.ca/main.caml"], [flat stringByAppendingString:@"/x.ca/assets/J120-Dark.HEIC"], [flat stringByAppendingString:@"/x.ca/assets/J120.HEIC"]]);
    CHECK("still: iPadOS 17 Flat: J120 light, J120-Dark dark", s.count == 2 && [s[0] hasSuffix:@"/J120.HEIC"] && [s[1] hasSuffix:@"/J120-Dark.HEIC"]);
    s = MSBDWallpaperStill(@[@"/a/Wallpaper.plist", @"/a/x.ca/assets/J99-Flat.HEIC"]);
    CHECK("still: Lake Flat: one picture, no dark one", s.count == 1 && [s[0] hasSuffix:@"J99-Flat.HEIC"]);
    s = MSBDWallpaperStill(@[@"/a/x.ca/assets/Glass.HEIC", @"/a/x.ca/assets/Star Trails.HEIC", @"/a/x.ca/assets/Mountain Edge.HEIC", @"/a/x.ca/assets/Lake And Mountains.HEIC", @"/a/x.ca/assets/Star Trails Mask.HEIC", @"/a/x.ca/assets/Sky.HEIC"]);
    CHECK("still: Lake (layered, six pictures): left out", s == nil);
    s = MSBDWallpaperStill(@[@"/a/x.ca/assets/Background Dark.HEIC", @"/a/x.ca/assets/Background Light.HEIC", @"/a/y.ca/assets/Green Dark.HEIC", @"/a/y.ca/assets/Red Light.HEIC"]);
    CHECK("still: iPadOS 17 (layered: background and floating shapes): left out", s == nil);
    s = MSBDWallpaperStill(@[@"/a/Info.plist", @"/a/Wallpaper.plist", @"/a/Localizable.loctable"]);
    CHECK("still: Bokeh / Stripe (drawn by code, no picture): left out", s == nil);
    s = MSBDWallpaperStill(@[@"/a/Red.HEIC", @"/a/Blue.HEIC"]);
    CHECK("still: two different pictures: left out", s == nil);
    s = MSBDWallpaperStill(@[@"/a/Sky Light.HEIC", @"/a/Sky Dark.HEIC", @"/a/Sky Mask.HEIC", @"/a/Sky-thumbnail.png"]);
    CHECK("still: masks and thumbnails are not the picture", s.count == 2 && [s[0] hasSuffix:@"Sky Light.HEIC"]);
    CHECK("name: iPadOS 17 Flat -> iPadOS 17", [MSBDWallpaperDisplayName(flat) isEqualToString:@"iPadOS 17"]);
    CHECK("name: Lake Flat -> Lake", [MSBDWallpaperDisplayName(@"/x/7560.Lake_Flat-1024w-1366h@2x~ipad.wallpaper") isEqualToString:@"Lake"]);
    CHECK("name: Stripe Blue", [MSBDWallpaperDisplayName(@"/x/7390.Stripe_Blue.wallpaper") isEqualToString:@"Stripe Blue"]);
    CHECK("size: the bundle made for this screen (1024x1366) over the 11-inch one", MSBDWallpaperBetterFit(@"/x/7570.a-1024w-1366h@2x~ipad.wallpaper", @"/x/7570.a-834w-1112h@2x~ipad.wallpaper", 1024, 1366)
          && !MSBDWallpaperBetterFit(@"/x/7570.a-834w-1112h@2x~ipad.wallpaper", @"/x/7570.a-1024w-1366h@2x~ipad.wallpaper", 1024, 1366));
    CHECK("size: on another screen (820x1180): the largest", MSBDWallpaperBetterFit(@"/x/7570.a-1024w-1366h@2x~ipad.wallpaper", @"/x/7570.a-834w-1112h@2x~ipad.wallpaper", 820, 1180));
    // Mac Wallpapers: the folder's pictures by name, Add from Files' names
    NSArray *list = MSBDWallpaperMacList(@[@"Yosemite 10.heic", @"Big Sur.heic", @"Yosemite 2.jpg", @".DS_Store", @"notes.txt", @"Catalina.PNG", @"sub/x.jpg"]);
    CHECK("mac list: pictures only, by name as the Files app sorts (2 before 10)", [list isEqualToArray:(@[@"Big Sur.heic", @"Catalina.PNG", @"Yosemite 2.jpg", @"Yosemite 10.heic"])]);
    CHECK("mac name: the file name", [MSBDWallpaperMacName(@"Big Sur Coastline.heic") isEqualToString:@"Big Sur Coastline"]);
    CHECK("import: its own name when free", [MSBDWallpaperImportName(@"Monterey.heic", @[@"Big Sur.heic"]) isEqualToString:@"Monterey.heic"]);
    CHECK("import: never replaces: \"<name> 2\", then 3 (any case)", [MSBDWallpaperImportName(@"Monterey.heic", @[@"monterey.HEIC"]) isEqualToString:@"Monterey 2.heic"]
          && [MSBDWallpaperImportName(@"Monterey.heic", @[@"Monterey.heic", @"Monterey 2.heic"]) isEqualToString:@"Monterey 3.heic"]);
    CHECK("import: a name of only a path or nothing", [MSBDWallpaperImportName(@"/tmp/x/Sur.jpg", @[]) isEqualToString:@"Sur.jpg"] && [MSBDWallpaperImportName(@".jpg", @[]) length] > 0);
    printf(fails ? "FAILED %d\n" : "ALL PASS\n", fails);
    return fails ? 1 : 0;
} }
