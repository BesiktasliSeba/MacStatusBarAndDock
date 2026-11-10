// MSBWallpaperController -- Settings > Desktop > Desktop Picture (1.8.6, KT 9-10 Nov): a gallery like a Mac's Wallpaper settings. The picture
// shows behind the first Home Screen page only (statusbar/DesktopWallpaper.h); the rules shared with SpringBoard are common/DesktopWallpaper.h's.
//  - "None" first (the default: nothing of ours is drawn), then the picture last chosen from Photos (when there is one) and Choose from Photos;
//    Mac Wallpapers: every picture in On My iPad > MacStatusBar&Dock > Wallpapers (made here when missing), by file name, and Add from Files;
//    iPadOS's still wallpapers found on this iPad. We ship no pictures: a Mac's wallpapers are Apple's. From a Mac: AirDrop the picture to the
//    iPad, save it in that folder (or it lands in Photos), then pick it here -- or Add from Files copies any picture into the folder and picks it.
//  - A tap chooses: the three preference values written, SpringBoard told (kMSBDWallpaperNotify). The choice in force is ticked (a blue ring and a
//    check mark, as on a Mac); a path SpringBoard would not show (the crash guard's "none") reads as None.
//  - Photos: the system's own picker (PHPickerViewController: it runs outside Settings and gives only the one picture picked; no access to the
//    library is asked for). The picture is copied, made only as large as the screen needs (its short side the screen's long side, in pixels), as
//    a JPEG beside our files in the preferences folder, under a new name each time (SpringBoard then reads the new one); the copy before is removed.
//  - Add from Files: the system's document picker, as a copy (only the picked file is given); the copy goes into the Mac Wallpapers folder under
//    its own name (or "<name> 2"...), then it is chosen.
//  - Thumbnails: ImageIO's (a HEIC's primary picture: a Mac's dynamic wallpapers hold several), small, made off the main thread, kept in memory and
//    in our cache folder (by path, size and date, so a changed file gets a new one).
#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <CommonCrypto/CommonDigest.h>
#import <notify.h>
#import <Preferences/PSViewController.h>
#import "../../common/DesktopWallpaper.h"

#define kWPDomain CFSTR("com.besiktasliseba.macstatusbar")

@interface MSBWallpaperCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *picture;
@property (nonatomic, strong) UILabel *name, *glyph;
@property (nonatomic, strong) UIImageView *check;
@property (nonatomic, copy) NSString *itemID;
- (void)msb_setChosen:(BOOL)on;
@end
@implementation MSBWallpaperCell
- (instancetype)initWithFrame:(CGRect)f {
	if (!(self = [super initWithFrame:f])) return nil;
	_picture = [UIImageView new];
	_picture.contentMode = UIViewContentModeScaleAspectFill; _picture.clipsToBounds = YES;
	_picture.layer.cornerRadius = 9.0; _picture.layer.cornerCurve = kCACornerCurveContinuous;
	_picture.backgroundColor = [UIColor tertiarySystemFillColor];
	_picture.layer.borderColor = [UIColor systemBlueColor].CGColor;
	_glyph = [UILabel new]; _glyph.textAlignment = NSTextAlignmentCenter; _glyph.textColor = [UIColor secondaryLabelColor];
	_glyph.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium]; _glyph.numberOfLines = 2;
	_name = [UILabel new]; _name.textAlignment = NSTextAlignmentCenter; _name.font = [UIFont systemFontOfSize:13]; _name.textColor = [UIColor labelColor];
	_name.adjustsFontSizeToFitWidth = YES; _name.minimumScaleFactor = 0.8;
	_check = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle.fill"]];
	_check.tintColor = [UIColor systemBlueColor]; _check.backgroundColor = [UIColor whiteColor]; _check.layer.cornerRadius = 10.0; _check.clipsToBounds = YES;
	for (UIView *v in @[_picture, _glyph, _name, _check]) [self.contentView addSubview:v];
	self.isAccessibilityElement = YES;
	self.accessibilityTraits = UIAccessibilityTraitButton;
	return self;
}
- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat w = self.contentView.bounds.size.width, ph = round(w * 0.66);
	_picture.frame = CGRectMake(0, 0, w, ph);
	_glyph.frame = CGRectInset(_picture.frame, 6, 6);
	_name.frame = CGRectMake(0, ph + 6, w, 18);
	_check.frame = CGRectMake(w - 26, ph - 26, 20, 20);
}
- (void)msb_setChosen:(BOOL)on {
	_picture.layer.borderWidth = on ? 3.0 : 0.0;
	_check.hidden = !on;
	self.accessibilityTraits = UIAccessibilityTraitButton | (on ? UIAccessibilityTraitSelected : 0);
}
- (void)prepareForReuse { [super prepareForReuse]; _picture.image = nil; _picture.contentMode = UIViewContentModeScaleAspectFill; _glyph.text = nil; _itemID = nil; }
@end

@interface MSBWallpaperController : PSViewController <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, PHPickerViewControllerDelegate, UIDocumentPickerDelegate>
@end

@implementation MSBWallpaperController {
	UICollectionView *_grid;
	NSArray<NSArray<NSDictionary *> *> *_sections;   // (each item: id, name, path [, dark, thumb, kind])
	NSArray<NSString *> *_titles;
	NSCache<NSString *, UIImage *> *_thumbs;
	NSString *_chosenID;
	BOOL _picking;
	NSArray<NSDictionary *> *_stills;          // (iPadOS's stills: scanned once per page, off the main thread -- review 1.8.6 L6)
	NSMutableSet<NSString *> *_thumbsInFlight; // (a thumbnail being made: not asked for again -- L5)
}

// ---- what there is ----
static NSString *WPPhotoNow(void) {   // (the copy of the picture last chosen from Photos, newest first)
	NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:kMSBDWallpaperPhotoDir error:nil];
	NSString *best = nil;
	for (NSString *f in files) if ([f hasPrefix:kMSBDWallpaperPhotoPrefix] && [f.pathExtension.lowercaseString isEqualToString:@"jpg"] && (!best || [f compare:best] == NSOrderedDescending)) best = f;
	return best ? [kMSBDWallpaperPhotoDir stringByAppendingPathComponent:best] : nil;
}
static NSArray<NSString *> *WPFilesUnder(NSString *dir, int depth) {   // (full paths of the files under dir, a few levels down)
	NSMutableArray *out = [NSMutableArray array];
	NSFileManager *fm = [NSFileManager defaultManager];
	for (NSString *f in [fm contentsOfDirectoryAtPath:dir error:nil]) {
		NSString *p = [dir stringByAppendingPathComponent:f];
		BOOL isDir = NO;
		if (![fm fileExistsAtPath:p isDirectory:&isDir]) continue;
		if (isDir && depth > 0) [out addObjectsFromArray:WPFilesUnder(p, depth - 1)];
		else if (!isDir) [out addObject:p];
	}
	return out;
}
// iPadOS's own stills: every .wallpaper bundle under /Library/Wallpaper whose pictures are one picture (or one in light and dark); of the same
// wallpaper in several sizes, the one made for this screen (MSBDWallpaperBetterFit).
static NSArray<NSDictionary *> *WPSystemStills(void) {
	NSMutableArray *bundles = [NSMutableArray array];
	NSMutableArray *todo = [NSMutableArray arrayWithObject:kMSBDWallpaperSystemDir];
	NSFileManager *fm = [NSFileManager defaultManager];
	for (int depth = 0; depth < 5 && todo.count; depth++) {
		NSMutableArray *next = [NSMutableArray array];
		for (NSString *d in todo) for (NSString *f in [fm contentsOfDirectoryAtPath:d error:nil]) {
			NSString *p = [d stringByAppendingPathComponent:f];
			BOOL isDir = NO;
			if (![fm fileExistsAtPath:p isDirectory:&isDir] || !isDir) continue;
			if ([f.pathExtension isEqualToString:@"wallpaper"]) [bundles addObject:p]; else [next addObject:p];
		}
		todo = next;
	}
	CGSize pts = [UIScreen mainScreen].bounds.size;
	NSMutableDictionary<NSString *, NSString *> *byName = [NSMutableDictionary dictionary];
	NSMutableDictionary<NSString *, NSArray *> *stills = [NSMutableDictionary dictionary];
	for (NSString *b in [bundles sortedArrayUsingSelector:@selector(compare:)]) {
		NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[b stringByAppendingPathComponent:@"Wallpaper.plist"]];
		NSArray *still = MSBDWallpaperStillFromInfo(info, b, [fm contentsOfDirectoryAtPath:b error:nil] ?: @[]);   // (15/16: the bundle's plist names its pictures)
		if (!still) info = nil;   // (17+: its plist names no picture files; its name is taken from the bundle as before)
		if (!still) still = MSBDWallpaperStill(WPFilesUnder(b, 3));   // (17+: the Core Animation package's pictures)
		if (!still) continue;   // (layered, drawn by code, or only its thumbnail on the iPad: not offered)
		{   // (a small picture is a texture of a drawn wallpaper, not one to show on a screen: review 1.8.6 L3)
			CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:still[0]], NULL);
			NSDictionary *props = src ? CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(src, CGImageSourceGetPrimaryImageIndex(src), NULL)) : nil;
			if (src) CFRelease(src);
			if (MAX([props[(id)kCGImagePropertyPixelWidth] doubleValue], [props[(id)kCGImagePropertyPixelHeight] doubleValue]) < 1000.0) continue;
		}
		NSString *name = [info[@"name"] isKindOfClass:[NSString class]] && [info[@"name"] length] ? info[@"name"] : MSBDWallpaperDisplayName(b);
		if (!name.length || !MSBDWallpaperBetterFit(b, byName[name], pts.width, pts.height)) continue;
		byName[name] = b; stills[name] = still;
	}
	NSMutableArray *out = [NSMutableArray array];
	for (NSString *name in [byName.allKeys sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
		NSArray *s = stills[name];
		NSMutableDictionary *d = [@{@"id": [@"ios:" stringByAppendingString:s[0]], @"name": name, @"path": s[0]} mutableCopy];
		if (s.count > 1) d[@"dark"] = s[1];
		[out addObject:d];
	}
	return out;
}
static NSString *WPMacDir(BOOL make) {   // (the Mac Wallpapers folder; made, with MacStatusBar&Dock around it, when asked and missing)
	NSString *d = MSBDWallpaperMacDir();
	if (!d) return nil;
	BOOL isDir = NO;
	if ([[NSFileManager defaultManager] fileExistsAtPath:d isDirectory:&isDir]) return isDir ? d : nil;
	if (!make || ![[NSFileManager defaultManager] createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil]) return nil;
	return d;
}
static NSArray<NSDictionary *> *WPMac(void) {
	NSString *d = WPMacDir(YES);
	NSMutableArray *out = [NSMutableArray array];
	for (NSString *f in MSBDWallpaperMacList([[NSFileManager defaultManager] contentsOfDirectoryAtPath:d error:nil] ?: @[]))
		[out addObject:@{@"id": [@"mac:" stringByAppendingString:f], @"name": MSBDWallpaperMacName(f), @"path": [d stringByAppendingPathComponent:f]}];
	return out;
}
- (void)msb_reload {
	NSMutableArray *first = [NSMutableArray arrayWithObject:@{@"id": @"none", @"name": @"None", @"kind": @"none"}];
	NSString *photo = WPPhotoNow();
	if (photo) [first addObject:@{@"id": @"photo", @"name": @"Your Photo", @"path": photo}];
	[first addObject:@{@"id": @"pick", @"name": @"Choose from Photos", @"kind": @"pick"}];
	NSMutableArray *sections = [NSMutableArray arrayWithObject:first], *titles = [NSMutableArray arrayWithObject:@""];
	NSMutableArray *mac = [WPMac() mutableCopy];
	[mac addObject:@{@"id": @"add", @"name": @"Add from Files", @"kind": @"add"}];
	[sections addObject:mac]; [titles addObject:@"Mac Wallpapers"];
	NSArray *ios = _stills;   // (nil until the scan is in: msb_reload runs again then)
	if (ios.count) { [sections addObject:ios]; [titles addObject:@"iPadOS"]; }
	_sections = sections; _titles = titles;
	CFPreferencesAppSynchronize(kWPDomain);
	CFPropertyListRef p = CFPreferencesCopyAppValue(CFSTR(kMSBDWallpaperPathKey), kWPDomain), i = CFPreferencesCopyAppValue(CFSTR(kMSBDWallpaperIDKey), kWPDomain);
	NSString *path = p && CFGetTypeID(p) == CFStringGetTypeID() ? (__bridge NSString *)p : nil, *ident = i && CFGetTypeID(i) == CFStringGetTypeID() ? (__bridge NSString *)i : nil;
	_chosenID = MSBDWallpaperPathAllowed(path) ? (ident ?: @"none") : @"none";   // (what SpringBoard shows decides: a refused path is None)
	_chosenID = [_chosenID copy];
	if (p) CFRelease(p);
	if (i) CFRelease(i);
	[_grid reloadData];
}

// A thumbnail: from our cache folder when the file is unchanged, else made by ImageIO (the primary picture, 360 px) and kept there.
#define kWPThumbDir @"/var/jb/var/mobile/Library/Caches/com.besiktasliseba.macstatusbar.wallpapers"
static UIImage *WPThumb(NSString *src) {
	if (![src isKindOfClass:[NSString class]] || !src.length) return nil;   // (w01 on the 17.5: the Add from Files tile reached here without a path and Settings stopped)
	NSDictionary *a = [[NSFileManager defaultManager] attributesOfItemAtPath:src error:nil];
	NSString *key = [NSString stringWithFormat:@"%@|%llu|%.0f", src, [a fileSize], [[a fileModificationDate] timeIntervalSince1970]];
	unsigned char h[CC_SHA1_DIGEST_LENGTH]; NSData *kd = [key dataUsingEncoding:NSUTF8StringEncoding];
	CC_SHA1(kd.bytes, (CC_LONG)kd.length, h);
	NSMutableString *hex = [NSMutableString string]; for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", h[i]];
	NSString *cached = [kWPThumbDir stringByAppendingPathComponent:[hex stringByAppendingString:@".jpg"]];
	UIImage *t = [UIImage imageWithContentsOfFile:cached];
	if (t) return t;
	CGImageSourceRef s = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:src], NULL);
	if (!s) return nil;
	size_t at = CGImageSourceGetPrimaryImageIndex(s);
	NSDictionary *props = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(s, at, NULL));
	CGSize sp = [UIScreen mainScreen].nativeBounds.size;   // (the screen's pixels: a square only as large as its long side is shown Fill Screen, L3)
	BOOL turnable = MSBDWallpaperIsTurnable(src, [props[(id)kCGImagePropertyPixelWidth] doubleValue], [props[(id)kCGImagePropertyPixelHeight] doubleValue], sp.width, sp.height);
	NSDictionary *o = @{(id)kCGImageSourceCreateThumbnailFromImageAlways: @YES, (id)kCGImageSourceCreateThumbnailWithTransform: @YES, (id)kCGImageSourceThumbnailMaxPixelSize: @(turnable ? 510 : 360)};
	CGImageRef r = CGImageSourceCreateThumbnailAtIndex(s, at, (__bridge CFDictionaryRef)o);
	CFRelease(s);
	if (!r) return nil;
	if (turnable) {   // (iPadOS's turnable square: its black corners are never shown -- the square inside the circle, as SpringBoard shows it)
		CGRect in = MSBDWallpaperCircleRect(CGImageGetWidth(r), 1, 1);
		CGImageRef c = CGImageCreateWithImageInRect(r, in);
		CGImageRelease(r);
		if (!c) return nil;
		r = c;
	}
	t = [UIImage imageWithCGImage:r];
	CGImageRelease(r);
	[[NSFileManager defaultManager] createDirectoryAtPath:kWPThumbDir withIntermediateDirectories:YES attributes:nil error:nil];
	[UIImageJPEGRepresentation(t, 0.85) writeToFile:cached atomically:YES];
	return t;
}

// ---- the page ----
- (void)loadView {
	UICollectionViewFlowLayout *l = [UICollectionViewFlowLayout new];
	l.minimumInteritemSpacing = 16; l.minimumLineSpacing = 18;
	l.sectionInset = UIEdgeInsetsMake(8, 20, 20, 20);
	l.headerReferenceSize = CGSizeMake(0, 34);
	_grid = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:l];
	_grid.backgroundColor = [UIColor systemGroupedBackgroundColor];
	_grid.dataSource = self; _grid.delegate = self;
	_grid.alwaysBounceVertical = YES;
	[_grid registerClass:[MSBWallpaperCell class] forCellWithReuseIdentifier:@"w"];
	[_grid registerClass:[UICollectionReusableView class] forSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:@"h"];
	[_grid registerClass:[UICollectionReusableView class] forSupplementaryViewOfKind:UICollectionElementKindSectionFooter withReuseIdentifier:@"f"];
	self.view = _grid;
}
- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Desktop Picture";
	_thumbs = [NSCache new];
	_thumbsInFlight = [NSMutableSet set];
	__weak MSBWallpaperController *ws = self;   // (iPadOS's folders walked once, off the main thread; the page shows the rest at once -- L6)
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSArray *stills = WPSystemStills();
		dispatch_async(dispatch_get_main_queue(), ^{ MSBWallpaperController *s2 = ws; if (!s2) return; s2->_stills = stills; if (!s2->_picking) [s2 msb_reload]; });
	});
}   // (the first msb_reload is viewWillAppear's: once, not twice -- L6)
- (void)viewWillAppear:(BOOL)a { [super viewWillAppear:a]; if (!_picking) [self msb_reload]; }
- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)cv { return _sections.count; }
- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s { return _sections[s].count; }
- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)l sizeForItemAtIndexPath:(NSIndexPath *)ip {
	CGFloat avail = cv.bounds.size.width - 40, w = 150;
	NSInteger n = MAX(2, (NSInteger)floor((avail + 16) / (w + 16)));
	w = MAX(1.0, floor((avail - 16 * (n - 1)) / n));   // (never zero or negative, before the page has its width: review 1.8.6 L12)
	return CGSizeMake(w, round(w * 0.66) + 28);
}
- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)l referenceSizeForFooterInSection:(NSInteger)s {
	return (s == 0 || [_titles[s] isEqualToString:@"Mac Wallpapers"]) ? CGSizeMake(cv.bounds.size.width, 52) : CGSizeZero;
}
- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)l referenceSizeForHeaderInSection:(NSInteger)s {
	return _titles[s].length ? CGSizeMake(cv.bounds.size.width, 34) : CGSizeMake(cv.bounds.size.width, 8);
}
- (UICollectionReusableView *)collectionView:(UICollectionView *)cv viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)ip {
	BOOL header = [kind isEqualToString:UICollectionElementKindSectionHeader];
	UICollectionReusableView *v = [cv dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:header ? @"h" : @"f" forIndexPath:ip];
	UILabel *t = (UILabel *)[v viewWithTag:7];
	if (!t) { t = [UILabel new]; t.tag = 7; t.numberOfLines = 0; [v addSubview:t]; }
	if (header) {
		t.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular]; t.textColor = [UIColor secondaryLabelColor];
		t.text = _titles[ip.section].uppercaseString;
		t.frame = CGRectMake(22, 10, v.bounds.size.width - 44, 20);
	} else {
		t.font = [UIFont systemFontOfSize:13]; t.textColor = [UIColor secondaryLabelColor];
		t.text = ip.section == 0 ? @"The picture shows behind the first page of the Home Screen, where the desktop is. The other pages keep your iPadOS wallpaper."
		                         : @"Pictures in On My iPad > MacStatusBar&Dock > Wallpapers. Add your Mac's wallpapers there with the Files app, AirDrop or Add from Files.";
		t.frame = CGRectMake(22, 0, v.bounds.size.width - 44, 48);
	}
	return v;
}
- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
	MSBWallpaperCell *c = [cv dequeueReusableCellWithReuseIdentifier:@"w" forIndexPath:ip];
	NSDictionary *it = _sections[ip.section][ip.item];
	c.itemID = it[@"id"];
	c.name.text = it[@"name"];
	c.accessibilityLabel = it[@"name"];
	[c msb_setChosen:[it[@"id"] isEqualToString:_chosenID]];
	if ([it[@"kind"] isEqualToString:@"none"]) { c.glyph.text = @"None"; c.name.text = @""; }
	else if ([it[@"kind"] isEqualToString:@"pick"] || [it[@"kind"] isEqualToString:@"add"]) {   // (Choose from Photos, Add from Files: buttons, never ticked)
		c.glyph.text = nil;
		c.picture.image = [UIImage systemImageNamed:[it[@"kind"] isEqualToString:@"pick"] ? @"photo.on.rectangle.angled" : @"folder.badge.plus" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:30]];
		c.picture.contentMode = UIViewContentModeCenter; c.picture.tintColor = [UIColor systemBlueColor];
		[c msb_setChosen:NO];
	} else {
		c.picture.contentMode = UIViewContentModeScaleAspectFill;
		NSString *dark = it[@"dark"], *src = (dark && self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) ? dark : it[@"path"];
		UIImage *img = src ? [_thumbs objectForKey:src] : nil;
		if (img || !src) c.picture.image = img;   // (an item always has its path; none: nothing to draw)
		else if (![_thumbsInFlight containsObject:src]) {   // (one at a time on one queue, each path once: review 1.8.6 L5 -- a folder of large HEICs)
			static dispatch_queue_t q; static dispatch_once_t once;
			dispatch_once(&once, ^{ q = dispatch_queue_create("com.besiktasliseba.macstatusbar.wallpaper-thumbs", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0)); });
			[_thumbsInFlight addObject:src];
			__weak MSBWallpaperController *ws = self;
			dispatch_async(q, ^{
				UIImage *t = WPThumb(src);
				dispatch_async(dispatch_get_main_queue(), ^{
					MSBWallpaperController *s2 = ws; if (!s2) return;
					[s2->_thumbsInFlight removeObject:src];
					if (!t) return;
					[s2->_thumbs setObject:t forKey:src];
					for (MSBWallpaperCell *vc in s2->_grid.visibleCells) {   // (every cell showing that picture now, whichever asked)
						NSIndexPath *vip = [s2->_grid indexPathForCell:vc];
						if (!vip || vip.section >= (NSInteger)s2->_sections.count || vip.item >= (NSInteger)s2->_sections[vip.section].count) continue;
						NSDictionary *vit = s2->_sections[vip.section][vip.item];
						NSString *vd = vit[@"dark"], *vsrc = (vd && s2.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) ? vd : vit[@"path"];
						if ([vsrc isEqualToString:src]) vc.picture.image = t;
					}
				});
			});
		}
	}
	return c;
}

// ---- choosing ----
// The choice written and SpringBoard told: the id it is ticked by, and the paths ("none" or a refused path: all three removed). A static function, so
// a Photos pick that finishes after the page has gone is still written (review 1.8.6 L4). Returns the id in force.
static NSString *WPWriteChoice(NSString *ident, NSString *path, NSString *dark) {
	if ([ident isEqualToString:@"none"] || !MSBDWallpaperPathAllowed(path)) {
		CFPreferencesSetAppValue(CFSTR(kMSBDWallpaperIDKey), NULL, kWPDomain);
		CFPreferencesSetAppValue(CFSTR(kMSBDWallpaperPathKey), NULL, kWPDomain);
		CFPreferencesSetAppValue(CFSTR(kMSBDWallpaperDarkKey), NULL, kWPDomain);
		ident = @"none";
	} else {
		CFPreferencesSetAppValue(CFSTR(kMSBDWallpaperIDKey), (__bridge CFStringRef)ident, kWPDomain);
		CFPreferencesSetAppValue(CFSTR(kMSBDWallpaperPathKey), (__bridge CFStringRef)path, kWPDomain);
		CFPreferencesSetAppValue(CFSTR(kMSBDWallpaperDarkKey), MSBDWallpaperPathAllowed(dark) ? (__bridge CFStringRef)dark : NULL, kWPDomain);
	}
	CFPreferencesAppSynchronize(kWPDomain);
	notify_post(kMSBDWallpaperNotify);
	return ident;
}
// The copies from Photos other than the one in force removed (only once the choice points at the new one: L4).
static void WPRemoveOldPhotos(NSString *keep) {
	for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:kMSBDWallpaperPhotoDir error:nil])
		if ([f hasPrefix:kMSBDWallpaperPhotoPrefix] && ![f isEqualToString:keep.lastPathComponent]) [[NSFileManager defaultManager] removeItemAtPath:[kMSBDWallpaperPhotoDir stringByAppendingPathComponent:f] error:nil];
}
- (void)msb_choose:(NSDictionary *)it {
	_chosenID = [WPWriteChoice(it[@"id"], it[@"path"], it[@"dark"]) copy];
	[_grid layoutIfNeeded];   // (the visible cells as the data is now, after a reloadData just before: review 1.8.6 L13)
	for (MSBWallpaperCell *c in _grid.visibleCells) {
		NSIndexPath *ip = [_grid indexPathForCell:c];
		if (!ip || ip.section >= (NSInteger)_sections.count || ip.item >= (NSInteger)_sections[ip.section].count) continue;
		NSDictionary *x = _sections[ip.section][ip.item];
		NSString *kind = x[@"kind"];   // (the two buttons are never ticked; None is: review 1.8.6 L2)
		[c msb_setChosen:[x[@"id"] isEqualToString:_chosenID] && ![kind isEqualToString:@"pick"] && ![kind isEqualToString:@"add"]];
	}
}
- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
	[cv deselectItemAtIndexPath:ip animated:NO];
	NSDictionary *it = _sections[ip.section][ip.item];
	if ([it[@"kind"] isEqualToString:@"pick"]) { [self msb_pickPhoto]; return; }
	if ([it[@"kind"] isEqualToString:@"add"]) { [self msb_addFromFiles]; return; }
	[self msb_choose:it];
}
- (void)msb_pickPhoto {
	PHPickerConfiguration *cfg = [PHPickerConfiguration new];   // (no photo library: the picker gives only the picture picked)
	cfg.filter = [PHPickerFilter imagesFilter];
	cfg.selectionLimit = 1;
	PHPickerViewController *p = [[PHPickerViewController alloc] initWithConfiguration:cfg];
	p.delegate = self;
	_picking = YES;
	[self presentViewController:p animated:YES completion:nil];
}
- (void)msb_addFromFiles {
	UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeImage] asCopy:YES];   // (a copy of the one file picked)
	p.delegate = self;
	p.allowsMultipleSelection = NO;
	_picking = YES;
	[self presentViewController:p animated:YES completion:nil];
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)c { _picking = NO; }
- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
	_picking = NO;
	NSURL *u = urls.firstObject;
	NSString *dir = WPMacDir(YES);
	if (!u || !dir || !MSBDWallpaperIsPictureFile(u.lastPathComponent)) return;
	NSString *name = MSBDWallpaperImportName(u.lastPathComponent, [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil] ?: @[]);
	NSString *to = [dir stringByAppendingPathComponent:name];
	if (![[NSFileManager defaultManager] copyItemAtPath:u.path toPath:to error:nil]) return;
	[self msb_reload];
	[self msb_choose:@{@"id": [@"mac:" stringByAppendingString:name], @"name": MSBDWallpaperMacName(name), @"path": to}];
}
// The copy: as large as the screen needs -- the picture's short side the screen's long side in pixels, so it fills the screen turned either way --,
// never larger than it was; a JPEG under a new name; the one before removed once the choice points at the new one (WPRemoveOldPhotos).
static NSString *WPCopyPhoto(NSURL *url) {
	CGImageSourceRef s = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
	if (!s) return nil;
	size_t at = CGImageSourceGetPrimaryImageIndex(s);   // (a Mac's dynamic wallpaper holds several pictures: its primary one)
	NSDictionary *props = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(s, at, NULL));
	double iw = [props[(id)kCGImagePropertyPixelWidth] doubleValue], ih = [props[(id)kCGImagePropertyPixelHeight] doubleValue];
	CGSize px = [UIScreen mainScreen].nativeBounds.size;
	double need = MAX(px.width, px.height), shortSide = MIN(iw, ih), longSide = MAX(iw, ih);
	double maxPixel = shortSide > 0 ? MIN(longSide, ceil(longSide * need / shortSide)) : need;
	maxPixel = MIN(maxPixel, 2.0 * need);   // (a panorama: its long side at most twice the screen's, not its short side at the screen's -- review 1.8.6 M3)
	NSDictionary *o = @{(id)kCGImageSourceCreateThumbnailFromImageAlways: @YES, (id)kCGImageSourceCreateThumbnailWithTransform: @YES, (id)kCGImageSourceThumbnailMaxPixelSize: @(maxPixel)};
	CGImageRef img = CGImageSourceCreateThumbnailAtIndex(s, at, (__bridge CFDictionaryRef)o);
	CFRelease(s);
	if (!img) return nil;
	NSString *name = [NSString stringWithFormat:@"%@%lld.jpg", kMSBDWallpaperPhotoPrefix, (long long)[[NSDate date] timeIntervalSince1970]];
	NSString *path = [kMSBDWallpaperPhotoDir stringByAppendingPathComponent:name];
	CGImageDestinationRef d = CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], CFSTR("public.jpeg"), 1, NULL);
	BOOL ok = NO;
	if (d) { CGImageDestinationAddImage(d, img, (__bridge CFDictionaryRef)@{(id)kCGImageDestinationLossyCompressionQuality: @0.9}); ok = CGImageDestinationFinalize(d); CFRelease(d); }
	CGImageRelease(img);
	if (!ok) { [[NSFileManager defaultManager] removeItemAtPath:path error:nil]; return nil; }
	return path;   // (the one before is removed once the choice points at this one: WPRemoveOldPhotos)
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
	[picker dismissViewControllerAnimated:YES completion:nil];
	_picking = NO;
	NSItemProvider *ip = results.firstObject.itemProvider;
	if (![ip hasItemConformingToTypeIdentifier:@"public.image"]) return;   // (Cancel: nothing changes)
	__weak MSBWallpaperController *ws = self;
	[ip loadFileRepresentationForTypeIdentifier:@"public.image" completionHandler:^(NSURL *url, NSError *err) {
		NSString *path = url ? WPCopyPhoto(url) : nil;   // (the file given is only there during this call: copied now)
		dispatch_async(dispatch_get_main_queue(), ^{
			if (!path) return;
			MSBWallpaperController *s = ws;
			if (s) { [s msb_reload]; [s msb_choose:@{@"id": @"photo", @"name": @"Your Photo", @"path": path}]; }
			else WPWriteChoice(@"photo", path, nil);   // (the page went meanwhile: the pick still counts -- L4)
			WPRemoveOldPhotos(path);
		});
	}];
}
@end
