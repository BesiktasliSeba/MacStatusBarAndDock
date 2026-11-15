// test-macfolder.m -- Mac test (Mac Catalyst: UIKit on the Mac) of Finder's folder picture (1.8.7.4 round 2, KT 14 Nov: "the folder icons inside
// finder are currently not mac-like. they have a empty line going across the top of the folder"). Finder drew iPadOS's folder.fill symbol, whose
// tab and back are cut off from the front by a clear line across the top; the desktop drew its own macOS folder. Now Finder draws the desktop's:
// the painter (DMDesktopFolderFill, DMDesktopDrawFolder) moved out of Desktop.h into statusbar/MacFolder.h, included before Finder.h and
// Desktop.h, and Finder's DMFinderFolderPicture renders it at the icon's side and the screen's scale, once per side.
// Runs the real code, cut out by test-macfolder.sh: the painter (mf-painter.inc: MacFolder.h, or Desktop.h before), Finder's DMFinderAppIcon,
// DMFinderFolderPicture (not there before) and DMFinderIcon (mf-finder.inc, Finder.h) and the desktop's -dm_folderImage (mf-desktop.inc, Desktop.h).
// With MF_REF, a second copy of Finder's functions (mf-ref.inc, renamed ...Ref: the code before the change) is built in too, for the proof that
// every other kind of item keeps its picture. One scenario per process: `t <scenario>`, `t list`; `t png <side> <file>` and `t pngapp <side>
// <file>` save Finder's picture of a folder / an app's folder (for the notes' pictures); `t sheet <out> <side> <png>...` lays pictures side by side.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ---- Finder's item (Finder.h DMFinderItem): what DMFinderIcon reads
@interface DMFinderItem : NSObject
@property (nonatomic, copy) NSString *path, *name, *display, *app, *appFolder;
@property (nonatomic) BOOL dir, locked, package, alias;
@end
@implementation DMFinderItem @end
static NSUInteger gFinderAppIconGen;
static NSMutableArray<NSString *> *gMFLog;   // (what the real code logs: DMLog, debug-only in the tweak)
static void MFLogLine(NSString *line) { [gMFLog addObject:line ?: @""]; }
#define DMLog(...) MFLogLine(__VA_ARGS__)

// ---- the painter, counted (every picture of a folder Finder or the desktop makes draws it once)
#include "mf-painter.inc"
static int gMFPaints;
static void MFCountedDraw(CGContextRef c, CGFloat s) { gMFPaints++; DMDesktopDrawFolder(c, s); }
#define DMDesktopDrawFolder MFCountedDraw

// ---- Finder's icons (the real code)
static UIImage *DMFinderIcon(DMFinderItem *it, CGFloat side);
#include "mf-finder.inc"
#ifdef MF_REF
static UIImage *DMFinderIconRef(DMFinderItem *it, CGFloat side);
#include "mf-ref.inc"
#endif

// ---- the desktop (the real -dm_folderImage on a stand-in DMDesktop)
static int gDesktopFolderFrom;
@interface DMDesktop : NSObject { @public UIImage *_folderImage; CGFloat _folderImageSide, _side; } @end
@implementation DMDesktop
#include "mf-desktop.inc"
@end
#undef DMDesktopDrawFolder
#ifdef MF_REF_DESKTOP
// (the desktop before the change: Desktop.h's own painter and -dm_folderImage, renamed ...Ref)
#include "mf-refpainter.inc"
@interface DMDesktopRef : NSObject { @public UIImage *_folderImage; CGFloat _folderImageSide, _side; } @end
@implementation DMDesktopRef
#include "mf-refdesktop.inc"
@end
#endif

// ---- an app's icon (SpringBoard's +[UIImage _applicationIconImageForBundleIdentifier:format:scale:]: a stand-in, one colour per app)
static int gMFAppIcons;
static UIColor *MFAppColor(NSString *bid) { return [bid hasSuffix:@"two"] ? [UIColor colorWithRed:0.2 green:0.8 blue:0.3 alpha:1] : [UIColor colorWithRed:0.96 green:0.2 blue:0.36 alpha:1]; }
static id MFAppIcon(id self, SEL _cmd, NSString *bid, int format, CGFloat scale) {
    gMFAppIcons++;
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat preferredFormat]; f.scale = scale;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(60, 60) format:f] imageWithActions:^(UIGraphicsImageRendererContext *c) {
        [MFAppColor(bid) setFill]; UIRectFill(CGRectMake(0, 0, 60, 60));
    }];
}

static int gMFFails, gMFChecks;
static void MFCheck(BOOL ok, NSString *what) { gMFChecks++; if (!ok) gMFFails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }

// A picture's pixels as they are (RGBA, 8 bits, premultiplied, its own pixel size).
typedef struct { size_t w, h; NSMutableData *px; } MFPix;
static MFPix MFPixels(UIImage *img) {
    MFPix p = { 0, 0, nil };
    CGImageRef cg = img.CGImage; if (!cg) return p;
    p.w = CGImageGetWidth(cg); p.h = CGImageGetHeight(cg); p.px = [NSMutableData dataWithLength:p.w * p.h * 4];
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(p.px.mutableBytes, p.w, p.h, 8, p.w * 4, cs, kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(c, CGRectMake(0, 0, p.w, p.h), cg);
    CGContextRelease(c); CGColorSpaceRelease(cs);
    return p;
}
// As a Finder view shows it: in a side x side box, aspect fit (the list's, the icons', Quick Look's and a drag's image views), at 2x.
static MFPix MFShown(UIImage *img, CGFloat side) {
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat preferredFormat]; f.scale = 2; f.opaque = NO;
    UIImage *box = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side) format:f] imageWithActions:^(UIGraphicsImageRendererContext *c) {
        CGSize s = img.size; CGFloat k = MIN(side / s.width, side / s.height);
        [img drawInRect:CGRectMake((side - s.width * k) / 2.0, (side - s.height * k) / 2.0, s.width * k, s.height * k)];
    }];
    return MFPixels(box);
}
static BOOL MFSame(UIImage *a, UIImage *b) {
    if (!a || !b || !CGSizeEqualToSize(a.size, b.size) || a.scale != b.scale) return NO;
    MFPix x = MFPixels(a), y = MFPixels(b);
    return x.px && y.px && x.w == y.w && x.h == y.h && [x.px isEqualToData:y.px];
}
static int MFAlpha(MFPix p, size_t x, size_t y) { return ((unsigned char *)p.px.mutableBytes)[(y * p.w + x) * 4 + 3]; }
// KT's complaint, measured: a row of the picture that is mostly clear (60 % or more of the picture's width) with a mostly opaque row above it and
// below it -- a line across the folder. Returns the first such row (in px from the top), or -1.
static long MFClearLine(MFPix p) {
    long x0 = (long)p.w, x1 = -1, y0 = (long)p.h, y1 = -1;
    for (size_t y = 0; y < p.h; y++) for (size_t x = 0; x < p.w; x++) if (MFAlpha(p, x, y) >= 64) { x0 = MIN(x0, (long)x); x1 = MAX(x1, (long)x); y0 = MIN(y0, (long)y); y1 = MAX(y1, (long)y); }
    if (x1 < 0) return -2;
    double w = x1 - x0 + 1, clear[4096];
    for (long y = y0; y <= y1 && y - y0 < 4096; y++) { long n = 0; for (long x = x0; x <= x1; x++) if (MFAlpha(p, x, y) < 64) n++; clear[y - y0] = n / w; }
    for (long y = y0 + 1; y < y1; y++) {
        if (clear[y - y0] < 0.6) continue;
        BOOL above = NO, below = NO;
        for (long u = y0; u < y; u++) if (clear[u - y0] <= 0.25) above = YES;
        for (long u = y + 1; u <= y1; u++) if (clear[u - y0] <= 0.25) below = YES;
        if (above && below) return y;
    }
    return -1;
}
static DMFinderItem *MFItem(NSString *path, BOOL dir) {
    DMFinderItem *it = [DMFinderItem new]; it.path = path; it.name = path.lastPathComponent; it.display = it.name; it.dir = dir; return it;
}
static UIImage *MFDesktop(CGFloat side) { DMDesktop *d = [DMDesktop new]; d->_side = side; return [d dm_folderImage]; }
// The macOS folder's colours (MacFolder.h's gradient stops, device RGB) at a point y of the 256 grid: n stops at ys.
static void MFMix(int n, const double *ys, const unsigned *rgb, double y, double out[3]) {
    int i = 0; while (i < n - 2 && y > ys[i + 1]) i++;
    double t = (y - ys[i]) / (ys[i + 1] - ys[i]); t = t < 0 ? 0 : t > 1 ? 1 : t;
    for (int c = 0; c < 3; c++) { double a = (rgb[i] >> (16 - 8 * c) & 0xFF), b = (rgb[i + 1] >> (16 - 8 * c) & 0xFF); out[c] = a + (b - a) * t; }
}
static NSString *MFLook(UIImage *img) {   // nil: the macOS folder's look at 256 pt (its colours inside, clear around); else what differs
    MFPix p = MFPixels(img); if (!p.px || p.w != 512) return @"not 256 pt at 2x";
    static const double back[] = { 38, 52, 68 }, front[] = { 68, 76, 188, 194, 213 };
    static const unsigned backRGB[] = { 0x41A2D6, 0x2F96D2, 0x007AC9 }, frontRGB[] = { 0x6CC9F6, 0x74CFFB, 0x70CDF9, 0x64C4F0, 0x50B6E8 };
    struct { double x, y; int front; const char *what; } at[] = { { 60, 45, 0, "the tab" }, { 170, 57, 0, "the back" }, { 130, 74, 1, "the front, top edge" }, { 130, 100, 1, "the front, top" },
        { 130, 150, 1, "the front, middle" }, { 60, 185, 1, "the front, low" }, { 200, 210, 1, "the front, bottom" } };
    for (size_t i = 0; i < sizeof at / sizeof at[0]; i++) {
        double want[3]; if (at[i].front) MFMix(5, front, frontRGB, at[i].y, want); else MFMix(3, back, backRGB, at[i].y, want);
        unsigned char *c = (unsigned char *)p.px.mutableBytes + ((size_t)(at[i].y * 2) * p.w + (size_t)(at[i].x * 2)) * 4;
        for (int k = 0; k < 3; k++) if (fabs(c[k] - want[k]) > 6 || c[3] != 255)
            return [NSString stringWithFormat:@"%s (%.0f,%.0f): %d,%d,%d,%d, want %.0f,%.0f,%.0f", at[i].what, at[i].x, at[i].y, c[0], c[1], c[2], c[3], want[0], want[1], want[2]];
    }
    struct { double x, y; } clear[] = { { 4, 4 }, { 128, 12 }, { 250, 128 }, { 128, 250 }, { 160, 42 } };   // (around it, and right of the tab)
    for (size_t i = 0; i < sizeof clear / sizeof clear[0]; i++) if (MFAlpha(p, (size_t)(clear[i].x * 2), (size_t)(clear[i].y * 2)) > 8)
        return [NSString stringWithFormat:@"not clear at (%.0f,%.0f)", clear[i].x, clear[i].y];
    return nil;
}
static const CGFloat kMFSides[] = { 16, 18, 32, 56, 64, 128, 80.5 };   // (Finder's: the list 18, a drag 32, the icons 56, Quick Look 128)
#define MF_NSIDES (sizeof kMFSides / sizeof kMFSides[0])

static void MFScenario(NSString *s) {
    NSString *tmp = NSTemporaryDirectory();
    if ([s isEqualToString:@"same"]) {   // Finder's folder is the desktop's, pixel for pixel, at every side
        for (size_t i = 0; i < MF_NSIDES; i++) {
            CGFloat side = kMFSides[i];
            UIImage *f = DMFinderIcon(MFItem([tmp stringByAppendingPathComponent:@"Projects"], YES), side), *d = MFDesktop(side);
            MFCheck(f && CGSizeEqualToSize(f.size, CGSizeMake(side, side)) && f.scale == [UIScreen mainScreen].scale,
                    [NSString stringWithFormat:@"%.1f pt: Finder's folder is %.1f x %.1f pt at %.0fx (the icon's side, the screen's scale %.0fx)", side, f.size.width, f.size.height, f.scale, [UIScreen mainScreen].scale]);
            MFCheck(MFSame(f, d), [NSString stringWithFormat:@"%.1f pt: Finder's folder and the desktop's folder are the same picture, pixel for pixel", side]);
        }
    } else if ([s isEqualToString:@"noline"]) {   // no clear line across the top, as Finder's views show it
        for (size_t i = 0; i < MF_NSIDES; i++) {
            CGFloat side = kMFSides[i];
            long row = MFClearLine(MFShown(DMFinderIcon(MFItem([tmp stringByAppendingPathComponent:@"Projects"], YES), side), side));
            MFCheck(row == -1, [NSString stringWithFormat:@"%.1f pt: no clear line across the folder (%@)", side, row == -1 ? @"none" : [NSString stringWithFormat:@"a clear row %ld px from the top", row]]);
            long drow = MFClearLine(MFShown(MFDesktop(side), side));
            MFCheck(drow == -1, [NSString stringWithFormat:@"%.1f pt: the desktop's folder has none either (the measure itself)", side]);
        }
        // (the measure sees iPadOS's folder.fill line where the views showed it: the picture Finder drew before)
        int seen = 0;
        const CGFloat olds[] = { 32, 56, 64, 128 };
        for (size_t i = 0; i < 4; i++) {
            CGFloat side = olds[i];
            UIImage *old = [[UIImage systemImageNamed:@"folder.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:side * 0.8 weight:UIImageSymbolWeightRegular]]
                            imageWithTintColor:[UIColor colorWithRed:0.33 green:0.66 blue:0.96 alpha:1] renderingMode:UIImageRenderingModeAlwaysOriginal];
            if (MFClearLine(MFShown(old, side)) >= 0) seen++;
        }
        MFCheck(seen == 4, [NSString stringWithFormat:@"the measure finds iPadOS's folder.fill line at 32, 56, 64 and 128 pt (%d of 4)", seen]);
    } else if ([s isEqualToString:@"cache"]) {   // made once per side: a folder of folders laid out, scrolled, laid out again draws each side once
        gMFPaints = 0; [gMFLog removeAllObjects];
        NSMutableSet *seen18 = [NSMutableSet set], *seen56 = [NSMutableSet set];
        for (int pass = 0; pass < 3; pass++) for (int r = 0; r < 200; r++) {
            DMFinderItem *it = MFItem([tmp stringByAppendingPathComponent:[NSString stringWithFormat:@"Folder %d", r]], YES);
            [seen18 addObject:[NSValue valueWithPointer:(__bridge void *)DMFinderIcon(it, 18.0)]];
            [seen56 addObject:[NSValue valueWithPointer:(__bridge void *)DMFinderIcon(it, 56.0)]];
        }
        MFCheck(gMFPaints == 2, [NSString stringWithFormat:@"1200 rows and icons of folders at 18 and 56 pt: the folder drawn %d time(s) (once per side: 2)", gMFPaints]);
        MFCheck(seen18.count == 1 && seen56.count == 1, [NSString stringWithFormat:@"every row gets the one picture of its side (%lu at 18 pt, %lu at 56 pt)", (unsigned long)seen18.count, (unsigned long)seen56.count]);
        NSString *want = [NSString stringWithFormat:@"[finder] folder picture made: 18.0 pt at %.0fx, the desktop's macOS folder|[finder] folder picture made: 56.0 pt at %.0fx, the desktop's macOS folder", [UIScreen mainScreen].scale, [UIScreen mainScreen].scale];
        MFCheck([[gMFLog componentsJoinedByString:@"|"] isEqualToString:want], [NSString stringWithFormat:@"the debug log says so once per side (%lu line(s): %@)", (unsigned long)gMFLog.count, gMFLog.firstObject ?: @"none"]);
        int before = gMFPaints; UIImage *q = DMFinderIcon(MFItem([tmp stringByAppendingPathComponent:@"Projects"], YES), 128.0);
        DMFinderIcon(MFItem([tmp stringByAppendingPathComponent:@"Other"], YES), 128.0);
        MFCheck(q && gMFPaints == before + 1, [NSString stringWithFormat:@"a new side (Quick Look's 128 pt) is drawn once (%d)", gMFPaints - before]);
    } else if ([s isEqualToString:@"kinds"]) {   // what else Finder shows a folder picture for, and what it does not
        CGFloat side = 56.0;
        UIImage *plain = DMFinderIcon(MFItem([tmp stringByAppendingPathComponent:@"Projects"], YES), side);
        DMFinderItem *pkg = MFItem([tmp stringByAppendingPathComponent:@"Notes.rtfd"], YES); pkg.package = YES;
        MFCheck(MFSame(DMFinderIcon(pkg, side), plain), @"a package Finder shows as a folder (Notes.rtfd) gets the macOS folder too, not folder.fill");
        DMFinderItem *alias = MFItem([tmp stringByAppendingPathComponent:@"Link"], YES); alias.alias = YES;
        MFCheck(MFSame(DMFinderIcon(alias, side), plain), @"a link to a folder: the macOS folder (its arrow is added by DMFinderIconWithAlias, as before)");
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:side * 0.8 weight:UIImageSymbolWeightRegular];
        UIImage *lock = [[UIImage systemImageNamed:@"lock.fill" withConfiguration:cfg] imageWithTintColor:[UIColor systemGrayColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
        DMFinderItem *locked = MFItem([tmp stringByAppendingPathComponent:@"Private"], YES); locked.locked = YES;
        UIImage *li = DMFinderIcon(locked, side);
        MFCheck(li && CGSizeEqualToSize(li.size, lock.size) && [MFShown(li, side).px isEqualToData:MFShown(lock, side).px], @"a folder Finder can't open keeps its grey lock.fill");
        DMFinderItem *lockedApp = MFItem([tmp stringByAppendingPathComponent:@"Data"], YES); lockedApp.locked = YES; lockedApp.appFolder = @"com.example.one";
        UIImage *lai = DMFinderIcon(lockedApp, side);
        MFCheck(lai && [MFShown(lai, side).px isEqualToData:MFShown(lock, side).px], @"... an app's folder Finder can't open too");
        // a file: its type's icon, as before (the same picture UIKit gives for its extension)
        DMFinderItem *txt = MFItem([tmp stringByAppendingPathComponent:@"read me.txt"], NO);
        UIDocumentInteractionController *dic = [UIDocumentInteractionController interactionControllerWithURL:[NSURL fileURLWithPath:txt.path]];
        UIImage *best = nil; for (UIImage *i in dic.icons) if (!best || fabs(i.size.width - side) < fabs(best.size.width - side)) best = i;
        best = best ?: [UIImage systemImageNamed:@"doc" withConfiguration:cfg];
        UIImage *ti = DMFinderIcon(txt, side);
        MFCheck(ti && best && ti == DMFinderIcon(txt, side) && CGSizeEqualToSize(ti.size, best.size) && [MFShown(ti, side).px isEqualToData:MFShown(best, side).px], @"a file: its type's icon, as before");
        int paints = gMFPaints; DMFinderIcon(txt, side);
        MFCheck(gMFPaints == paints, @"... and no folder drawn for it");
    } else if ([s isEqualToString:@"appfolder"]) {   // an app's folder in On My iPad: the macOS folder with the app's icon on its front
        const CGFloat sides[] = { 18, 56, 128 };
        for (size_t i = 0; i < 3; i++) {
            CGFloat side = sides[i];
            DMFinderItem *it = MFItem([tmp stringByAppendingPathComponent:@"5F3A-UUID"], YES); it.appFolder = @"com.example.one"; it.display = @"Example";
            int icons = gMFAppIcons, paints = gMFPaints;
            UIImage *a = DMFinderIcon(it, side), *plain = DMFinderIcon(MFItem([tmp stringByAppendingPathComponent:@"Projects"], YES), side);
            MFCheck(a && CGSizeEqualToSize(a.size, CGSizeMake(side, side)), [NSString stringWithFormat:@"%.0f pt: an app's folder is the folder's square (%.1f x %.1f)", side, a.size.width, a.size.height]);
            MFPix p = MFPixels(a), q = MFPixels(plain);
            // the app's icon: centred on the front (26..235 x 68..213.5 of the 256 grid), 92 of 256 wide -- 94.75..186.75 high, above the folds at
            // 193.5 --; every pixel away from it is the folder's
            double k = p.w / 256.0; long cx = lround(130.5 * k), cy = lround(140.75 * k), half = lround(46 * k), outside = 0, differ = 0;
            for (size_t y = 0; p.px && q.px && p.w == q.w && y < p.h; y++) for (size_t x = 0; x < p.w; x++) {
                if (labs((long)x - cx) <= half + 2 && labs((long)y - cy) <= half + 2) continue;
                outside++; if (memcmp((char *)p.px.mutableBytes + (y * p.w + x) * 4, (char *)q.px.mutableBytes + (y * q.w + x) * 4, 4)) differ++;
            }
            MFCheck(outside > 0 && differ == 0, [NSString stringWithFormat:@"%.0f pt: around the app's icon it is the macOS folder, pixel for pixel (%ld of %ld differ)", side, differ, outside]);
            unsigned char *c = p.px ? (unsigned char *)p.px.mutableBytes + ((size_t)cy * p.w + (size_t)cx) * 4 : NULL;
            MFCheck(c && c[0] > 200 && c[1] < 90 && c[3] == 255, [NSString stringWithFormat:@"%.0f pt: the app's icon sits at the front's centre (%d,%d,%d)", side, c ? c[0] : -1, c ? c[1] : -1, c ? c[2] : -1]);
            // ... at its whole size, 92 of 256 (84.5..176.5 x 94.75..186.75): its colour reaches each side of that box -- the first and the last pixel
            // wholly inside it, at the middle of each side (clear of the rounded corners); the check above bounds it from outside
            long x0 = (long)ceil(84.5 * k), x1 = (long)floor(176.5 * k) - 1, y0 = (long)ceil(94.75 * k), y1 = (long)floor(186.75 * k) - 1, at[4][2] = { { x0, cy }, { x1, cy }, { cx, y0 }, { cx, y1 } };
            int reach = 0;
            for (int j = 0; j < 4; j++) {
                unsigned char *e = p.px && at[j][0] >= 0 && at[j][1] >= 0 && (size_t)at[j][0] < p.w && (size_t)at[j][1] < p.h ? (unsigned char *)p.px.mutableBytes + ((size_t)at[j][1] * p.w + (size_t)at[j][0]) * 4 : NULL;
                if (e && e[0] > 200 && e[1] < 90 && e[3] == 255) reach++;
            }
            MFCheck(reach == 4, [NSString stringWithFormat:@"%.0f pt: the app's icon fills its box, 92 of 256 wide and high (its colour at the middle of each side, pixels %ld..%ld x %ld..%ld: %d of 4)", side, x0, x1, y0, y1, reach]);
            MFCheck(MFClearLine(MFShown(a, side)) == -1, [NSString stringWithFormat:@"%.0f pt: no clear line across an app's folder either", side]);
            UIImage *again = DMFinderIcon(it, side);
            MFCheck(again == a && gMFAppIcons == icons + 1 && gMFPaints <= paints + 1, [NSString stringWithFormat:@"%.0f pt: made once per app and side (app icon asked %d time(s), folder drawn %d time(s))", side, gMFAppIcons - icons, gMFPaints - paints]);
            DMFinderItem *two = MFItem([tmp stringByAppendingPathComponent:@"9C1B-UUID"], YES); two.appFolder = @"com.example.two";
            UIImage *b = DMFinderIcon(two, side); MFPix r = MFPixels(b);
            unsigned char *d = r.px ? (unsigned char *)r.px.mutableBytes + ((size_t)cy * r.w + (size_t)cx) * 4 : NULL;
            MFCheck(b != a && d && d[1] > 150 && d[0] < 100, [NSString stringWithFormat:@"%.0f pt: another app's folder has its own icon on it", side]);
        }
    } else if ([s isEqualToString:@"look"]) {   // the macOS folder: its blues where the painter puts them, clear around it
        NSString *d = MFLook(MFDesktop(256)), *f = MFLook(DMFinderIcon(MFItem([tmp stringByAppendingPathComponent:@"Projects"], YES), 256));
        MFCheck(!d, [NSString stringWithFormat:@"the desktop's folder at 256 pt: the macOS folder's tab, back and front colours, clear around it%@", d ? [@" -- " stringByAppendingString:d] : @""]);
        MFCheck(!f, [NSString stringWithFormat:@"Finder's folder at 256 pt: the same%@", f ? [@" -- " stringByAppendingString:f] : @""]);
    } else if ([s isEqualToString:@"refdesk"]) {   // (MF_REF_DESKTOP) the desktop's folders are the pictures they were, pixel for pixel
#ifdef MF_REF_DESKTOP
        const CGFloat sides[] = { 16, 18, 32, 48, 56, 64, 72.5, 80, 96, 112.25, 128, 256 };
        int same = 0;
        for (size_t i = 0; i < sizeof sides / sizeof sides[0]; i++) {
            DMDesktopRef *r = [DMDesktopRef new]; r->_side = sides[i];
            if (MFSame(MFDesktop(sides[i]), [r dm_folderImage])) same++; else printf("   differs at %.2f pt\n", sides[i]);
        }
        MFCheck(same == (int)(sizeof sides / sizeof sides[0]), [NSString stringWithFormat:@"the desktop's folder at 12 sides (16 to 256 pt, fractional ones too): the same picture as before the move, pixel for pixel (%d of 12)", same]);
#else
        MFCheck(NO, @"built without MF_REF_DESKTOP");
#endif
    } else if ([s isEqualToString:@"ref"]) {   // (MF_REF) every other kind keeps the picture the code before gave
#ifdef MF_REF
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *d = [tmp stringByAppendingPathComponent:[NSString stringWithFormat:@"mf-ref-%d", getpid()]];
        [fm createDirectoryAtPath:[d stringByAppendingPathComponent:@"Plain.app"] withIntermediateDirectories:YES attributes:nil error:nil];
        [fm createDirectoryAtPath:[d stringByAppendingPathComponent:@"Mine.app"] withIntermediateDirectories:YES attributes:nil error:nil];
        [@{@"CFBundleIdentifier": @"com.example.one"} writeToFile:[d stringByAppendingPathComponent:@"Mine.app/Info.plist"] atomically:YES];
        NSMutableArray<DMFinderItem *> *items = [NSMutableArray array];
        for (NSString *n in @[@"a.txt", @"b.pdf", @"c.png", @"d.zip", @"e", @"f.mp3", @"g.json", @"h.ipa"]) [items addObject:MFItem([d stringByAppendingPathComponent:n], NO)];
        [items addObject:MFItem([d stringByAppendingPathComponent:@"Plain.app"], YES)];
        [items addObject:MFItem([d stringByAppendingPathComponent:@"Mine.app"], YES)];
        DMFinderItem *row = MFItem([d stringByAppendingPathComponent:@"Mine"], NO); row.app = [d stringByAppendingPathComponent:@"Mine.app"]; [items addObject:row];
        DMFinderItem *locked = MFItem([d stringByAppendingPathComponent:@"Private"], YES); locked.locked = YES; [items addObject:locked];
        DMFinderItem *lockedApp = MFItem([d stringByAppendingPathComponent:@"Data"], YES); lockedApp.locked = YES; lockedApp.appFolder = @"com.example.two"; [items addObject:lockedApp];
        int same = 0, n = 0;
        const CGFloat sides[] = { 18, 32, 56, 128 };
        for (DMFinderItem *it in items) for (size_t i = 0; i < 4; i++) {
            CGFloat side = sides[i];
            UIImage *a = DMFinderIcon(it, side), *b = DMFinderIconRef(it, side);
            BOOL eq = a && b && CGSizeEqualToSize(a.size, b.size) && [MFShown(a, side).px isEqualToData:MFShown(b, side).px];
            n++; if (eq) same++; else printf("   differs: %s at %.0f pt\n", it.name.UTF8String, side);
        }
        MFCheck(same == n, [NSString stringWithFormat:@"every other kind (8 file types, 2 apps, an app's row, a locked folder, a locked app's folder; 4 sides): the same picture as the code before (%d of %d)", same, n]);
        int differ = 0;
        for (size_t i = 0; i < 4; i++) {
            CGFloat side = sides[i];
            DMFinderItem *f = MFItem([d stringByAppendingPathComponent:@"Projects"], YES), *af = MFItem([d stringByAppendingPathComponent:@"5F3A"], YES); af.appFolder = @"com.example.one";
            if (![MFShown(DMFinderIcon(f, side), side).px isEqualToData:MFShown(DMFinderIconRef(f, side), side).px]) differ++;
            if (![MFShown(DMFinderIcon(af, side), side).px isEqualToData:MFShown(DMFinderIconRef(af, side), side).px]) differ++;
        }
        MFCheck(differ == 8, [NSString stringWithFormat:@"... while a folder and an app's folder do change (%d of 8)", differ]);
        [fm removeItemAtPath:d error:nil];
#else
        MFCheck(NO, @"built without MF_REF");
#endif
    } else MFCheck(NO, [@"no scenario " stringByAppendingString:s]);
}

static BOOL MFSavePNG(UIImage *img, NSString *file) { return img && [UIImagePNGRepresentation(img) writeToFile:file atomically:YES]; }

int main(int argc, char **argv) {
    @autoreleasepool {
        Method m = class_getClassMethod([UIImage class], NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:"));
        if (!m) class_addMethod(object_getClass([UIImage class]), NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:"), (IMP)MFAppIcon, "@@:@id");
        gMFLog = [NSMutableArray array];
        NSString *s = argc > 1 ? @(argv[1]) : @"list";
        if ([s isEqualToString:@"list"]) { printf("same\nnoline\nlook\ncache\nkinds\nappfolder\n"); return 0; }
        if ([s isEqualToString:@"png"] && argc > 3) return MFSavePNG(DMFinderIcon(MFItem(@"/tmp/Projects", YES), atof(argv[2])), @(argv[3])) ? 0 : 1;
        if ([s isEqualToString:@"pngapp"] && argc > 3) { DMFinderItem *it = MFItem(@"/tmp/5F3A", YES); it.appFolder = @"com.example.one"; return MFSavePNG(DMFinderIcon(it, atof(argv[2])), @(argv[3])) ? 0 : 1; }
        if ([s isEqualToString:@"sheet"] && argc > 4) {   // sheet <out> <side> <png>...: each picture in a side x side box (aspect fit), on a light and a dark row, 2x
            CGFloat side = atof(argv[3]), pad = MAX(8, side / 2); int n = argc - 4;
            NSMutableArray<UIImage *> *imgs = [NSMutableArray array];
            for (int i = 4; i < argc; i++) { UIImage *im = [UIImage imageWithContentsOfFile:@(argv[i])]; if (!im) return 1; [imgs addObject:[UIImage imageWithCGImage:im.CGImage scale:2 orientation:UIImageOrientationUp]]; }
            UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat preferredFormat]; f.scale = 2;
            CGSize all = CGSizeMake(n * (side + pad) + pad, 2 * (side + pad) + pad);
            UIImage *sheet = [[[UIGraphicsImageRenderer alloc] initWithSize:all format:f] imageWithActions:^(UIGraphicsImageRendererContext *c) {
                [[UIColor whiteColor] setFill]; UIRectFill(CGRectMake(0, 0, all.width, all.height / 2));
                [[UIColor colorWithWhite:0.12 alpha:1] setFill]; UIRectFill(CGRectMake(0, all.height / 2, all.width, all.height / 2));
                for (int row = 0; row < 2; row++) for (int i = 0; i < n; i++) {
                    UIImage *im = imgs[i]; CGSize sz = im.size; CGFloat k = MIN(side / sz.width, side / sz.height);
                    CGFloat x = pad + i * (side + pad), y = pad / 2 + row * (side + pad) + (row ? pad / 2 : 0);
                    [im drawInRect:CGRectMake(x + (side - sz.width * k) / 2, y + (side - sz.height * k) / 2, sz.width * k, sz.height * k)];
                }
            }];
            return MFSavePNG(sheet, @(argv[2])) ? 0 : 1;
        }
        MFScenario(s);
        printf("   (%d check(s), %d failed)\n", gMFChecks, gMFFails);
        return gMFFails ? 1 : 0;
    }
}
