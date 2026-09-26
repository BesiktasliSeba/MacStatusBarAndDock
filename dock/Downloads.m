// Downloads.m -- a Downloads stack in the Dock, like macOS.
//
// A folder icon sits in the Dock right before the App Library icon (Tweak.x reserves the slot in the Dock's layout numbers
// and calls DMDownloadsAttach with its rectangle). Tapping it opens a panel above the Dock with the most recent downloads.
//
// Where downloads live (found on the device):
//   Safari:   /var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Downloads   (iCloud Drive > Downloads)
//   Browsers: <the app's data container>/Documents/Downloads   (Reynard does this; the container path changes when the app
//             is reinstalled, so it is asked from LaunchServices every time)
// SpringBoard is not sandboxed, so it can read all of these directly.
//
// Opening a download: Safari's are opened in Files (its own quick look), the other browsers' with Filza, because Files
// cannot see another app's container. The panel's footer also has a button per browser that opens its folder.

#import <UIKit/UIKit.h>
#import <ImageIO/ImageIO.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <stdio.h>
#import <sys/stat.h>
#import <notify.h>
#import <unistd.h>

@interface UIWindow (DMPrivateDL)
+ (NSArray *)allWindowsIncludingInternalWindows:(BOOL)internal onlyVisibleWindows:(BOOL)visible;
@end

#import "DMLog.h"
#import "../common/ReduceMotion.h"   // (Reduce Motion: the panel fades instead of popping up)

#pragma mark - model

@interface DMDownload : NSObject
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, copy) NSString *source;
@property (nonatomic, strong) NSDate *date;
@property (nonatomic) long long size;
@property (nonatomic) BOOL directory;
@property (nonatomic) BOOL viaFiles;   // open with Files (Safari) rather than Filza
@end
@implementation DMDownload
@end

@interface DMDownloadSource : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSURL *folder;
@property (nonatomic) BOOL viaFiles;
@end
@implementation DMDownloadSource
@end

// Browsers that keep their downloads in Documents/Downloads of their own container. Only the ones that are installed count.
static NSArray<NSArray<NSString *> *> *DMBrowserList(void) {
    return @[ @[@"com.minh-ton.Reynard", @"Reynard"], @[@"org.mozilla.ios.Firefox", @"Firefox"], @[@"com.google.chrome.ios", @"Chrome"],
              @[@"com.brave.ios.browser", @"Brave"], @[@"com.microsoft.msedge", @"Edge"], @[@"com.opera.OperaTouch", @"Opera"],
              @[@"com.duckduckgo.mobile.ios", @"DuckDuckGo"] ];
}

static NSURL *DMDataContainer(NSString *bundleID) {
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    SEL make = NSSelectorFromString(@"applicationProxyForIdentifier:");
    if (!proxyClass || ![(id)proxyClass respondsToSelector:make]) return nil;
    id proxy = ((id (*)(id, SEL, id))objc_msgSend)((id)proxyClass, make, bundleID);
    id url = [proxy respondsToSelector:NSSelectorFromString(@"dataContainerURL")] ? [proxy valueForKey:@"dataContainerURL"] : nil;
    return [url isKindOfClass:[NSURL class]] ? url : nil;
}

#pragma mark - keeping the Dock forward on purpose (abandoned — see below)

// SBFloatingDockController's private "_addFloatingDockBehaviorAssertion:withCompletion:" is NOT used any more, for good. Tried twice
// tonight: a reckless probe (create-and-discard 11 instances in a loop) crashed SpringBoard in objc_release during autorelease pool
// drain; a careful, single-held-instance, properly paired add/remove usage — the add call worked cleanly and visibly held the Dock
// forward with no crash — still crashed SpringBoard on the REMOVE call, in objc_retain, EXC_BAD_ACCESS, and put the device into jailbreak
// Safe Mode a second time. A class whose ADD half works safely and whose REMOVE half crashes is not something to keep chasing live on a
// daily-driver device — there is no way to tell from the outside what invariant this private, undocumented class actually needs that our
// usage was violating. DMAcquireDockVisibility/DMReleaseDockVisibility (and DMFloatingDockController) are gone. If this is revisited, it
// needs a real disassembly of SBFloatingDockController's remove method, not another guess from a live device.

#define DM_DOMAIN CFSTR("com.besiktasliseba.dockmagnification")

static NSString *DMAppName(NSString *bundleID) {
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    SEL make = NSSelectorFromString(@"applicationProxyForIdentifier:");
    id proxy = (proxyClass && [(id)proxyClass respondsToSelector:make]) ? ((id (*)(id, SEL, id))objc_msgSend)((id)proxyClass, make, bundleID) : nil;
    id name = [proxy respondsToSelector:NSSelectorFromString(@"localizedName")] ? [proxy valueForKey:@"localizedName"] : nil;
    if ([name isKindOfClass:[NSString class]] && [name length]) return name;
    for (NSArray<NSString *> *b in DMBrowserList()) if ([b[0] isEqualToString:bundleID]) return b[1];
    return bundleID.pathExtension.length ? bundleID.pathExtension : bundleID;
}

// The folder an app keeps its downloads in: Documents/Downloads, or its Documents folder when it has no such folder.
static NSURL *DMDownloadFolder(NSString *bundleID) {
    NSURL *container = DMDataContainer(bundleID);
    if (!container) return nil;
    NSURL *documents = [container URLByAppendingPathComponent:@"Documents" isDirectory:YES];
    NSURL *downloads = [documents URLByAppendingPathComponent:@"Downloads" isDirectory:YES];
    BOOL isDir = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:downloads.path isDirectory:&isDir] && isDir) return downloads;
    if ([[NSFileManager defaultManager] fileExistsAtPath:documents.path isDirectory:&isDir] && isDir) return documents;
    return nil;
}

// Settings > Dock > Downloads From. `downloadApps` is an array of bundle ids written by the AltList picker. First time (nothing
// stored yet) it is filled with the known browsers that are installed and have a Downloads folder, so the picker starts ticked.
static NSArray<NSString *> *DMChosenApps(void) {
    CFPreferencesAppSynchronize(DM_DOMAIN);
    CFPropertyListRef raw = CFPreferencesCopyValue(CFSTR("downloadApps"), DM_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    id stored = raw ? CFBridgingRelease(raw) : nil;
    if ([stored isKindOfClass:[NSArray class]]) return stored;
    NSMutableArray *seed = [NSMutableArray array];
    for (NSArray<NSString *> *b in DMBrowserList()) {
        NSURL *container = DMDataContainer(b[0]);
        if (!container) continue;
        BOOL isDir = NO;
        NSURL *dir = [[container URLByAppendingPathComponent:@"Documents" isDirectory:YES] URLByAppendingPathComponent:@"Downloads" isDirectory:YES];
        if ([[NSFileManager defaultManager] fileExistsAtPath:dir.path isDirectory:&isDir] && isDir) [seed addObject:b[0]];
    }
    CFPreferencesSetValue(CFSTR("downloadApps"), (__bridge CFPropertyListRef)seed, DM_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(DM_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    DMLog([NSString stringWithFormat:@"[downloads] seeded the app choice with %@", seed]);
    return seed;
}

static NSArray<DMDownloadSource *> *DMSources(void) {
    NSMutableArray *sources = [NSMutableArray array];
    BOOL includeSafari = YES;
    CFPropertyListRef s = CFPreferencesCopyValue(CFSTR("downloadsSafari"), DM_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (s) { if (CFGetTypeID(s) == CFBooleanGetTypeID()) includeSafari = CFBooleanGetValue(s); CFRelease(s); }
    if (includeSafari) {
        DMDownloadSource *safari = [DMDownloadSource new];
        safari.name = @"Safari";
        safari.folder = [NSURL fileURLWithPath:@"/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Downloads" isDirectory:YES];
        safari.viaFiles = YES;
        [sources addObject:safari];
    }
    NSMutableArray<DMDownloadSource *> *apps = [NSMutableArray array];
    for (NSString *bundleID in DMChosenApps()) {
        if (![bundleID isKindOfClass:[NSString class]]) continue;
        NSURL *dir = DMDownloadFolder(bundleID);
        if (!dir) continue;   // not installed, or nothing to read
        DMDownloadSource *src = [DMDownloadSource new];
        src.name = DMAppName(bundleID); src.folder = dir; src.viaFiles = NO;
        [apps addObject:src];
    }
    [apps sortUsingComparator:^NSComparisonResult(DMDownloadSource *a, DMDownloadSource *b) { return [a.name localizedCaseInsensitiveCompare:b.name]; }];
    [sources addObjectsFromArray:apps];
    return sources;
}

// The newest items of every source, newest first.
static NSArray<DMDownload *> *DMScan(NSArray<DMDownloadSource *> *sources, NSUInteger limit) {
    NSMutableArray<DMDownload *> *all = [NSMutableArray array];
    NSArray *keys = @[NSURLContentModificationDateKey, NSURLCreationDateKey, NSURLFileSizeKey, NSURLIsDirectoryKey];
    for (DMDownloadSource *src in sources) {
        NSArray<NSURL *> *urls = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:src.folder includingPropertiesForKeys:keys
                                                                                  options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
        NSMutableArray<DMDownload *> *mine = [NSMutableArray array];
        for (NSURL *u in urls) {
            NSString *ext = u.pathExtension.lowercaseString;
            if ([@[@"icloud", @"part", @"crdownload", @"download", @"tmp"] containsObject:ext]) continue;   // not finished / not on the device
            NSDictionary *v = [u resourceValuesForKeys:keys error:nil];
            DMDownload *d = [DMDownload new];
            d.url = u; d.source = src.name; d.viaFiles = src.viaFiles;
            d.date = v[NSURLContentModificationDateKey] ?: v[NSURLCreationDateKey] ?: [NSDate distantPast];
            d.size = [v[NSURLFileSizeKey] longLongValue];
            d.directory = [v[NSURLIsDirectoryKey] boolValue];
            [mine addObject:d];
        }
        [mine sortUsingComparator:^NSComparisonResult(DMDownload *a, DMDownload *b) { return [b.date compare:a.date]; }];
        if (mine.count > limit) [mine removeObjectsInRange:NSMakeRange(limit, mine.count - limit)];
        [all addObjectsFromArray:mine];
    }
    [all sortUsingComparator:^NSComparisonResult(DMDownload *a, DMDownload *b) { return [b.date compare:a.date]; }];
    if (all.count > limit) [all removeObjectsInRange:NSMakeRange(limit, all.count - limit)];
    return all;
}

#pragma mark - opening

// Asking LaunchServices to open a URL can block for seconds while the target app (Files, Filza) launches, so it is done off
// the main thread: SpringBoard's UI must never wait for it (it froze the whole Home Screen when done on the main thread).
static void DMOpenURLString(NSString *string) {
    NSURL *url = [NSURL URLWithString:string];
    Class ws = NSClassFromString(@"LSApplicationWorkspace");
    id workspace = [ws respondsToSelector:NSSelectorFromString(@"defaultWorkspace")] ? ((id (*)(id, SEL))objc_msgSend)((id)ws, NSSelectorFromString(@"defaultWorkspace")) : nil;
    DMLog([NSString stringWithFormat:@"[downloads] open %@", string]);
    if (!url || ![workspace respondsToSelector:NSSelectorFromString(@"openSensitiveURL:withOptions:")]) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
        BOOL ok = ((BOOL (*)(id, SEL, id, id))objc_msgSend)(workspace, NSSelectorFromString(@"openSensitiveURL:withOptions:"), url, nil);
        DMLog([NSString stringWithFormat:@"[downloads] open returned %d after %.2f s (off the main thread)", ok, CFAbsoluteTimeGetCurrent() - started]);
    });
}
static NSString *DMEncodedPath(NSString *path) {
    return [path stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];
}
static void DMOpenPath(NSURL *item, BOOL viaFiles) {
    NSString *p = DMEncodedPath(item.path);
    DMOpenURLString(viaFiles ? [@"shareddocuments://" stringByAppendingString:p] : [@"filza://view" stringByAppendingString:p]);
}

#pragma mark - looks

static UIColor *DMBlue(CGFloat r, CGFloat g, CGFloat b) { return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1.0]; }

// The Downloads folder icon, drawn after the macOS Downloads stack tile the owner picked (colours and proportions measured from his
// reference picture, as fractions of the tile): a full app-icon-sized rounded tile, like the other Dock icons, showing a folder
// seen from the front -- a dark back (#0090D2) with a lighter tab at the top left (#3AADE3) that slopes down into a band across
// the top, a light blue front (#5ED0FF) from 18% down with two slightly darker stripes along its bottom edge, and in the middle a
// darker circle (#1896DC) with a thin down arrow in the front's own colour. Drawn, so it stays sharp at any size.
static UIImage *DMFolderImage(CGSize size) {
    static NSMutableDictionary *cache = nil;
    if (!cache) cache = [NSMutableDictionary dictionary];
    NSString *key = NSStringFromCGSize(size);
    if (cache[key]) return cache[key];
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    UIImage *img = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:fmt] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGFloat w = size.width, h = size.height;
        CGContextRef c = ctx.CGContext;
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, w, h) cornerRadius:w * 0.225] addClip];   // continuous corners, like app icons
        // back of the folder
        [DMBlue(0, 144, 210) setFill];
        UIRectFill(CGRectMake(0, 0, w, h * 0.19));
        // the tab: flat along the top to 30% across, then an S-curve down to the band at 42%
        UIBezierPath *tab = [UIBezierPath bezierPath];
        [tab moveToPoint:CGPointMake(0, h * 0.015)];
        [tab addLineToPoint:CGPointMake(w * 0.29, h * 0.015)];
        [tab addCurveToPoint:CGPointMake(w * 0.42, h * 0.106) controlPoint1:CGPointMake(w * 0.35, h * 0.015) controlPoint2:CGPointMake(w * 0.36, h * 0.106)];
        [tab addLineToPoint:CGPointMake(0, h * 0.106)];
        [tab closePath];
        [DMBlue(58, 173, 227) setFill];
        [tab fill];
        // the band across the top, a little lighter at its upper edge
        CGContextSaveGState(c);
        CGContextClipToRect(c, CGRectMake(0, h * 0.106, w, h * 0.076));
        CGFloat band[8] = { 32 / 255.0, 159 / 255.0, 219 / 255.0, 1.0,   0 / 255.0, 146 / 255.0, 210 / 255.0, 1.0 };
        CGGradientRef bandGrad = CGGradientCreateWithColorComponents(space, band, NULL, 2);
        CGContextDrawLinearGradient(c, bandGrad, CGPointMake(0, h * 0.106), CGPointMake(0, h * 0.182), 0);
        CGGradientRelease(bandGrad);
        CGContextRestoreGState(c);
        // the front, with a thin highlight along its top edge and two darker stripes along the bottom
        [DMBlue(94, 208, 255) setFill];
        UIRectFill(CGRectMake(0, h * 0.182, w, h * 0.818));
        [DMBlue(113, 210, 249) setFill];
        UIRectFill(CGRectMake(0, h * 0.182, w, MAX(1.0, h * 0.004)));
        [DMBlue(68, 188, 238) setFill];
        UIRectFill(CGRectMake(0, h * 0.90, w, h * 0.05));
        [DMBlue(43, 171, 229) setFill];
        UIRectFill(CGRectMake(0, h * 0.95, w, h * 0.05));
        CGColorSpaceRelease(space);
        // the circle and arrow
        CGFloat d = w * 0.298;
        CGRect circle = CGRectMake(w / 2.0 - d / 2.0, h * 0.537 - d / 2.0, d, d);
        [DMBlue(24, 150, 220) setFill];
        [[UIBezierPath bezierPathWithOvalInRect:circle] fill];
        UIImage *arrow = [[UIImage systemImageNamed:@"arrow.down" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:d * 0.50 weight:UIImageSymbolWeightSemibold]]
                          imageWithTintColor:DMBlue(97, 207, 255) renderingMode:UIImageRenderingModeAlwaysOriginal];
        [arrow drawInRect:CGRectMake(CGRectGetMidX(circle) - arrow.size.width / 2.0, CGRectGetMidY(circle) - arrow.size.height / 2.0, arrow.size.width, arrow.size.height)];
    }];
    cache[key] = img;
    return img;
}

static NSString *DMSymbolFor(DMDownload *d, UIColor **tint) {
    NSString *ext = d.url.pathExtension.lowercaseString;
    *tint = [UIColor systemGrayColor];
    if (d.directory) { *tint = DMBlue(72, 160, 240); return @"folder.fill"; }
    if ([@[@"ipa", @"zip", @"rar", @"7z", @"tar", @"gz", @"nsp", @"xci", @"dmg", @"deb", @"tipa"] containsObject:ext]) { *tint = DMBlue(199, 152, 92); return @"archivebox.fill"; }
    if ([ext isEqualToString:@"pdf"]) { *tint = [UIColor systemRedColor]; return @"doc.richtext.fill"; }
    if ([@[@"doc", @"docx", @"pages", @"txt", @"rtf"] containsObject:ext]) { *tint = DMBlue(60, 130, 235); return @"doc.text.fill"; }
    if ([@[@"xls", @"xlsx", @"csv", @"numbers"] containsObject:ext]) { *tint = [UIColor systemGreenColor]; return @"tablecells.fill"; }
    if ([@[@"ppt", @"pptx", @"key"] containsObject:ext]) { *tint = [UIColor systemOrangeColor]; return @"rectangle.on.rectangle.fill"; }
    if ([@[@"mp3", @"m4a", @"wav", @"flac", @"aac"] containsObject:ext]) { *tint = [UIColor systemPinkColor]; return @"waveform"; }
    if ([@[@"mp4", @"mov", @"m4v", @"mkv", @"avi"] containsObject:ext]) { *tint = [UIColor systemPurpleColor]; return @"film.fill"; }
    if ([@[@"png", @"jpg", @"jpeg", @"heic", @"gif", @"webp"] containsObject:ext]) { *tint = [UIColor systemTealColor]; return @"photo.fill"; }
    return @"doc.fill";
}

// Real thumbnails for pictures, PDFs and videos (decoded small, off the main thread); everything else keeps its symbol.
static NSCache *DMThumbCache(void) {
    static NSCache *c = nil;
    if (!c) { c = [NSCache new]; c.countLimit = 60; }
    return c;
}
static void DMLoadThumbnail(DMDownload *d, void (^done)(UIImage *image)) {
    NSString *key = [NSString stringWithFormat:@"%@|%f", d.url.path, d.date.timeIntervalSince1970];
    UIImage *cached = [DMThumbCache() objectForKey:key];
    if (cached) { done(cached); return; }
    if (d.directory) return;
    NSString *ext = d.url.pathExtension.lowercaseString;
    BOOL image = [@[@"png", @"jpg", @"jpeg", @"heic", @"gif", @"webp", @"tiff", @"bmp"] containsObject:ext];
    BOOL pdf = [ext isEqualToString:@"pdf"];
    BOOL video = [@[@"mp4", @"mov", @"m4v"] containsObject:ext];
    if (!image && !pdf && !video) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        UIImage *result = nil;
        @try {
            if (image) {
                CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)d.url, NULL);
                if (src) {
                    NSDictionary *opts = @{ (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES, (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
                                            (id)kCGImageSourceThumbnailMaxPixelSize: @160 };
                    CGImageRef cg = CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)opts);
                    if (cg) { result = [UIImage imageWithCGImage:cg]; CGImageRelease(cg); }
                    CFRelease(src);
                }
            } else if (pdf) {
                CGPDFDocumentRef doc = CGPDFDocumentCreateWithURL((__bridge CFURLRef)d.url);
                CGPDFPageRef page = doc ? CGPDFDocumentGetPage(doc, 1) : NULL;
                if (page) {
                    CGRect box = CGPDFPageGetBoxRect(page, kCGPDFCropBox);
                    CGFloat scale = 160.0 / MAX(box.size.width, box.size.height);
                    CGSize size = CGSizeMake(box.size.width * scale, box.size.height * scale);
                    result = [[[UIGraphicsImageRenderer alloc] initWithSize:size] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
                        [[UIColor whiteColor] setFill]; UIRectFill(CGRectMake(0, 0, size.width, size.height));
                        CGContextTranslateCTM(ctx.CGContext, 0, size.height);
                        CGContextScaleCTM(ctx.CGContext, scale, -scale);
                        CGContextTranslateCTM(ctx.CGContext, -box.origin.x, -box.origin.y);
                        CGContextDrawPDFPage(ctx.CGContext, page);
                    }];
                }
                if (doc) CGPDFDocumentRelease(doc);
            } else if (video) {
                AVAssetImageGenerator *gen = [[AVAssetImageGenerator alloc] initWithAsset:[AVURLAsset URLAssetWithURL:d.url options:nil]];
                gen.appliesPreferredTrackTransform = YES;
                gen.maximumSize = CGSizeMake(160, 160);
                CGImageRef cg = [gen copyCGImageAtTime:CMTimeMake(1, 2) actualTime:NULL error:NULL];
                if (cg) { result = [UIImage imageWithCGImage:cg]; CGImageRelease(cg); }
            }
        } @catch (NSException *e) { result = nil; }
        if (result) [DMThumbCache() setObject:result forKey:key];
        dispatch_async(dispatch_get_main_queue(), ^{ if (result) done(result); });
    });
}

static NSString *DMSizeText(DMDownload *d) {
    if (d.directory) return @"Folder";
    return [NSByteCountFormatter stringFromByteCount:d.size countStyle:NSByteCountFormatterCountStyleFile];
}
static NSString *DMAgeText(NSDate *date) {
    static NSRelativeDateTimeFormatter *f = nil;
    if (!f) { f = [NSRelativeDateTimeFormatter new]; f.unitsStyle = NSRelativeDateTimeFormatterUnitsStyleAbbreviated; f.dateTimeStyle = NSRelativeDateTimeFormatterStyleNumeric; }
    return [f localizedStringForDate:date relativeToDate:[NSDate date]];
}

#pragma mark - panel

@interface DMDownloadRow : UIControl
@property (nonatomic, strong) DMDownload *download;
@property (nonatomic, strong) UIImageView *thumb;
@end
@implementation DMDownloadRow
- (instancetype)initWithDownload:(DMDownload *)d width:(CGFloat)width {
    if (!(self = [super initWithFrame:CGRectMake(0, 0, width, 56)])) return nil;
    self.download = d;
    self.layer.cornerRadius = 10.0;
    self.thumb = [[UIImageView alloc] initWithFrame:CGRectMake(10, 6, 44, 44)];
    self.thumb.contentMode = UIViewContentModeScaleAspectFill;
    self.thumb.layer.cornerRadius = 7.0; self.thumb.clipsToBounds = YES;
    self.thumb.userInteractionEnabled = NO;
    UIColor *tint = nil;
    NSString *symbol = DMSymbolFor(d, &tint);
    self.thumb.contentMode = UIViewContentModeCenter;
    self.thumb.tintColor = tint;
    self.thumb.image = [UIImage systemImageNamed:symbol withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:26 weight:UIImageSymbolWeightRegular]];
    [self addSubview:self.thumb];
    __weak DMDownloadRow *weakSelf = self;
    DMLoadThumbnail(d, ^(UIImage *image) { weakSelf.thumb.contentMode = UIViewContentModeScaleAspectFill; weakSelf.thumb.image = image; weakSelf.thumb.backgroundColor = [UIColor clearColor]; });
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(64, 9, width - 64 - 12, 20)];
    title.text = d.url.lastPathComponent;
    title.font = [UIFont systemFontOfSize:14.5 weight:UIFontWeightMedium];
    title.textColor = [UIColor labelColor];
    title.lineBreakMode = NSLineBreakByTruncatingMiddle;
    title.userInteractionEnabled = NO;
    [self addSubview:title];
    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(64, 30, width - 64 - 12, 17)];
    sub.text = [NSString stringWithFormat:@"%@  ·  %@  ·  %@", d.source, DMSizeText(d), DMAgeText(d.date)];
    sub.font = [UIFont systemFontOfSize:12];
    sub.textColor = [UIColor secondaryLabelColor];
    sub.userInteractionEnabled = NO;
    [self addSubview:sub];
    return self;
}
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.backgroundColor = highlighted ? [UIColor colorWithWhite:0.5 alpha:0.28] : [UIColor clearColor];
}
@end

@interface DMDownloadsPanel : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
@property (nonatomic, strong) UIView *shield;
@property (nonatomic, strong) UITapGestureRecognizer *outsideTap;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) NSArray<DMDownloadSource *> *sources;
@property (nonatomic, weak) UIWindow *hostWindow;   // the Dock window, raised above MilkyWay's windows while the panel is open
@property (nonatomic) CGFloat savedLevel;
@property (nonatomic) BOOL presentedDockOurselves;   // whether WE told SBFloatingDockController to present the Dock (so we know whether it's ours to dismiss again)
- (BOOL)isOpen;
- (void)toggleFromIcon:(UIView *)icon;
- (void)dismissAnimated:(BOOL)animated;
- (void)debugTapFolder:(NSInteger)index;
- (void)startDockWatch;
- (void)touchBeganOnView:(UIView *)v;
@end

@implementation DMDownloadsPanel
static void DMFrontAppChangedCallback(CFNotificationCenterRef c, void *observer, CFNotificationName name, const void *object, CFDictionaryRef info) {
    DMDownloadsPanel *p = (__bridge DMDownloadsPanel *)observer;
    if ([p isOpen]) { DMLog([NSString stringWithFormat:@"[downloads] closes: %@", (__bridge NSString *)name]); [p dismissAnimated:YES]; }
}
+ (instancetype)shared {
    static DMDownloadsPanel *p; static dispatch_once_t once;
    dispatch_once(&once, ^{
        p = [DMDownloadsPanel new];
        // MacStatusBar posts this whenever the real frontmost app changes (very often a full-screen one) — closes the panel if it is
        // still open from a previous context, rather than leaving it anchored to a Dock icon that is no longer the reason to look at it.
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)p, DMFrontAppChangedCallback,
                                         CFSTR("com.besiktasliseba.dockmagnification/frontAppChanged"), NULL, CFNotificationSuspensionBehaviorCoalesce);
        // a tap or click in any app (MacAppBridge tells us; an app's own touches never pass through SpringBoard) closes the panel too, like a menu
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)p, DMFrontAppChangedCallback,
                                         CFSTR("com.besiktasliseba.appbridge.anytouch"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    });
    return p;
}
- (BOOL)isOpen { return self.panel.superview != nil; }

// MilkyWay's windows float at window level 1033, above the Dock window (25), and would cover the panel. While the panel is
// open the Dock window is raised above them (still below the Cover Sheet at 1050) and put back afterwards.
static const CGFloat kPanelWindowLevel = 1036.0;

// DOCK BUG #1 FIX: the alpha/hidden overrides above (gKeepDockVisible) were not enough on their own -- the Dock's
// icons could still vanish while a fully full-screen app (not windowed) was frontmost, because SBFloatingDockController
// itself tracks a separate "is the floating dock presented" state that governs more than just alpha/hidden, and our
// overrides never touched it. Found the real, intended mechanism instead of fighting it: SBFloatingDockController (the
// object SpringBoard itself already owns -- reached via SBIconController.sharedInstance's own "_floatingDockController"
// ivar, never alloc/init'd by us) exposes plain present/dismiss methods that ask IT to manage its own internal assertion,
// the exact same machinery Apple's own 3D Touch/folder-over-full-screen-app behaviour already uses successfully -- so this
// never creates an SBFloatingDockBehaviorAssertion ourselves (the thing that crashed SpringBoard twice tonight). Confirmed
// live before wiring this in: opened Safari full screen (isFloatingDockPresented=0, no Dock on screen), called
// -presentFloatingDockIfDismissedAnimated:completionHandler: and the Dock appeared ON TOP of Safari with NO blocking veil
// and Safari's own content still interactive-looking (cursor still blinking in the search field) -- unlike the native
// 3D Touch menu path the owner described, which does the same but blocks/freezes the app underneath. Called
// -dismissFloatingDockIfPresentedAnimated:completionHandler: afterwards and it cleanly reversed, dock gone, no crash,
// tested over several present/dismiss cycles with SpringBoard's PID unchanged throughout.
// iPadOS 15 keeps the one floating Dock controller in SBIconController's `_floatingDockController` ivar. iPadOS 16 has none there: each
// window scene makes its own (-[SBIconController createFloatingDockControllerForWindowScene:]) and hands it out as
// -[SBWindowScene floatingDockController]. Bug (iPad 2 on 16.7.7): tapping the Downloads icon resprung SpringBoard twice -- the old
// `valueForKey:@"_floatingDockController"` threw NSUnknownKeyException (valueForUndefinedKey:) on 16 and nothing caught it. Now the ivar is only
// read if it exists, then the Dock window's own scene is asked, and if neither answers the Dock-visibility step is simply skipped.
static id DMFloatingDockControllerObj(void) {
    Class icClass = objc_getClass("SBIconController");
    id ic = (icClass && [(id)icClass respondsToSelector:@selector(sharedInstance)]) ? ((id (*)(id, SEL))objc_msgSend)((id)icClass, @selector(sharedInstance)) : nil;
    if (ic) {
        Ivar iv = class_getInstanceVariable([ic class], "_floatingDockController");
        id ctrl = iv ? object_getIvar(ic, iv) : nil;
        if (ctrl) return ctrl;
    }
    SEL sceneCtrl = NSSelectorFromString(@"floatingDockController");
    Class dockWindowClass = objc_getClass("SBFloatingDockWindow");
    for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
        if (![sc isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)sc).windows) {
            if (dockWindowClass && ![w isKindOfClass:dockWindowClass]) continue;
            if ([sc respondsToSelector:sceneCtrl]) { id ctrl = ((id (*)(id, SEL))objc_msgSend)(sc, sceneCtrl); if (ctrl) return ctrl; }
        }
    }
    return nil;
}
static BOOL DMFloatingDockIsPresented(void) {
    id ctrl = DMFloatingDockControllerObj();
    SEL sel = @selector(isFloatingDockPresented);
    if (!ctrl || ![ctrl respondsToSelector:sel]) return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(ctrl, sel);
}
static void DMFloatingDockPresent(void) {
    id ctrl = DMFloatingDockControllerObj();
    SEL sel = @selector(presentFloatingDockIfDismissedAnimated:completionHandler:);
    if (!ctrl || ![ctrl respondsToSelector:sel]) return;
    ((void (*)(id, SEL, BOOL, id))objc_msgSend)(ctrl, sel, YES, ^{});
}
static void DMFloatingDockDismiss(void) {
    id ctrl = DMFloatingDockControllerObj();
    SEL sel = @selector(dismissFloatingDockIfPresentedAnimated:completionHandler:);
    if (!ctrl || ![ctrl respondsToSelector:sel]) return;
    ((void (*)(id, SEL, BOOL, id))objc_msgSend)(ctrl, sel, YES, ^{});
}

- (void)raiseHostWindow:(UIWindow *)window {
    if (!self.hostWindow) {
        self.hostWindow = window; self.savedLevel = window.windowLevel;
        self.presentedDockOurselves = !DMFloatingDockIsPresented();   // only ours to dismiss later if it wasn't already up (e.g. we're on the Home Screen)
        if (self.presentedDockOurselves) DMFloatingDockPresent();
    }
    if (window.windowLevel < kPanelWindowLevel) window.windowLevel = kPanelWindowLevel;
    extern BOOL gKeepDockVisible; gKeepDockVisible = YES;   // the Dock itself (not just this panel) must not auto-hide while browsing a full-screen app
}
- (void)restoreHostWindowIfIdle {
    if (self.panel || !self.hostWindow) return;   // a newer panel is open, or nothing was raised
    self.hostWindow.windowLevel = self.savedLevel;
    self.hostWindow = nil;
    extern BOOL gKeepDockVisible; gKeepDockVisible = NO;
    extern BOOL gDockHoverDismissBlocked; extern BOOL DMDockPointerHovering(void);
    if (self.presentedDockOurselves) { DMFloatingDockDismiss(); self.presentedDockOurselves = NO; }
    else if (gDockHoverDismissBlocked && !DMDockPointerHovering() && DMFloatingDockIsPresented()) {   // (the pointer had left the Dock while the panel
        DMLog(@"[downloads] panel closed with the pointer away from the Dock: the Dock goes, as SpringBoard wanted");   // was open: its dismissal now)
        DMFloatingDockDismiss();
    }
    gDockHoverDismissBlocked = NO;
}

// The panel and the Dock are one unit (2026-09-24): while the panel is open, it is checked 10 times a second that the Dock is still really on
// the screen -- SpringBoard's controller still presenting it, its platter inside the screen (the Dock leaves by sliding off, not only by fading, which
// our alpha/hidden guards never saw), visible, not under the Lock Screen / Cover Sheet. The moment it is not, the panel closes with it.
static BOOL DMDockReallyOnScreen(UIWindow *dockWindow) {
    if (!dockWindow || dockWindow.hidden || dockWindow.alpha < 0.05) return NO;
    if (DMFloatingDockControllerObj() && !DMFloatingDockIsPresented()) return NO;
    Class lockClass = objc_getClass("SBLockScreenManager");
    id lm = (lockClass && [(id)lockClass respondsToSelector:@selector(sharedInstance)]) ? ((id (*)(id, SEL))objc_msgSend)((id)lockClass, @selector(sharedInstance)) : nil;
    SEL locked = NSSelectorFromString(@"isUILocked");
    if (lm && [lm respondsToSelector:locked] && ((BOOL (*)(id, SEL))objc_msgSend)(lm, locked)) return NO;
    Class platterClass = objc_getClass("SBFloatingDockPlatterView");
    NSMutableArray *stack = [NSMutableArray arrayWithObject:dockWindow];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        if (platterClass && [v isKindOfClass:platterClass] && v.window) {
            CALayer *pl = v.layer.presentationLayer ?: v.layer;
            CGRect r = [v.superview convertRect:pl.frame toView:nil];   // (where it is drawn right now, mid-animation too)
            CGFloat alpha = 1.0; for (UIView *x = v; x; x = x.superview) alpha *= (x.layer.presentationLayer ?: x.layer).opacity * (x.hidden ? 0 : 1);
            CGRect screen = dockWindow.bounds;
            return alpha > 0.05 && CGRectGetMaxY(r) > 1.0 && CGRectGetMinY(r) < CGRectGetMaxY(screen) - 8.0 && CGRectIntersectsRect(r, screen);
        }
        [stack addObjectsFromArray:v.subviews];
    }
    return NO;
}
// The real front app (SpringBoard's own answer). MacStatusBar's tick also posts frontAppChanged, but it does not run with the stock status bar.
static NSString *DMDownloadsFrontBundle(void) {
    id sb = [UIApplication sharedApplication]; SEL s = NSSelectorFromString(@"_accessibilityFrontMostApplication");
    id app = [sb respondsToSelector:s] ? ((id (*)(id, SEL))objc_msgSend)(sb, s) : nil;
    return [app respondsToSelector:@selector(bundleIdentifier)] ? ([app bundleIdentifier] ?: @"") : @"";
}
// The App Switcher (iOS 15: SBMainSwitcherViewController, iOS 16: SBMainSwitcherControllerCoordinator). On the iPad the Dock stays on the screen in
// the App Switcher, so the Dock rule below never closed the panel: it stayed open on top of the switcher's cards and was still open after it (iPad 2,
// 26 Sep, layering audit row 20). The panel now closes when the switcher comes up, like the menus do.
static BOOL DMDownloadsSwitcherVisible(void) {
    id sw = nil;
    Class vc = objc_getClass("SBMainSwitcherViewController"), co = objc_getClass("SBMainSwitcherControllerCoordinator");
    SEL shared = @selector(sharedInstance), ifExists = NSSelectorFromString(@"sharedInstanceIfExists");
    if (vc && [(id)vc respondsToSelector:shared]) sw = ((id (*)(id, SEL))objc_msgSend)((id)vc, shared);
    else if (co && [(id)co respondsToSelector:ifExists]) sw = ((id (*)(id, SEL))objc_msgSend)((id)co, ifExists);
    for (NSString *name in @[@"isAnySwitcherVisible", @"isMainSwitcherVisible"]) {
        SEL sel = NSSelectorFromString(name);
        if ([sw respondsToSelector:sel] && ((BOOL (*)(id, SEL))objc_msgSend)(sw, sel)) return YES;
    }
    return NO;
}
- (void)startDockWatch {
    __weak DMDownloadsPanel *weakSelf = self;
    __block int misses = 0, switcherTicks = 0;
    CGSize openedIn = (self.hostWindow ?: self.panel.window).bounds.size;
    NSString *front = DMDownloadsFrontBundle();
    NSTimer *t = [NSTimer timerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *timer) {
        DMDownloadsPanel *me = weakSelf;
        if (!me || !me.panel) { [timer invalidate]; return; }
        CGSize now = (me.hostWindow ?: me.panel.window).bounds.size;
        if (!CGSizeEqualToSize(now, openedIn)) {   // turned: the Dock re-lays out and the panel would point at the wrong place
            DMLog(@"[downloads] the screen turned: the panel closes");
            [timer invalidate]; [me dismissAnimated:NO]; return;
        }
        if (![DMDownloadsFrontBundle() isEqualToString:front]) {   // another app came to the front
            DMLog(@"[downloads] the front app changed: the panel closes");
            [timer invalidate]; [me dismissAnimated:YES]; return;
        }
        if (!DMDownloadsSwitcherVisible()) switcherTicks = 0;
        else if (++switcherTicks >= 2) {   // (two ticks in a row, 0.2 s: not a passing reading)
            DMLog(@"[downloads] the App Switcher came up: the panel closes");
            [timer invalidate]; [me dismissAnimated:YES]; return;
        }
        if (DMDockReallyOnScreen(me.hostWindow ?: me.panel.window)) { misses = 0; return; }
        if (++misses < 2) return;   // (two ticks in a row: not a one-frame glitch)
        DMLog(@"[downloads] the Dock left the screen: the panel closes with it");
        [timer invalidate];
        [me dismissAnimated:YES];
    }];
    [[NSRunLoop mainRunLoop] addTimer:t forMode:NSRunLoopCommonModes];
}
- (void)dismissAnimated:(BOOL)animated {
    UIView *panel = self.panel, *shield = self.shield;
    UITapGestureRecognizer *outsideTap = self.outsideTap;
    self.panel = nil; self.shield = nil; self.outsideTap = nil;
    [shield removeFromSuperview];
    [outsideTap.view removeGestureRecognizer:outsideTap];
    if (!panel) { [self restoreHostWindowIfIdle]; return; }
    if (!animated) { [panel removeFromSuperview]; [self restoreHostWindowIfIdle]; return; }
    BOOL rm = MSBReduceMotion();   // (Reduce Motion: a fade with only a tiny scale)
    [UIView animateWithDuration:0.14 delay:0 options:rm ? UIViewAnimationOptionCurveEaseInOut : UIViewAnimationOptionCurveEaseIn animations:^{
        panel.alpha = 0.0; panel.transform = rm ? CGAffineTransformMakeScale(kMSBRMScale, kMSBRMScale) : CGAffineTransformMakeScale(0.94, 0.94);
    } completion:^(BOOL f) { [panel removeFromSuperview]; [self restoreHostWindowIfIdle]; }];
}

- (void)toggleFromIcon:(UIView *)icon {
    if ([self isOpen]) { DMLog(@"[downloads] closes: its icon was tapped again"); [self dismissAnimated:YES]; return; }
    UIWindow *window = icon.window;
    if (!window) return;
    __weak UIView *weakIcon = icon;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
        NSArray<DMDownloadSource *> *sources = DMSources();
        NSArray<DMDownload *> *items = DMScan(sources, 40);
#if DEBUG
        if (access("/tmp/dockmag-empty", F_OK) == 0) items = @[];   // (test: the panel as it looks with no downloads)
#endif
        DMLog([NSString stringWithFormat:@"[downloads] scan took %.2f s", CFAbsoluteTimeGetCurrent() - started]);
        dispatch_async(dispatch_get_main_queue(), ^{
            UIView *strongIcon = weakIcon;
            if (strongIcon.window && ![self isOpen]) [self presentItems:items sources:sources fromIcon:strongIcon];
        });
    });
}

- (void)presentItems:(NSArray<DMDownload *> *)items sources:(NSArray<DMDownloadSource *> *)sources fromIcon:(UIView *)icon {
    UIWindow *window = icon.window;
    self.sources = sources;
    [self raiseHostWindow:window];
    DMLog([NSString stringWithFormat:@"[downloads] panel with %lu items from %lu sources", (unsigned long)items.count, (unsigned long)sources.count]);

    // A tap anywhere dismisses the panel, but — unlike a Haptic Touch menu, which freezes the app behind it — nothing here blocks or
    // freezes the app: this is a plain, non-interactive UIView (not a UIControl swallowing touches), and the dismiss gesture itself has
    // cancelsTouchesInView = NO, so the very same touch still reaches the app underneath too (a scroll still scrolls, a button underneath
    // still responds), the tap only additionally also closes the panel.
    UIView *shield = [[UIView alloc] initWithFrame:window.bounds];
    shield.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    shield.userInteractionEnabled = NO;
    shield.backgroundColor = [UIColor clearColor];
    [window addSubview:shield];
    self.shield = shield;

    UITapGestureRecognizer *outsideTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(shieldTapped)];
    outsideTap.cancelsTouchesInView = NO;
    outsideTap.delegate = self;
    [window addGestureRecognizer:outsideTap];
    self.outsideTap = outsideTap;

    // A list that grows upward from the icon: newest at the bottom (closest to the icon), older ones above it, scrollable.
    // It gets as tall as the room above the Dock allows (never under the status bar), at most 10 rows before it scrolls.
    const CGFloat width = 360.0, pad = 8.0, rowH = 56.0, headerH = 42.0, gap = 14.0, footerH = 30.0;
    CGRect iconFrame = [icon.superview convertRect:icon.frame toView:window];
    CGFloat room = iconFrame.origin.y - gap - 54.0;   // 54: keeps clear of the status bar
    NSUInteger fit = (NSUInteger)MAX(1.0, floor((room - headerH - footerH - 2 * pad) / rowH));
    NSUInteger visible = items.count ? MIN(MIN(items.count, fit), 10) : 0;
    CGFloat listH = items.count ? visible * rowH : 64.0;
    CGFloat height = headerH + pad + listH + pad + footerH;
    CGFloat x = MIN(MAX(CGRectGetMidX(iconFrame) - width / 2.0, 12.0), window.bounds.size.width - width - 12.0);
    CGFloat y = iconFrame.origin.y - gap - height;

    UIVisualEffectView *panel = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterial]];
    panel.layer.cornerRadius = 18.0; panel.layer.cornerCurve = kCACornerCurveContinuous; panel.clipsToBounds = YES;
    panel.layer.borderWidth = 0.5; panel.layer.borderColor = [UIColor colorWithWhite:0.5 alpha:0.35].CGColor;
    UIView *content = panel.contentView;

    // header: one button per download folder (Safari, Reynard, ...)
    CGFloat count = sources.count, bw = (width - 2 * pad) / MAX(count, 1);
    for (NSUInteger k = 0; k < sources.count; k++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(pad + k * bw, 4, bw, headerH - 8);
        [b setTitle:[@" " stringByAppendingString:((DMDownloadSource *)sources[k]).name] forState:UIControlStateNormal];   // folder symbol + browser name
        [b setImage:[UIImage systemImageNamed:@"folder" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightMedium]] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        b.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        b.tag = (NSInteger)k;
        [b addTarget:self action:@selector(folderTapped:) forControlEvents:UIControlEventTouchUpInside];
        [content addSubview:b];
    }
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(pad, headerH - 0.5, width - 2 * pad, 0.5)];
    line.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.35];
    [content addSubview:line];

    NSMutableArray<UIView *> *rows = [NSMutableArray array];
    if (!items.count) {
        UILabel *empty = [[UILabel alloc] initWithFrame:CGRectMake(0, headerH + pad, width, 64)];
        empty.text = @"No recent downloads"; empty.textAlignment = NSTextAlignmentCenter;
        empty.font = [UIFont systemFontOfSize:14]; empty.textColor = [UIColor secondaryLabelColor];
        [content addSubview:empty];
    } else {
        UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(pad, headerH + pad, width - 2 * pad, listH)];
        scroll.showsVerticalScrollIndicator = YES; scroll.alwaysBounceVertical = YES;
        CGFloat rowW = width - 2 * pad;
        for (NSUInteger k = 0; k < items.count; k++) {
            // items are newest first; the newest goes at the bottom, next to the icon
            DMDownloadRow *row = [[DMDownloadRow alloc] initWithDownload:items[k] width:rowW];
            row.frame = CGRectMake(0, (items.count - 1 - k) * rowH, rowW, rowH);
            [row addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
            [scroll addSubview:row];
            if (k < visible) [rows addObject:row];
        }
        scroll.contentSize = CGSizeMake(rowW, items.count * rowH);
        scroll.contentOffset = CGPointMake(0, MAX(0.0, scroll.contentSize.height - listH));   // start at the newest
        [content addSubview:scroll];
    }

    // footer: a quiet "Downloads From..." link to the browser picker in Settings (like "Open in Finder" under a macOS stack)
    UIView *footLine = [[UIView alloc] initWithFrame:CGRectMake(pad, height - footerH, width - 2 * pad, 0.5)];
    footLine.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.35];
    [content addSubview:footLine];
    UIButton *from = [UIButton buttonWithType:UIButtonTypeSystem];
    [from setTitle:@"Downloads From\u2026" forState:UIControlStateNormal];
    from.titleLabel.font = [UIFont systemFontOfSize:13];
    [from setTitleColor:[UIColor secondaryLabelColor] forState:UIControlStateNormal];
    [from setTitleColor:[UIColor tertiaryLabelColor] forState:UIControlStateHighlighted];
    UIImage *gear = [UIImage systemImageNamed:@"gearshape" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightRegular]];   // (a small gear on the left: it opens Settings)
    if (gear) { [from setImage:gear forState:UIControlStateNormal]; from.tintColor = [UIColor secondaryLabelColor]; [from setTitle:@" Downloads From\u2026" forState:UIControlStateNormal]; }   // (a space between gear and text)
    [from sizeToFit];
    CGFloat fw = from.bounds.size.width + 16.0 + (gear ? 4.0 : 0.0);
    from.frame = CGRectMake(width - pad - fw, height - footerH + 1.0, fw, footerH - 2.0);
    from.pointerInteractionEnabled = YES;
    from.accessibilityIdentifier = @"DMDownloadsFrom";
    [from addTarget:self action:@selector(sourcesTapped:) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:from];

    panel.frame = CGRectMake(x, y, width, height);
    panel.alpha = 0.0;
    panel.layer.anchorPoint = CGPointMake((CGRectGetMidX(iconFrame) - x) / width, 1.0);
    panel.frame = CGRectMake(x, y, width, height);   // the anchor point moved the frame; put it back
    BOOL rm = MSBReduceMotion();   // (Reduce Motion: the panel fades in with only a tiny scale, the rows with it: no pop-up from the icon)
    panel.transform = rm ? CGAffineTransformMakeScale(kMSBRMScale, kMSBRMScale) : CGAffineTransformMakeScale(0.9, 0.9);
    [window addSubview:panel];
    self.panel = panel;
    [self startDockWatch];
    MSBAnimate(0.24, 0, 0.86, 0, ^{
        panel.alpha = 1.0; panel.transform = CGAffineTransformIdentity;
    }, nil);
    // the visible rows pop up one after another from the icon, newest first
    if (!rm) for (NSUInteger k = 0; k < rows.count; k++) {
        UIView *row = rows[k];
        row.alpha = 0.0; row.transform = CGAffineTransformMakeTranslation(0, 26.0 + 10.0 * k);
        [UIView animateWithDuration:0.26 delay:0.015 * k usingSpringWithDamping:0.88 initialSpringVelocity:0 options:0 animations:^{
            row.alpha = 1.0; row.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
}

- (void)debugTapFolder:(NSInteger)index {   // test helper: press the header button with this index
    UIView *found = nil;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:self.panel ?: [UIView new]];
    while (stack.count && !found) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        [stack addObjectsFromArray:v.subviews];
        if ([v isKindOfClass:[UIButton class]] && v.tag == index && [(UIButton *)v allTargets].count) found = v;
    }
    DMLog([NSString stringWithFormat:@"[downloads] debug folder tap %ld -> %@", (long)index, found ? @"pressing" : @"no button"]);
    if (found) [(UIControl *)found sendActionsForControlEvents:UIControlEventTouchUpInside];
}
- (void)shieldTapped { DMLog(@"[downloads] closes: a tap outside (the window's tap recogniser)"); [self dismissAnimated:YES]; }
- (void)touchBeganOnView:(UIView *)v {   // any touch in SpringBoard's own windows (Home Screen, other windows): outside the panel and its icon = close
    if (![self isOpen] || !v) return;
    if ([v isDescendantOfView:self.panel]) return;
    // SpringBoard's system-gesture window sees EVERY touch -- a finger anywhere, and a finger on the trackpad too -- alongside the window the
    // touch is really for: it said nothing about where the touch was, and closed the panel on a scroll inside it or a trackpad touch (M1).
    // Only touches in SpringBoard's own content windows count; touches in apps are reported by MacAppBridge.
    if ([NSStringFromClass([v.window class]) isEqualToString:@"_UISystemGestureWindow"]) return;
    for (UIView *x = v; x; x = x.superview) if ([NSStringFromClass([x class]) containsString:@"FloatingDock"]) return;   // (the Dock itself: its own icon toggles)
    DMLog([NSString stringWithFormat:@"[downloads] closes: a touch began on %@ in %@", NSStringFromClass([v class]), NSStringFromClass([v.window class])]);
    [self dismissAnimated:YES];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    // A tap that lands on the panel itself is a row/folder-button tap, not a dismiss — the panel's own buttons already handle it.
    CGPoint p = [touch locationInView:self.panel];
    return !CGRectContainsPoint(self.panel.bounds, p);
}
- (void)rowTapped:(DMDownloadRow *)row {
    DMLog(@"[downloads] closes: a file was picked");
    [self dismissAnimated:YES];
    DMOpenPath(row.download.url, row.download.viaFiles);
}
// "Downloads From...": closes the panel the way picking a file does, then Settings opens on Dock > Downloads From (the browser picker). The
// link is handled by our Dock row in Settings (DockSettingsRow.x), also when Settings is not running yet. Never while the screen is locked.
- (void)sourcesTapped:(UIButton *)b {
    DMLog(@"[downloads] closes: Downloads From was picked");
    [self dismissAnimated:YES];
    id lock = nil; Class lc = objc_getClass("SBLockScreenManager");
    if (lc && [(id)lc respondsToSelector:@selector(sharedInstance)]) lock = ((id (*)(id, SEL))objc_msgSend)((id)lc, @selector(sharedInstance));
    if ([lock respondsToSelector:NSSelectorFromString(@"isUILocked")] && ((BOOL (*)(id, SEL))objc_msgSend)(lock, NSSelectorFromString(@"isUILocked"))) {
        DMLog(@"[downloads] Downloads From: the screen is locked, Settings is not opened");
        return;
    }
    // Mac Status Bar running in this SpringBoard: it opens Settings full screen, then the link (see DMOpenSettingsLinkFullScreen); otherwise the link
    int alive = 0; uint64_t pid = 0;
    if (notify_register_check("com.besiktasliseba.macstatusbar.alive", &alive) == NOTIFY_STATUS_OK) { notify_get_state(alive, &pid); notify_cancel(alive); }
    if (pid == (uint64_t)getpid()) { DMLog(@"[downloads] Downloads From: Mac Status Bar opens Settings full screen"); notify_post("com.besiktasliseba.macstatusbaranddock.opendownloadsfrom"); return; }
    DMOpenURLString(@"prefs:root=DOCK_MAGNIFICATION&path=DOWNLOADS");
}
- (void)folderTapped:(UIButton *)b {
    DMLog(@"[downloads] closes: a folder was picked");
    DMDownloadSource *src = self.sources[(NSUInteger)b.tag];
    [self dismissAnimated:YES];
    DMOpenPath(src.folder, src.viaFiles);
}
@end

#pragma mark - the Dock icon

@interface DMDownloadsIconView : UIView <UIPointerInteractionDelegate>
@property (nonatomic, strong) UIImageView *image;
- (void)tapped;
@end
@implementation DMDownloadsIconView
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.image = [[UIImageView alloc] initWithFrame:self.bounds];
    self.image.contentMode = UIViewContentModeScaleAspectFit;
    self.image.userInteractionEnabled = NO;
    [self addSubview:self.image];
    [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];
    [self addInteraction:[[UIPointerInteraction alloc] initWithDelegate:self]];
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.image.frame = self.bounds;
    if (!self.image.image || !CGSizeEqualToSize(self.image.image.size, self.bounds.size)) self.image.image = DMFolderImage(self.bounds.size);
}
- (void)tapped { [[DMDownloadsPanel shared] toggleFromIcon:self]; }
- (UIPointerStyle *)pointerInteraction:(UIPointerInteraction *)interaction styleForRegion:(UIPointerRegion *)region {
    UITargetedPreview *preview = [[UITargetedPreview alloc] initWithView:self];
    return [UIPointerStyle styleWithEffect:[UIPointerLiftEffect effectWithPreview:preview] shape:nil];
}
@end

// ---- called from Tweak.x ----
void DMDownloadsAttach(UIView *platter, CGRect slot, BOOL show) {
    static const void *kKey = &kKey;
    DMDownloadsIconView *icon = objc_getAssociatedObject(platter, kKey);
    if (!show || slot.size.width < 8.0) {
        if (icon) icon.hidden = YES;
        if (!show && [[DMDownloadsPanel shared] isOpen]) { DMLog(@"[downloads] closes: the Downloads icon was switched off"); [[DMDownloadsPanel shared] dismissAnimated:NO]; }
        return;
    }
    if (!icon) {
        icon = [[DMDownloadsIconView alloc] initWithFrame:CGRectMake(0, 0, slot.size.width, slot.size.height)];
        objc_setAssociatedObject(platter, kKey, icon, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [platter addSubview:icon];
        // warm up the caches (LaunchServices lookups, the download folders) so the first tap does not wait
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ DMScan(DMSources(), 40); });
    }
    icon.hidden = NO;
    icon.transform = CGAffineTransformIdentity;   // hover magnification re-applies its own
    icon.bounds = CGRectMake(0, 0, slot.size.width, slot.size.height);
    icon.center = CGPointMake(CGRectGetMidX(slot), CGRectGetMidY(slot));
    [platter bringSubviewToFront:icon];
}
UIView *DMDownloadsIcon(UIView *platter) {
    static const void *kKey2 = NULL;
    (void)kKey2;
    Class c = [DMDownloadsIconView class];
    for (UIView *v in platter.subviews) if ([v isKindOfClass:c] && !v.hidden) return v;
    return nil;
}

#if DEBUG   // (test helpers: never in a release build)
// Test helper: `touch /tmp/dockmag-tap` taps the Downloads icon (there is no touch injection on the device). Polled once a second.
void DMDownloadsStartDebugPolling(void) {
    static dispatch_source_t timer;
    static time_t last = 0;
    timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), 1 * NSEC_PER_SEC, 200 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer, ^{
        struct stat st;
        if (stat("/tmp/dockmag-tap", &st) != 0 || st.st_mtimespec.tv_sec == last) return;
        last = st.st_mtimespec.tv_sec;
        for (UIWindow *w in [UIWindow allWindowsIncludingInternalWindows:YES onlyVisibleWindows:NO]) {
            if (![NSStringFromClass([w class]) isEqualToString:@"SBFloatingDockWindow"]) continue;
            NSMutableArray *stack = [NSMutableArray arrayWithObject:w];
            while (stack.count) {
                UIView *v = stack.lastObject; [stack removeLastObject];
                [stack addObjectsFromArray:v.subviews];
                if ([v isKindOfClass:[DMDownloadsIconView class]]) { DMLog(@"[downloads] debug tap"); [(DMDownloadsIconView *)v tapped]; return; }
            }
        }
        DMLog(@"[downloads] debug tap: icon not found");
    });
    dispatch_resume(timer);

    // stall detector: logs whenever the main thread was blocked for more than 0.4 s
    static dispatch_source_t beat;
    static CFAbsoluteTime lastBeat = 0;
    beat = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(beat, dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), 100 * NSEC_PER_MSEC, 20 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(beat, ^{
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (lastBeat > 0 && now - lastBeat > 0.4) DMLog([NSString stringWithFormat:@"[stall] the main thread was blocked for %.2f s", now - lastBeat]);
        lastBeat = now;
    });
    dispatch_resume(beat);
    // `echo N > /tmp/dockmag-folder` presses header button N of the open panel
    static dispatch_source_t folderTimer;
    static time_t lastFolder = 0;
    folderTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(folderTimer, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), 1 * NSEC_PER_SEC, 200 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(folderTimer, ^{
        struct stat st;
        if (stat("/tmp/dockmag-folder", &st) != 0 || st.st_mtimespec.tv_sec == lastFolder) return;
        lastFolder = st.st_mtimespec.tv_sec;
        FILE *f = fopen("/tmp/dockmag-folder", "r"); int n = 0; if (f) { if (fscanf(f, "%d", &n) != 1) n = 0; fclose(f); }
        [[DMDownloadsPanel shared] debugTapFolder:n];
    });
    dispatch_resume(folderTimer);
}
#endif

BOOL DMDownloadsPanelContainsTouch(UITouch *touch) {
    DMDownloadsPanel *p = [DMDownloadsPanel shared];
    if (![p isOpen] || !touch) return NO;
    UIView *panel = p.panel;
    CGPoint s = [touch locationInView:nil];   // (the touch's own window coordinates)
    CGPoint inPanel = [panel convertPoint:[touch.window convertPoint:s toCoordinateSpace:touch.window.screen.coordinateSpace] fromCoordinateSpace:panel.window.screen.coordinateSpace];
    return CGRectContainsPoint(CGRectInset(panel.bounds, -8.0, -8.0), inPanel);
}
void DMDownloadsTouchBegan(UIView *view) { [[DMDownloadsPanel shared] touchBeganOnView:view]; }
