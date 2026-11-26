// MSBMacLockScreenController.m -- Settings > MacStatusBar&Dock > Status Bar > Lock Screen > Mac Lock Screen (F49, 1.8.9; KT 25 Nov ~02:35: "lets
// make it a submenu since its a lot of switches"). Its rows are MacLockScreen.plist's (so the Settings search finds them, common/TweakIndex.h);
// this controller only sets what depends on the iPad: the per-version defaults (common/MacLockScreen.h, the same function SpringBoard uses), the
// Background choices this iPadOS can draw, the footers, the greyed rows, and "Handled by another tweak" under a part SpringBoard found another
// modification already changing (its state file: part labels only, never a name). The picture: Initials by default; "Choose from Photos..." is the
// system's own picker (it runs outside Settings and gives only the picture picked: no permission prompt), a small copy kept beside our files.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>
#import <notify.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
#import <Preferences/PSSwitchTableCell.h>
#import "../../common/MacLockScreen.h"
#import "../../common/DesktopWallpaper.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#import "../../common/LineSwitch.h"   // (MSBDNoteSwitch: a switch turned on here is in the crash guard's RecentlyOn list, as every switch of ours)
#pragma clang diagnostic pop

// ---- the "Handled by another tweak" line under a row (grey, no name) ----
static NSString *const kMLSHandledText = @"Handled by another tweak";
static void MLSLayoutHandled(PSTableCell *cell) {
	static const void *kLabel = &kLabel;
	UILabel *l = objc_getAssociatedObject(cell, kLabel);
	BOOL on = [[cell.specifier propertyForKey:@"mlsHandled"] boolValue];
	if (!on) { l.hidden = YES; return; }
	if (!l) {
		l = [UILabel new];
		l.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
		l.textColor = [UIColor secondaryLabelColor];
		l.text = kMLSHandledText;
		[cell.contentView addSubview:l];
		objc_setAssociatedObject(cell, kLabel, l, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
	l.hidden = NO;
	UILabel *t = cell.textLabel;
	CGRect tf = t.frame;
	CGFloat h = cell.contentView.bounds.size.height;
	[l sizeToFit];
	tf.origin.y = round(h / 2 - tf.size.height - 1);
	t.frame = tf;
	l.frame = CGRectMake(tf.origin.x, round(h / 2 + 1), MAX(l.bounds.size.width, 10), l.bounds.size.height);
}
@interface MSBMLSwitchCell : PSSwitchTableCell
@end
@implementation MSBMLSwitchCell
- (void)layoutSubviews { [super layoutSubviews]; MLSLayoutHandled(self); }
@end
@interface MSBMLLinkCell : PSTableCell
@end
@implementation MSBMLLinkCell
- (void)layoutSubviews { [super layoutSubviews]; MLSLayoutHandled(self); }
@end

// (PSSpecifier's own call, checked at run time as the Status Bar page does: MSBRootListController.m)
static void MLSSetValues(PSSpecifier *sp, NSArray *values, NSArray *titles) {
	SEL sv = NSSelectorFromString(@"setValues:titles:shortTitles:");
	if (![sp respondsToSelector:sv]) return;
	((void (*)(id, SEL, id, id, id))objc_msgSend)(sp, sv, values, titles, titles);
}
static int MLSOSMajor(void) { return (int)[NSProcessInfo processInfo].operatingSystemVersion.majorVersion; }
static NSDictionary *MLSStored(void) {
	CFPreferencesAppSynchronize(CFSTR(MLS_DOMAIN));
	NSMutableDictionary *d = [NSMutableDictionary dictionary];
	for (NSString *k in @[ @"enabled", @"clockStyle", @"background", @"cards", @"showUser", @"statusPair", @"picture", @"name" ]) {
		id v = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)k, CFSTR(MLS_DOMAIN)));
		if (v) d[k] = v;
	}
	return d;
}
static NSDictionary *MLSState(void) {
	NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:@MLS_STATE_FILE];
	return [d isKindOfClass:[NSDictionary class]] ? d : @{};
}
static BOOL MLSDesktopPictureSet(void) {
	id v = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR(kMSBDWallpaperPathKey), CFSTR("com.besiktasliseba.macstatusbar")));
	return [v isKindOfClass:[NSString class]] && MSBDWallpaperPathAllowed(v);
}
// (17/18: the depth-effect line names only the Backgrounds this page offers -- review of the black backdrop fix, 1)
static NSString *MLSDepthLine(BOOL blurred, BOOL desktop) {
	if (blurred && desktop) return @"Blurred Wallpaper and Desktop Picture hide your Lock Screen's depth effect while they show. Wallpaper keeps it.";
	return blurred ? @"Blurred Wallpaper hides your Lock Screen's depth effect while it shows. Wallpaper keeps it."
	               : @"Desktop Picture hides your Lock Screen's depth effect while it shows. Wallpaper keeps it.";
}
// The Status Bar page's row: "On" / "Off" (read as SpringBoard reads the switch)
NSString *MSBMacLockScreenValue(void) { return MLSettingsFrom(MLSStored(), MLSOSMajor()).enabled ? @"On" : @"Off"; }

@interface MSBMacLockScreenController : PSListController <PHPickerViewControllerDelegate>
@end
@implementation MSBMacLockScreenController
- (NSArray *)specifiers {
	if (_specifiers) return _specifiers;
	NSMutableArray *specs = [[self loadSpecifiersFromPlistName:@"MacLockScreen" target:self] mutableCopy];
	int os = MLSOSMajor();
	NSDictionary *stored = MLSStored(), *state = MLSState();
	MLSettings s = MLSettingsFrom(stored, os);
	BOOL blurred = MLBlurredOffered(os, state), desktop = MLSDesktopPictureSet();
	BOOL anyHandled = NO;
	for (PSSpecifier *sp in specs) {
		NSString *i = sp.identifier;
		BOOL afterMaster = ![i isEqualToString:@"MLS_MASTER_GROUP"] && ![i isEqualToString:@"MLS_ENABLED"];
		if (afterMaster && sp.cellType != PSGroupCell && !s.enabled) [sp setProperty:@NO forKey:@"enabled"];   // (greyed, their values kept)
		// (rev 2, 12.8: each footer true on its iPadOS with every pick, from the same version table SpringBoard uses)
		if ([i isEqualToString:@"MLS_MASTER_GROUP"])
			[sp setProperty:[NSString stringWithFormat:@"A Mac lock screen: the Mac clock, your picture and name, and Mac-style cards%@. Each part can go back to iPadOS's own, and your widgets and notifications always stay where iPadOS puts them.",
			                 blurred && MLDefaultBackground(os) == kMLBackBlurred ? @", on a blurred wallpaper" : @""] forKey:@"footerText"];
		if ([i isEqualToString:@"MLS_STYLE_GROUP"]) {
			NSString *clock = os >= 17 ? @"Mac shows the date above a large time, like on a Mac. iPadOS keeps the clock you set for your Lock Screen."
			                           : @"Mac shows the date above a large time, like on a Mac. iPadOS shows iPadOS's own clock.";
			if (os >= 17 && (blurred || desktop)) clock = [clock stringByAppendingFormat:@" %@", MLSDepthLine(blurred, desktop)];
			[sp setProperty:clock forKey:@"footerText"];
		}
		if ([i isEqualToString:@"MLS_CLOCK"]) [sp setProperty:MLClockStyleString(MLDefaultClockStyle(os)) forKey:@"default"];
		if ([i isEqualToString:@"MLS_BACKGROUND"]) {
			// (the default: the version's (Blurred on 15/16, Wallpaper on 17/18: 1.8.9 pass: the black backdrop) where this iPadOS gives a still, else Wallpaper --
			//  what SpringBoard draws, 12.8)
			[sp setProperty:MLBackgroundString(blurred ? MLDefaultBackground(os) : kMLBackWallpaper) forKey:@"default"];
			NSMutableArray *v = [NSMutableArray arrayWithObject:@"wallpaper"], *t = [NSMutableArray arrayWithObject:@"Wallpaper"];
			if (blurred) { [v addObject:@"blurred"]; [t addObject:@"Blurred Wallpaper"]; }
			if (desktop) { [v addObject:@"desktop"]; [t addObject:@"Desktop Picture"]; }
			MLSSetValues(sp, v, t);
			NSMutableArray *foot = [NSMutableArray array];
			if (!blurred) [foot addObject:os >= 17 ? @"Blurred Wallpaper is available on iPadOS 15 and 16." : @"Blurred needs a still picture of your Lock Screen, which this iPadOS doesn't give."];
			if (os >= 17 && (blurred || desktop)) [foot addObject:MLSDepthLine(blurred, desktop)];
			if (foot.count) [sp setProperty:[foot componentsJoinedByString:@" "] forKey:@"staticTextMessage"];
		}
		if (([i isEqualToString:@"MLS_PICTURE"] || [i isEqualToString:@"MLS_PICK"] || [i isEqualToString:@"MLS_NAME"]) && !s.showUser) [sp setProperty:@NO forKey:@"enabled"];
		if ([i isEqualToString:@"MLS_PICTURE"] && access(MLS_PICTURE_FILE, R_OK) != 0) MLSSetValues(sp, @[ @"initials" ], @[ @"Initials" ]);
		if ([i isEqualToString:@"MLS_NAME"]) [sp setProperty:MLAutomaticName([UIDevice currentDevice].name) forKey:@"placeholder"];
		// a part SpringBoard found another modification changing (only while the master is on and that part set to a Mac value)
		int part = [i isEqualToString:@"MLS_CLOCK"] ? kMLPartClock : [i isEqualToString:@"MLS_BACKGROUND"] ? kMLPartBackground : [i isEqualToString:@"MLS_CARDS"] ? kMLPartCards
		         : [i isEqualToString:@"MLS_USER"] ? kMLPartUser : [i isEqualToString:@"MLS_PAIR"] ? kMLPartPair : -1;
		if (part >= 0 && MLPartWanted(&s, part) && MLStateHandled(state, part)) {
			[sp setProperty:@YES forKey:@"mlsHandled"];
			[sp setProperty:@58 forKey:@"height"];
			[sp setProperty:(sp.cellType == PSSwitchCell ? [MSBMLSwitchCell class] : [MSBMLLinkCell class]) forKey:@"cellClass"];
			anyHandled = YES;
		}
	}
	if (anyHandled) {
		PSSpecifier *g = [PSSpecifier groupSpecifierWithID:@"MLS_HANDLED_GROUP"];
		[g setProperty:@"A part another tweak already changes stays off here, so the two never draw over each other." forKey:@"footerText"];
		[specs addObject:g];
	}
	_specifiers = specs;
	return _specifiers;
}
// the master, Picture and Name, or a choice that changes what the page offers: the rows follow at once
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)spec {
	if (spec.cellType == PSSwitchCell)
		MSBDNoteSwitch([spec propertyForKey:@"defaults"], [spec propertyForKey:@"key"], [@"Mac Lock Screen: " stringByAppendingString:spec.name ?: @""], [[self readPreferenceValue:spec] boolValue], [value boolValue]);
	[super setPreferenceValue:value specifier:spec];
	NSString *k = [spec propertyForKey:@"key"];
	if ([k isEqualToString:@"picture"] && [value isEqual:@"initials"]) unlink(MLS_PICTURE_FILE);   // (privacy: the copy goes when Initials is picked)
	if ([k isEqualToString:@"enabled"] || [k isEqualToString:@"showUser"] || [k isEqualToString:@"picture"])
		dispatch_async(dispatch_get_main_queue(), ^{ self->_specifiers = nil; [self reloadSpecifiers]; });
}
- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	_specifiers = nil; [self reloadSpecifiers];   // (SpringBoard's state file may have changed since: the "Handled" lines follow)
}
// ---- Choose from Photos... ----
- (void)msb_choosePicture:(PSSpecifier *)spec {
	PHPickerConfiguration *cfg = [PHPickerConfiguration new];   // (no photo library access: the picker gives only the picture picked)
	cfg.filter = [PHPickerFilter imagesFilter];
	cfg.selectionLimit = 1;
	PHPickerViewController *p = [[PHPickerViewController alloc] initWithConfiguration:cfg];
	p.delegate = self;
	[self presentViewController:p animated:YES completion:nil];
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
	[picker dismissViewControllerAnimated:YES completion:nil];
	NSItemProvider *ip = results.firstObject.itemProvider;
	if (![ip canLoadObjectOfClass:[UIImage class]]) return;   // (Cancel: nothing changes)
	__weak MSBMacLockScreenController *ws = self;
	[ip loadObjectOfClass:[UIImage class] completionHandler:^(id<NSItemProviderReading> obj, NSError *err) {
		UIImage *img = [(id)obj isKindOfClass:[UIImage class]] ? (UIImage *)obj : nil;
		if (!img) return;
		// (a 256 px square copy, the middle of the picture: all the round picture ever shows)
		CGFloat side = 256;
		UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat defaultFormat]; f.scale = 1; f.opaque = YES;
		UIImage *small = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side) format:f] imageWithActions:^(UIGraphicsImageRendererContext *rc) {
			CGSize s = img.size; CGFloat k = MAX(side / MAX(s.width, 1), side / MAX(s.height, 1));
			[img drawInRect:CGRectMake((side - s.width * k) / 2, (side - s.height * k) / 2, s.width * k, s.height * k)];
		}];
		NSData *png = UIImagePNGRepresentation(small);
		if (![png writeToFile:@MLS_PICTURE_FILE atomically:YES]) return;
		dispatch_async(dispatch_get_main_queue(), ^{
			MSBMacLockScreenController *me = ws;
			CFPreferencesSetAppValue(CFSTR("picture"), CFSTR("file"), CFSTR(MLS_DOMAIN));
			CFPreferencesAppSynchronize(CFSTR(MLS_DOMAIN));
			notify_post(MLS_NOTIFY);
			if (me) { me->_specifiers = nil; [me reloadSpecifiers]; }
		});
	}];
}
@end
