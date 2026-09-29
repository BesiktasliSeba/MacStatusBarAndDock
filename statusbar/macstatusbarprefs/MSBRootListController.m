#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <notify.h>
#import <unistd.h>
#import <objc/message.h>
#import <sys/sysctl.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSListItemsController.h>
#import <Preferences/PSTableCell.h>
#import "MSBRootListController.h"
#import "../../common/LineSwitch.h"
#import "../../common/EngineBuilds.h"
#import "../../common/StageManagerAvailable.h"
#import "../../common/OtherTweaks.h"   // (Single Mute showing the mute icon: said under the Audio group)

// The "Apps" row in the plist uses AltList's app picker (ATLApplicationListMultiSelectionController). That
// class only exists once AltList's library is loaded, and this bundle is not linked against it, so load it
// as soon as the bundle is loaded, before Settings looks the class up.
__attribute__((constructor)) static void MSBLoadAltList(void) {
	dlopen("/var/jb/Library/Frameworks/AltList.framework/AltList", RTLD_NOW);
}


// ---- Engine exclusivity (2026-09-24, "Option A"): picking a Window Engine here makes the OTHER engines truly not load. An engine's own "Enabled"
// switch is not enough: its library still loads into SpringBoard and hooks it, and two windowing tweaks loaded together can break Full Screen mirroring
// over AirPlay/HDMI. The package depends on Choicy (or iCleaner Pro), and whichever is installed does the actual not-loading:
//  - Choicy: its global "denied tweaks" list (globalDeniedTweaks in /var/jb/var/mobile/Library/Preferences/com.opa334.choicyprefs.plist, a plain file
//    owned by mobile that Choicy's own settings write the same way, then post com.opa334.choicyprefs/ReloadPrefs). The format is the same in Choicy
//    1.4.7 .. 1.5.4 (checked in its source: only 1.4 renamed the key from globalTweakBlacklist), so no version-specific code is needed. SpringBoard's own
//    per-app configuration in Choicy, when switched on, can override the global list, so it is kept in line too. A copy of the whole Choicy file as it
//    was before we first changed it is kept in MacStatusBar-ChoicyBackup.plist.
//  - iCleaner Pro (no Choicy): it turns a tweak off by renaming its .dylib to .disabled inside /var/jb/usr/lib/TweakInject, which is root-only, so
//    Settings (running as mobile) cannot do it itself. With MacSettings installed, its root helper (sshtoggled) does it when asked with the
//    notification com.besiktasliseba.msb.engines.apply (it re-reads the choice from our preferences itself); without it, Settings tells the user exactly which
//    ones to switch off in iCleaner Pro and opens it.
static NSString *const kMSBTweakDir = @"/var/jb/usr/lib/TweakInject";
static NSString *const kMSBChoicyPrefs = @"/var/jb/var/mobile/Library/Preferences/com.opa334.choicyprefs.plist";
static NSString *const kMSBChoicyBackup = @"/var/jb/var/mobile/Library/Preferences/MacStatusBar-ChoicyBackup.plist";
static NSDictionary<NSString *, NSArray<NSString *> *> *MSBEngineLibraries(void) {
	return @{@"aerial": @[@"Aerial"], @"milkyway": @[@"MilkyWay4", @"MilkyWay3SubModule"], @"zetsu": @[@"Zetsu"]};
}
static BOOL MSBLibraryPresent(NSString *name, NSString *ext) {
	return [[NSFileManager defaultManager] fileExistsAtPath:[[kMSBTweakDir stringByAppendingPathComponent:name] stringByAppendingPathExtension:ext]];
}
static BOOL MSBChoicyInstalled(void) { return MSBLibraryPresent(@"ChoicySB", @"dylib") || MSBLibraryPresent(@"Choicy", @"dylib"); }
static BOOL MSBiCleanerInstalled(void) { return [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/Applications/iCleaner.app"]; }
// The libraries of every installed engine other than `engine` (installed = its .dylib or an iCleaner-disabled .disabled is there).
static NSArray<NSString *> *MSBOtherEngineLibraries(NSString *engine) {
	NSMutableArray *out = [NSMutableArray array];
	[MSBEngineLibraries() enumerateKeysAndObjectsUsingBlock:^(NSString *e, NSArray<NSString *> *libs, BOOL *stop) {
		if ([e isEqualToString:engine]) return;
		for (NSString *l in libs) if (MSBLibraryPresent(l, @"dylib") || MSBLibraryPresent(l, @"disabled")) [out addObject:l];
	}];
	return [out sortedArrayUsingSelector:@selector(compare:)];
}
// Every change we make to Choicy's lists is RECORDED (kMSBChoicyChanges: list -> entry -> "added"/"removed", the net effect of all our changes), so
// that if Mac Status Bar is ever switched off without being removed, MacSettings' root helper (sshtoggled) can undo exactly our changes and nothing
// else -- only where an entry is still as we left it; everything the user changes in Choicy is theirs (2026-09-24).
static NSString *const kMSBChoicyChanges = @"/var/jb/var/mobile/Library/Preferences/MacStatusBar-ChoicyChanges.plist";
static void MSBRecordChange(NSMutableDictionary *record, NSString *listKey, NSString *entry, BOOL added) {
	NSMutableDictionary *l = [record[listKey] isKindOfClass:[NSDictionary class]] ? [record[listKey] mutableCopy] : [NSMutableDictionary new];
	NSString *before = l[entry];
	if ((added && [before isEqual:@"removed"]) || (!added && [before isEqual:@"added"])) [l removeObjectForKey:entry];   // back to the user's own state
	else l[entry] = added ? @"added" : @"removed";
	if (l.count) record[listKey] = l; else [record removeObjectForKey:listKey];
}
static BOOL MSBSetMembershipRecorded(NSMutableArray *list, NSArray *add, NSArray *remove, NSString *listKey, NSMutableDictionary *record) {
	BOOL changed = NO;
	for (NSString *n in add) if (![list containsObject:n]) { [list addObject:n]; changed = YES; MSBRecordChange(record, listKey, n, YES); }
	for (NSString *n in remove) if ([list containsObject:n]) { while ([list containsObject:n]) [list removeObject:n]; changed = YES; MSBRecordChange(record, listKey, n, NO); }
	return changed;
}
// (Setups from before the record existed: it is made once from the copy of Choicy's settings we took before our first change, window-engine entries
// only -- those are the only entries we ever change.)
static NSMutableDictionary *MSBLoadChoicyRecord(NSDictionary *current) {
	NSMutableDictionary *record = [[NSDictionary dictionaryWithContentsOfFile:kMSBChoicyChanges] mutableCopy];
	if (record) return record;
	record = [NSMutableDictionary new];
	NSDictionary *orig = [NSDictionary dictionaryWithContentsOfFile:kMSBChoicyBackup];
	if (!orig) return record;
	NSArray *engines = @[@"Aerial", @"MilkyWay4", @"MilkyWay3SubModule", @"Zetsu"];
	NSDictionary *pairs = @{ @"globalDeniedTweaks": @[@"globalDeniedTweaks"], @"springboard.allowedTweaks": @[@"appSettings", @"com.apple.springboard", @"allowedTweaks"], @"springboard.deniedTweaks": @[@"appSettings", @"com.apple.springboard", @"deniedTweaks"] };
	for (NSString *listKey in pairs) {
		id a = current, b = orig;
		for (NSString *k in pairs[listKey]) { a = [a isKindOfClass:[NSDictionary class]] ? a[k] : nil; b = [b isKindOfClass:[NSDictionary class]] ? b[k] : nil; }
		NSArray *now = [a isKindOfClass:[NSArray class]] ? a : @[], *before = [b isKindOfClass:[NSArray class]] ? b : @[];
		for (NSString *e in engines) {
			if ([now containsObject:e] && ![before containsObject:e]) MSBRecordChange(record, listKey, e, YES);
			if (![now containsObject:e] && [before containsObject:e]) MSBRecordChange(record, listKey, e, NO);
		}
	}
	return record;
}
// Choicy: deny the other engines, allow the picked one. Returns YES if Choicy's configuration had to change (a respring makes it real).
static BOOL MSBChoicyApplyEngine(NSString *engine) {
	NSMutableDictionary *prefs = [[NSDictionary dictionaryWithContentsOfFile:kMSBChoicyPrefs] mutableCopy] ?: [NSMutableDictionary new];
	NSMutableDictionary *record = MSBLoadChoicyRecord(prefs);
	NSArray *keep = MSBEngineLibraries()[engine] ?: @[], *deny = MSBOtherEngineLibraries(engine);
	NSMutableArray *global = [prefs[@"globalDeniedTweaks"] isKindOfClass:[NSArray class]] ? [prefs[@"globalDeniedTweaks"] mutableCopy] : [NSMutableArray new];
	BOOL changed = MSBSetMembershipRecorded(global, deny, keep, @"globalDeniedTweaks", record);
	prefs[@"globalDeniedTweaks"] = global;
	NSMutableDictionary *apps = [prefs[@"appSettings"] isKindOfClass:[NSDictionary class]] ? [prefs[@"appSettings"] mutableCopy] : nil;
	NSMutableDictionary *sb = [apps[@"com.apple.springboard"] isKindOfClass:[NSDictionary class]] ? [apps[@"com.apple.springboard"] mutableCopy] : nil;
	if ([sb[@"customTweakConfigurationEnabled"] boolValue]) {   // SpringBoard's own list is in force: it must agree
		NSInteger mode = sb[@"allowDenyMode"] ? [sb[@"allowDenyMode"] integerValue] : 1;
		NSString *listKey = mode == 2 ? @"deniedTweaks" : @"allowedTweaks";
		NSMutableArray *list = [sb[listKey] isKindOfClass:[NSArray class]] ? [sb[listKey] mutableCopy] : [NSMutableArray new];
		NSString *rk = [@"springboard." stringByAppendingString:listKey];
		BOOL c = mode == 2 ? MSBSetMembershipRecorded(list, [sb[@"overwriteGlobalTweakConfiguration"] boolValue] ? deny : @[], keep, rk, record) : MSBSetMembershipRecorded(list, keep, deny, rk, record);
		if (c) { sb[listKey] = list; apps[@"com.apple.springboard"] = sb; prefs[@"appSettings"] = apps; changed = YES; }
	}
	if (!changed) { if (![[NSFileManager defaultManager] fileExistsAtPath:kMSBChoicyChanges]) [record writeToFile:kMSBChoicyChanges atomically:YES]; return NO; }
	if (![[NSFileManager defaultManager] fileExistsAtPath:kMSBChoicyBackup]) {
		NSDictionary *orig = [NSDictionary dictionaryWithContentsOfFile:kMSBChoicyPrefs];
		if (orig) [orig writeToFile:kMSBChoicyBackup atomically:YES];
	}
	[record writeToFile:kMSBChoicyChanges atomically:YES];
	if (!prefs[@"preferenceVersion"]) prefs[@"preferenceVersion"] = @1;
	[prefs writeToFile:kMSBChoicyPrefs atomically:YES];
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.opa334.choicyprefs/ReloadPrefs"), NULL, NULL, YES);
	return YES;
}
static void MSBRespring(void) { MSBDRespring(); }   // (LineSwitch.h: with the VPN check first)

// ---- Window Engine list (2026-09-24): every engine this iOS supports is listed; one that is not installed is shown greyed out and cannot be
// picked (stock-looking disabled row), and an installed build our integration has not been tested with is greyed with a short note (it would run on
// its own, without any of our window features -- the one list of tested builds is common/EngineBuilds.h).
// "Installed" = its library is in TweakInject, as .dylib or as iCleaner's .disabled (Choicy's deny list does not make an engine uninstalled).
// 0 = not installed, 1 = installed but not a tested build, 2 = installed and tested
static NSString *MSBEngineLibraryPath(NSString *lib) {   // (its .dylib, or iCleaner's .disabled)
	NSString *path = [[kMSBTweakDir stringByAppendingPathComponent:lib] stringByAppendingPathExtension:@"dylib"];
	if (![[NSFileManager defaultManager] fileExistsAtPath:path]) path = [[kMSBTweakDir stringByAppendingPathComponent:lib] stringByAppendingPathExtension:@"disabled"];
	return path;
}
// Stage Manager as the engine (iPadOS 16+): usable where Stage Manager runs -- natively (iPad Pro 2018 and later, M1/M2 iPads: iPad8/13/14,x) or
// through TrollPad on older iPads.
// (and where SpringBoard's self-check of the engine found the system methods it uses missing or different on this iPadOS version, it is not
// offered either: the row greyed, "Not Supported Yet" -- the same verdict as SpringBoard and the root helper, common/StageManagerAvailable.h)
static BOOL MSBStageManagerAvailable(void) { return MSBDStageManagerEngineUsable(); }   // (common/StageManagerAvailable.h)
static BOOL MSBStageManagerUnsupported(NSString **os) {   // (Stage Manager is here, but the engine's self-check failed on this iPadOS build)
	return MSBDStageManagerAvailable() && MSBDStageManagerVerdict(NULL, os) == 0;
}
static int MSBEngineState(NSString *engine) {
	if ([engine isEqualToString:@"stagemanager"]) return MSBStageManagerAvailable() ? 2 : 0;
	NSDictionary *mainLib = @{@"aerial": @"Aerial", @"milkyway": @"MilkyWay4", @"zetsu": @"Zetsu"};
	NSString *lib = mainLib[engine];
	if (!lib) return 2;
#if DEBUG
	NSString *pretend = [NSString stringWithContentsOfFile:@"/tmp/msb-engine-notinstalled" encoding:NSUTF8StringEncoding error:nil];   // (debug: test the GET button)
	if ([pretend containsString:[engine stringByAppendingString:@"-untested"]]) return 1;   // (debug: test the "(untested version)" label)
	if ([pretend containsString:engine]) return 0;
#endif
	NSString *path = MSBEngineLibraryPath(lib);
	if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return 0;
	return MSBDEngineFileTested(lib, path) ? 2 : 1;
}
@interface MSBEngineListController : PSListItemsController
@end
@implementation MSBEngineListController
- (NSString *)msb_valueForRow:(NSIndexPath *)ip {
	NSArray *values = ((id (*)(id, SEL))objc_msgSend)(self.specifier, NSSelectorFromString(@"values"));
	return ip.section == 0 && ip.row < (NSInteger)values.count ? values[ip.row] : nil;
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *cell = [super tableView:tv cellForRowAtIndexPath:ip];
	NSString *v = [self msb_valueForRow:ip];
	int state = v ? MSBEngineState(v) : 2;
	BOOL usable = state == 2;
	cell.userInteractionEnabled = usable || state == 0;   // (a not-installed row stays greyed and unselectable, but its GET button can be tapped)
	cell.selectionStyle = usable ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
	cell.textLabel.enabled = usable;
	if (state == 1 && ![cell.textLabel.text hasSuffix:@"(untested version)"]) cell.textLabel.text = [cell.textLabel.text stringByAppendingString:@" (untested version)"];
	// Requirement (2026-09-24): an engine this iOS supports but that is not installed gets an App Store-style GET button where the checkmark would be,
	// opening the engine's official page (Aerial: the GitHub link in Aerial's own Settings bundle; Zetsu and MilkyWay4: their developers' own
	// GitHub-hosted pages).
	NSDictionary *pages = @{@"aerial": @"https://github.com/uz-ra", @"zetsu": @"https://dcsyhi1998.github.io/depiction/zetsu",
	                        @"milkyway": @"https://akusio.github.io/"};
	if (state == 0 && pages[v]) {
		UIButton *get = [UIButton buttonWithType:UIButtonTypeSystem];
		[get setTitle:@"GET" forState:UIControlStateNormal];
		get.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightBold];
		[get setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
		get.backgroundColor = [UIColor tertiarySystemFillColor];
		get.frame = CGRectMake(0, 0, 74.0, 28.0);
		get.layer.cornerRadius = 14.0;
		get.clipsToBounds = YES;
		NSString *url = pages[v];
		[get addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
			[[UIApplication sharedApplication] openURL:[NSURL URLWithString:url] options:@{} completionHandler:nil];
		}] forControlEvents:UIControlEventTouchUpInside];
		cell.accessoryView = get;
	} else if ([v isEqualToString:@"stagemanager"] && MSBStageManagerUnsupported(NULL)) {   // (greyed, and why, where the checkmark would be)
		UILabel *why = [UILabel new];
		why.text = @"Not Supported Yet";
		why.font = [UIFont systemFontOfSize:15.0];
		why.textColor = [UIColor secondaryLabelColor];
		[why sizeToFit];
		cell.accessoryView = why;
	} else cell.accessoryView = nil;
	return cell;
}
- (NSIndexPath *)tableView:(UITableView *)tv willSelectRowAtIndexPath:(NSIndexPath *)ip {
	NSString *v = [self msb_valueForRow:ip];
	return (v && MSBEngineState(v) != 2) ? nil : ip;
}
@end

// ---- Report a Problem (2026-09-25): opens a new GitHub issue in Safari, its text already filled in with what helps and nothing personal: the device
// model (hw.machine, e.g. iPad13,4), the iPadOS version, the window engine and its package version, and this package's version; since 2026-09-26
// also the crash guard's short crash summary and, on an untested iPadOS version, the tester lines (common/CrashExplain.h, where the address is).

// ---- Status Bar Background > Color (2026-09-25): Apple's color well and picker (iOS 14+) instead of a hex text field. The choice is still stored as a
// hex string under backgroundColor (#242225 when nothing is stored), so a saved color stays; the opacity has its own slider, so no alpha here.
// While the picker is dragged the value is written at once and SpringBoard is told at most every 0.15 s.
#define kMSBBarDomain CFSTR("com.besiktasliseba.macstatusbar")
static UIColor *MSBStoredBarColor(void) {
	CFPreferencesAppSynchronize(kMSBBarDomain);
	CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("backgroundColor"), kMSBBarDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	NSString *hex = v ? CFBridgingRelease(v) : nil;
	unsigned int rgb = 0x242225;
	if ([hex isKindOfClass:[NSString class]]) {
		NSString *h = [[hex stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] stringByReplacingOccurrencesOfString:@"#" withString:@""];
		unsigned int parsed = 0;
		if (h.length == 6 && [[NSScanner scannerWithString:h] scanHexInt:&parsed]) rgb = parsed;
	}
	return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0 green:((rgb >> 8) & 0xff) / 255.0 blue:(rgb & 0xff) / 255.0 alpha:1.0];
}
static void MSBSaveBarColor(UIColor *c) {
	CGFloat r = 0, g = 0, b = 0, a = 0;
	if (![c getRed:&r green:&g blue:&b alpha:&a]) return;
	int (^byte)(CGFloat) = ^int(CGFloat x) { return (int)lround(MIN(1.0, MAX(0.0, x)) * 255.0); };
	NSString *hex = [NSString stringWithFormat:@"#%02X%02X%02X", byte(r), byte(g), byte(b)];
	CFPreferencesSetValue(CFSTR("backgroundColor"), (__bridge CFStringRef)hex, kMSBBarDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	static BOOL pending = NO;
	if (pending) return;
	pending = YES;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		pending = NO;
		CFPreferencesSynchronize(kMSBBarDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
		notify_post("com.besiktasliseba.macstatusbar/prefsChanged");
	});
}
@interface MSBColorCell : PSTableCell
@end
@implementation MSBColorCell {
	UIColorWell *_well;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid specifier:(PSSpecifier *)specifier {
	self = [super initWithStyle:style reuseIdentifier:rid specifier:specifier];
	if (!self) return nil;
	_well = [[UIColorWell alloc] initWithFrame:CGRectMake(0, 0, 32, 32)];
	_well.supportsAlpha = NO;
	_well.title = @"Color";
	_well.selectedColor = MSBStoredBarColor();
	[_well addTarget:self action:@selector(msb_colorChanged) forControlEvents:UIControlEventValueChanged];
	self.accessoryView = _well;
	self.selectionStyle = UITableViewCellSelectionStyleNone;
	return self;
}
- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
	[super refreshCellContentsWithSpecifier:specifier];
	self.accessoryView = _well;
	self.textLabel.textColor = [UIColor labelColor];
}
- (void)msb_colorChanged { if (_well.selectedColor) MSBSaveBarColor(_well.selectedColor); }
@end

// ---- Status Bar Style (2026-09-25): a "Status Bar Style" row (Mac / Stock), like Pointer Style -- shows the current choice and opens a two-item
// picker page (Root.plist: cell PSLinkListCell, detail PSListItemsController, key stockStatusBar, validValues "mac"/"stock"). The value is still
// stored as the plain bool StatusBar.x/StockBar.h have always read (stockStatusBar); -readPreferenceValue:/-setPreferenceValue:specifier: below
// translate it to and from the two strings the picker offers, so nothing else about the stored preference changes. While it is on, the groups
// tagged stockHides in Root.plist (and their rows) are left out, the way Apple hides rows that depend on a switch. It takes effect after a
// respring (StatusBar.x / StockBar.h), so a change still offers one.
static BOOL MSBStockBarStored(void) {
	CFPreferencesAppSynchronize(kMSBBarDomain);
	CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("stockStatusBar"), kMSBBarDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	BOOL on = v && CFGetTypeID(v) == CFBooleanGetTypeID() && CFBooleanGetValue(v);
	if (v) CFRelease(v);
	return on;
}
static void MSBSetStockBarStored(BOOL on) {
	CFPreferencesSetValue(CFSTR("stockStatusBar"), on ? kCFBooleanTrue : kCFBooleanFalse, kMSBBarDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	CFPreferencesSynchronize(kMSBBarDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	notify_post("com.besiktasliseba.macstatusbar/prefsChanged");
}

@implementation MSBRootListController

MSBD_LINE_SWITCH_METHODS

- (void)msb_stockChanged:(BOOL)on {
	dispatch_async(dispatch_get_main_queue(), ^{   // (after the picker's own callback)
		_specifiers = nil;
		[self reloadSpecifiers];
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Respring to Finish" message:on ? @"The stock status bar turns on after a respring." : @"The Mac status bar comes back after a respring." preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:@"Respring Now" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ MSBRespring(); });   // (SpringBoard gives the engine its settings back first)
		}]];
		[alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
		[self presentViewController:alert animated:YES completion:nil];
	});
}

- (void)msb_reportProblem:(PSSpecifier *)specifier {
	PSSpecifier *engineSpec = nil;
	for (PSSpecifier *sp in [self specifiers]) if ([[sp propertyForKey:@"key"] isEqual:@"windowEngine"]) engineSpec = sp;
	NSString *engine = engineSpec ? [self readPreferenceValue:engineSpec] : nil;   // (the engine that really runs: see -readPreferenceValue: below)
	MSBDOpenReport(MSBDReportProblemURL([engine isKindOfClass:[NSString class]] && ![engine isEqualToString:@"none"] ? engine : nil));
}

// The page is opened from a row we add to Settings ourselves, not from a PreferenceLoader entry, so say where the
// bundle is instead of relying on the entry to tell Settings.
- (NSBundle *)bundle {
	return [NSBundle bundleForClass:[MSBRootListController class]];
}

// The stock slider cell's value label is a little too narrow for two decimals on iPadOS 16: "0.70" showed as "0.7C" (iPad 2 cross-test, both
// sliders). The label keeps its place and size; its text shrinks a touch when it would not fit.
static void MSBFitValueLabels(UIView *v) {
	for (UIView *sub in v.subviews) {
		if ([sub isKindOfClass:[UILabel class]]) {
			UILabel *l = (UILabel *)sub;
			NSString *t = l.text ?: @"";
			if (t.length && [t rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789.,-"] invertedSet]].location == NSNotFound) {
				l.adjustsFontSizeToFitWidth = YES; l.minimumScaleFactor = 0.6;
			}
		}
		MSBFitValueLabels(sub);
	}
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *cell = [super tableView:tv cellForRowAtIndexPath:ip];
	if ([NSStringFromClass([cell class]) containsString:@"Slider"]) {
		MSBFitValueLabels(cell);
		dispatch_async(dispatch_get_main_queue(), ^{ MSBFitValueLabels(cell); });   // (the value label may be made during the first layout)
	}
	return cell;
}

- (NSArray *)specifiers {
	if (!_specifiers) {
		_specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
		NSArray *untested = [self msbd_untestedSpecifiers];   // (on top: "Enable Anyway" on an untested iPadOS version, or the crash guard's note)
		if (untested.count) { NSMutableArray *all = [untested mutableCopy]; [all addObjectsFromArray:_specifiers]; _specifiers = all; }
		// The Control Center size only resizes BigSurCenter's own drop-down panel; with the stock Control Center it does nothing, so without
		// BigSurCenter installed its whole section (the group and its slider) is left out.
		BOOL bigSur = NO;
		for (NSString *dir in @[@"/var/jb/usr/lib/TweakInject", @"/var/jb/Library/MobileSubstrate/DynamicLibraries"])
			if ([[NSFileManager defaultManager] fileExistsAtPath:[dir stringByAppendingPathComponent:@"BigSurCenter.dylib"]]) bigSur = YES;
		if (!bigSur) {
			NSMutableArray *kept = [_specifiers mutableCopy];
			for (PSSpecifier *spec in _specifiers) {
				BOOL ccGroup = [spec.identifier isEqualToString:@"CC_SIZE_GROUP"];
				if (ccGroup || [[spec propertyForKey:@"key"] isEqual:@"controlCenterScale"]) [kept removeObject:spec];
			}
			_specifiers = kept;
		}
		// The Control Center size slider: small and large glyphs at its ends, like Apple's own size sliders, instead of a raw number.
		for (PSSpecifier *spec in _specifiers) {
			if (![[spec propertyForKey:@"key"] isEqual:@"controlCenterScale"]) continue;
			UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightRegular];
			UIImage *small = [UIImage systemImageNamed:@"textformat.size.smaller" withConfiguration:cfg], *large = [UIImage systemImageNamed:@"textformat.size.larger" withConfiguration:cfg];
			small = [small imageWithTintColor:[UIColor secondaryLabelColor] renderingMode:UIImageRenderingModeAlwaysOriginal];   // (grey, like Apple's slider glyphs)
			large = [large imageWithTintColor:[UIColor secondaryLabelColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
			if (small && large) { [spec setProperty:small forKey:@"leftImage"]; [spec setProperty:large forKey:@"rightImage"]; }
		}
		// Stage Manager as an engine only exists on iPadOS 16+ (and only where Stage Manager runs, MSBEngineState greys it out elsewhere).
		if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion < 16) for (PSSpecifier *spec in _specifiers) {
			if (![[spec propertyForKey:@"key"] isEqual:@"windowEngine"] || ![spec respondsToSelector:NSSelectorFromString(@"values")] || ![spec respondsToSelector:NSSelectorFromString(@"setValues:titles:shortTitles:")]) continue;
			NSArray *v = ((id (*)(id, SEL))objc_msgSend)(spec, NSSelectorFromString(@"values"));
			NSDictionary *td = ((id (*)(id, SEL))objc_msgSend)(spec, NSSelectorFromString(@"titleDictionary"));
			NSDictionary *sd = ((id (*)(id, SEL))objc_msgSend)(spec, NSSelectorFromString(@"shortTitleDictionary"));
			NSMutableArray *values = [NSMutableArray array], *titles = [NSMutableArray array], *shorts = [NSMutableArray array];
			for (NSString *x in v) { if ([x isEqual:@"stagemanager"]) continue; [values addObject:x]; [titles addObject:[x isEqual:@"aerial"] ? [NSString stringWithFormat:@"%@ (Recommended)", td[x] ?: @"Aerial"] : (td[x] ?: x)]; [shorts addObject:sd[x] ?: td[x] ?: x]; }
			((void (*)(id, SEL, id, id, id))objc_msgSend)(spec, NSSelectorFromString(@"setValues:titles:shortTitles:"), values, titles, shorts);
		}
		// MilkyWay4 does not run on iPadOS 16, so there it is not offered as an engine and not named in the notes.
		if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 16) {
			for (PSSpecifier *spec in _specifiers) {
				NSString *footer = [spec propertyForKey:@"footerText"];
				if ([footer isKindOfClass:[NSString class]] && [footer containsString:@"MilkyWay4"])
					[spec setProperty:[footer stringByReplacingOccurrencesOfString:@", MilkyWay4 or " withString:@" or "] forKey:@"footerText"];
				if (![[spec propertyForKey:@"key"] isEqual:@"windowEngine"]) continue;
				NSMutableArray *values = [NSMutableArray array], *titles = [NSMutableArray array], *shorts = [NSMutableArray array];
				BOOL api = YES;   // (guard: a newer iPadOS might not have these)
				for (NSString *sel in @[@"values", @"titleDictionary", @"shortTitleDictionary", @"setValues:titles:shortTitles:"]) api = api && [spec respondsToSelector:NSSelectorFromString(sel)];
				if (!api) continue;
				NSArray *v = ((id (*)(id, SEL))objc_msgSend)(spec, NSSelectorFromString(@"values"));
				NSDictionary *td = ((id (*)(id, SEL))objc_msgSend)(spec, NSSelectorFromString(@"titleDictionary"));
				NSDictionary *sd = ((id (*)(id, SEL))objc_msgSend)(spec, NSSelectorFromString(@"shortTitleDictionary"));
				for (NSUInteger i = 0; i < v.count; i++) {
					if ([v[i] isEqual:@"milkyway"]) continue;
					[values addObject:v[i]];
					// (1.1.3: Aerial 5.0 is the recommended engine on every iPad again -- Stage Manager is an option, not the default)
					BOOL rec = [v[i] isEqual:@"aerial"];
					[titles addObject:rec ? [NSString stringWithFormat:@"%@ (Recommended)", td[v[i]] ?: @"Aerial"] : (td[v[i]] ?: v[i])];
					[shorts addObject:sd[v[i]] ?: td[v[i]] ?: v[i]];
				}
				((void (*)(id, SEL, id, id, id))objc_msgSend)(spec, NSSelectorFromString(@"setValues:titles:shortTitles:"), values, titles, shorts);
			}
		}
		// No working engine (none installed, or the one that would run is an untested build, which runs on its own): the Window Engine row says
		// "None" and the Windows group (whose switches only work through an engine) is left out, with a short note (StatusBar.x shows the dots then).
		for (PSSpecifier *spec in [_specifiers copy]) {
			if (![[spec propertyForKey:@"key"] isEqual:@"windowEngine"]) continue;
			NSString *engine = [self readPreferenceValue:spec];
			if ([engine isKindOfClass:[NSString class]] && ![engine isEqualToString:@"none"] && MSBEngineState(engine) == 2) break;
			SEL setShort = NSSelectorFromString(@"setShortTitleDictionary:"), setTitles = NSSelectorFromString(@"setTitleDictionary:");
			if ([spec respondsToSelector:setShort] && [spec respondsToSelector:setTitles] && [engine isKindOfClass:[NSString class]]) {
				NSMutableDictionary *sd = [NSMutableDictionary dictionary];
				NSDictionary *oldShort = [spec respondsToSelector:NSSelectorFromString(@"shortTitleDictionary")] ? ((id (*)(id, SEL))objc_msgSend)(spec, NSSelectorFromString(@"shortTitleDictionary")) : nil;
				NSDictionary *oldTitles = [spec respondsToSelector:NSSelectorFromString(@"titleDictionary")] ? ((id (*)(id, SEL))objc_msgSend)(spec, NSSelectorFromString(@"titleDictionary")) : nil;
				if ([oldShort isKindOfClass:[NSDictionary class]]) [sd addEntriesFromDictionary:oldShort];
				sd[engine] = @"None";   // (the row only: the picker's own rows use the full titles, "(untested version)" included)
				((void (*)(id, SEL, id))objc_msgSend)(spec, setShort, sd);
				if ([engine isEqualToString:@"none"]) {
					NSMutableDictionary *td = [oldTitles isKindOfClass:[NSDictionary class]] ? [oldTitles mutableCopy] : [NSMutableDictionary dictionary];
					td[@"none"] = @"None";
					((void (*)(id, SEL, id))objc_msgSend)(spec, setTitles, td);
				}
			}
			NSMutableArray *kept = [NSMutableArray array];
			BOOL hiding = NO;
			for (PSSpecifier *sp in _specifiers) {
				if (sp.cellType == PSGroupCell) hiding = [sp.identifier isEqualToString:@"WINDOWS_GROUP"];
				if ([sp.identifier isEqualToString:@"ENGINE_GROUP"]) [sp setProperty:@"No tested window engine is installed, so the window features are off." forKey:@"footerText"];
				if (!hiding) [kept addObject:sp];
			}
			_specifiers = kept;
			break;
		}
		// Stage Manager as the engine: the Windows group's switches work through a third-party engine's windows, so it is left out.
		for (PSSpecifier *spec in [_specifiers copy]) {
			if (![[spec propertyForKey:@"key"] isEqual:@"windowEngine"]) continue;
			NSString *engine = [self readPreferenceValue:spec];
			if (![engine isKindOfClass:[NSString class]] || ![engine isEqualToString:@"stagemanager"]) break;
			NSMutableArray *kept = [NSMutableArray array];
			BOOL hiding = NO;
			for (PSSpecifier *sp in _specifiers) {
				if (sp.cellType == PSGroupCell) hiding = [sp.identifier isEqualToString:@"WINDOWS_GROUP"];
				if ([sp.identifier isEqualToString:@"ENGINE_GROUP"]) [sp setProperty:@"Apple's Stage Manager does the windowing, with the Mac look on top. Other engines are not loaded." forKey:@"footerText"];
				// (the window handles are Stage Manager's own windows' too: their style and tint stay)
				NSString *key = [sp propertyForKey:@"key"];
				BOOL handles = [key isEqual:@"resizeHandleStyle"] || [key isEqual:@"tintResizeHandles"];
				if (!hiding || handles || (sp.cellType == PSGroupCell && [sp.identifier isEqualToString:@"WINDOWS_GROUP"])) [kept addObject:sp];
			}
			_specifiers = kept;
			break;
		}
		// Stage Manager picked, but not supported on this iPadOS version (the engine's self-check failed): the default engine runs, and the footer says why.
		for (PSSpecifier *spec in [_specifiers copy]) {
			if (![[spec propertyForKey:@"key"] isEqual:@"windowEngine"]) continue;
			id stored = [super readPreferenceValue:spec];
			NSString *os = nil;
			if (![stored isKindOfClass:[NSString class]] || ![stored isEqualToString:@"stagemanager"] || !MSBStageManagerUnsupported(&os)) break;
			for (PSSpecifier *sp in _specifiers) if ([sp.identifier isEqualToString:@"ENGINE_GROUP"])
				[sp setProperty:[NSString stringWithFormat:@"Stage Manager isn't supported as a window engine on iPadOS %@ yet, so the default engine is used.", os ?: @"(this version)"] forKey:@"footerText"];
			break;
		}
		// "Resize Handles" (ours or Stage Manager's) is only a choice with Stage Manager as the engine: the other engines always have ours.
		for (PSSpecifier *spec in [_specifiers copy]) {
			if (![[spec propertyForKey:@"key"] isEqual:@"windowEngine"]) continue;
			NSString *engine = [self readPreferenceValue:spec];
			if ([engine isKindOfClass:[NSString class]] && [engine isEqualToString:@"stagemanager"]) break;
			NSMutableArray *kept = [NSMutableArray array];
			for (PSSpecifier *sp in _specifiers) if (![[sp propertyForKey:@"key"] isEqual:@"resizeHandleStyle"]) [kept addObject:sp];
			_specifiers = kept;
			break;
		}
				// "Resize Apps to Fit Windows" only works with MilkyWay4 (Zetsu always fits apps to its windows itself, Aerial never does): with any
		// other engine, or none, its group and switch are left out.
		for (PSSpecifier *spec in [_specifiers copy]) {
			if (![[spec propertyForKey:@"key"] isEqual:@"windowEngine"]) continue;
			NSString *engine = [self readPreferenceValue:spec];
			if ([engine isKindOfClass:[NSString class]] && [engine isEqualToString:@"milkyway"]) break;
			NSMutableArray *kept = [NSMutableArray array];
			BOOL hiding = NO;
			for (PSSpecifier *sp in _specifiers) {
				if (sp.cellType == PSGroupCell) hiding = [sp.identifier isEqualToString:@"RESIZE_GROUP"];
				if (!hiding) [kept addObject:sp];
			}
			_specifiers = kept;
			break;
		}
		// Single Mute installed and switched on: it shows the mute icon and ours steps aside (OtherTweaks.h), so the switch says who does it.
		NSString *muteBy = MSBDOtherTweakDoing(kMSBDDupMuteIcon, NO);
		if (muteBy) for (PSSpecifier *spec in _specifiers) if ([spec.identifier isEqualToString:@"AUDIO_GROUP"])
			[spec setProperty:[NSString stringWithFormat:@"%@ is showing the mute icon.", muteBy] forKey:@"footerText"];
		// Destra showing Mac-style banners: ours steps aside (both at once squeezed every banner), so the group says who does it.
		NSString *bannersBy = MSBDOtherTweakDoing(kMSBDDupBanners, NO);
		if (bannersBy) for (PSSpecifier *spec in _specifiers) if ([spec.identifier isEqualToString:@"BANNERS_GROUP"])
			[spec setProperty:[NSString stringWithFormat:@"%@ is showing Mac-style banners.", bannersBy] forKey:@"footerText"];
		// Lynx hiding the Lock Screen status bar: ours steps aside (LockStatusBar.x), so the group says who does it.
		NSString *lockBy = MSBDOtherTweakDoing(kMSBDDupLockStatusBar, NO);
		if (lockBy) for (PSSpecifier *spec in _specifiers) if ([spec.identifier isEqualToString:@"LOCK_GROUP"])
			[spec setProperty:[NSString stringWithFormat:@"%@ is hiding the Lock Screen status bar. %@", lockBy, [spec propertyForKey:@"footerText"] ?: @""] forKey:@"footerText"];
		if (MSBStockBarStored()) {   // stock status bar: what only our status bar and windows use is hidden
			NSMutableArray *kept = [NSMutableArray array];
			BOOL hiding = NO;
			PSSpecifier *report = nil;
			for (PSSpecifier *spec in _specifiers) {
				if (spec.cellType == PSGroupCell) hiding = [[spec propertyForKey:@"stockHides"] boolValue];
				if ([spec.identifier isEqualToString:@"REPORT_PROBLEM"]) report = spec;
				if (!hiding) [kept addObject:spec];
			}
			// Report a Problem stays reachable: its own group at the end (its usual group is about windows, hidden here)
			if (report && ![kept containsObject:report] && ![[kept valueForKey:@"identifier"] containsObject:@"MSBD_GUARD_REPORT"]) {
				[kept addObject:[PSSpecifier groupSpecifierWithID:@"STOCK_REPORT_GROUP"]];
				[kept addObject:report];
			}
			_specifiers = kept;
		}
		_specifiers = [self msbd_hideRowsWhenLineOff:_specifiers offFooter:@"Everything except the Dock is off. Turn it on to change its settings. Takes effect after a respring."];
		// The last SpringBoard crash (24 h) was another tweak's: one quiet line at the bottom of the page, nothing else (CrashExplain.h).
		NSString *other = MSBDOtherTweakCrashNote();
		if (other) {
			PSSpecifier *note = [PSSpecifier groupSpecifierWithID:@"MSBD_OTHER_CRASH"];
			[note setProperty:other forKey:@"footerText"];
			_specifiers = [[_specifiers arrayByAddingObject:note] mutableCopy];
		}
	}
	return _specifiers;
}

// The saved engine can name one this device does not offer (MilkyWay4 saved before an update to iPadOS 16, or an engine since removed): the tweak
// then runs the default one (DMActiveEngine / MSBDDefaultEngine), so that is the one shown as picked (an untested Aerial too, greyed "(untested version)").
- (id)readPreferenceValue:(PSSpecifier *)specifier {
	if ([[specifier propertyForKey:@"key"] isEqual:@"stockStatusBar"]) return MSBStockBarStored() ? @"stock" : @"mac";   // the row and its picker page show/pick these two strings
	id value = [super readPreferenceValue:specifier];
	if (![[specifier propertyForKey:@"key"] isEqual:@"windowEngine"]) return value;
	NSArray *offered = [specifier respondsToSelector:NSSelectorFromString(@"values")] ? ((id (*)(id, SEL))objc_msgSend)(specifier, NSSelectorFromString(@"values")) : nil;
	if ([value isKindOfClass:[NSString class]] && [offered containsObject:value] && MSBEngineState(value) == 2) return value;
	// Nothing usable picked (none, not offered, not installed, or an untested build, which SpringBoard skips too): the same single rule as SpringBoard and the helper (EngineBuilds.h: Aerial of any build, else MilkyWay4, else Zetsu).
	NSString *fallback = MSBDDefaultEngine(^BOOL(NSString *e) { return MSBEngineState(e) != 0; }, ^NSString *(NSString *lib) { return MSBEngineLibraryPath(lib); });
	return fallback ?: @"none";   // ("none": no engine at all, shown as "None", see -specifiers)
}
// Picking a Window Engine: Mac Status Bar's own preference is saved as before, then the other engines are stopped from loading (see above).
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	[self msbd_noteSwitch:value specifier:specifier];   // (crash guard: LineSwitch.h)
	if ([[specifier propertyForKey:@"key"] isEqual:@"stockStatusBar"]) {   // "mac"/"stock" from the picker page; still stored under the same bool key
		BOOL on = [value isKindOfClass:[NSString class]] && [value isEqualToString:@"stock"];
		if (on == MSBStockBarStored()) return;   // the already-picked choice was tapped again
		MSBSetStockBarStored(on);
		// (the helper applies engine exclusivity for the new style before the respring: in stock mode the chosen engine loads even with windowing
		// switched off in Mac mode, and back in Mac mode that switch counts again -- sshtoggled ChosenEngine)
		if (MSBDGateWanted() && access("/var/jb/usr/libexec/sshtoggled", X_OK) == 0) notify_post("com.besiktasliseba.msb.engines.apply");
		int guardAction = MSBDGuardAction();   // (back to Mac after the crash guard picked Stock: its note goes, as a switch change ends it; LineSwitch.h)
		if (!on && !MSBDSafeMode() && ((MSBDVersionTested() && guardAction == 1) || (guardAction == 4 && !MSBDStepPartsOff(MSBDCrashRecord())))) {
			CFPreferencesSetValue(CFSTR(MSBD_GUARD_ACTION_KEY), NULL, MSBD_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
			CFPreferencesSynchronize(MSBD_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
		}
		[self msb_stockChanged:on];
		return;
	}
	[super setPreferenceValue:value specifier:specifier];
	// Enable Windowing off = no window engine loads at all (MacSettings' root helper denies them all in Choicy / renames them for iCleaner Pro; on
	// again, only the chosen one comes back). Its footer says it takes effect after a respring. An engine picked while windowing is off is only
	// saved; the helper applies it when windowing is on again.
	if (!MSBDGateWanted()) return;   // (untested iPadOS / safe mode: the rows are greyed; nothing may change Choicy or the engines -- LineSwitch.h)
	BOOL helper = access("/var/jb/usr/libexec/sshtoggled", X_OK) == 0;
	if ([[specifier propertyForKey:@"key"] isEqual:@"windowingEnabled"]) {
		if (helper) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ notify_post("com.besiktasliseba.msb.engines.apply"); });
		BOOL on = [value boolValue];   // (the respring is offered like every other change that needs one)
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Respring to Finish" message:on ? @"Windowing turns on after a respring." : @"Windowing turns off after a respring." preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:@"Respring Now" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ MSBRespring(); });   // (after the helper's 0.4 s)
		}]];
		[alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
		[self presentViewController:alert animated:YES completion:nil];
		return;
	}
	if (![[specifier propertyForKey:@"key"] isEqual:@"windowEngine"] || ![value isKindOfClass:[NSString class]]) return;
	dispatch_async(dispatch_get_main_queue(), ^{ _specifiers = nil; [self reloadSpecifiers]; });   // (rows that depend on the engine: Resize Apps to Fit Windows)
	CFPreferencesAppSynchronize(kMSBBarDomain);
	CFPropertyListRef w = CFPreferencesCopyValue(CFSTR("windowingEnabled"), kMSBBarDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	BOOL windowingOff = w && CFGetTypeID(w) == CFBooleanGetTypeID() && !CFBooleanGetValue(w);
	if (w) CFRelease(w);
	if (windowingOff) return;
	NSString *engine = value;
	NSDictionary *names = @{@"aerial": @"Aerial", @"milkyway": @"MilkyWay4", @"zetsu": @"Zetsu", @"stagemanager": @"Stage Manager"};
	NSString *title = nil, *message = nil; BOOL offerRespring = NO, offerICleaner = NO;
	if (MSBChoicyInstalled()) {
		if (MSBChoicyApplyEngine(engine)) {
			NSMutableOrderedSet *others = [NSMutableOrderedSet orderedSet];   // (engine names, not library names: MilkyWay3SubModule is part of MilkyWay4)
			for (NSString *l in MSBOtherEngineLibraries(engine)) [others addObject:[l hasPrefix:@"MilkyWay"] ? @"MilkyWay4" : l];
			title = @"Respring to Switch Engines";
			message = others.count ? [NSString stringWithFormat:@"Choicy now stops loading %@, so only %@ runs. The change takes effect after a respring.", [others.array componentsJoinedByString:@", "], names[engine] ?: engine]
			                       : [NSString stringWithFormat:@"Only %@ runs. The change takes effect after a respring.", names[engine] ?: engine];
			offerRespring = YES;
		}
	} else if (MSBiCleanerInstalled() && access("/var/jb/usr/libexec/sshtoggled", X_OK) == 0) {
		// MacSettings' root helper does iCleaner's renaming for us (it re-reads the choice from our preferences itself; see sshtoggled/main.m)
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ notify_post("com.besiktasliseba.msb.engines.apply"); });
		title = @"Respring to Switch Engines";
		message = [NSString stringWithFormat:@"Only %@ will load after a respring.", names[engine] ?: engine];
		offerRespring = YES;
	} else if (MSBiCleanerInstalled()) {
		NSMutableArray *on = [NSMutableArray array];
		for (NSString *l in MSBOtherEngineLibraries(engine)) if (MSBLibraryPresent(l, @"dylib")) [on addObject:l];
		NSMutableArray *off = [NSMutableArray array];
		for (NSString *l in MSBEngineLibraries()[engine]) if (!MSBLibraryPresent(l, @"dylib") && MSBLibraryPresent(l, @"disabled")) [off addObject:l];
		if (on.count || off.count) {
			title = @"Switch engines in iCleaner Pro";
			NSMutableString *m = [NSMutableString stringWithString:@"iCleaner Pro manages which tweaks load. In iCleaner Pro > Tweaks,"];
			if (on.count) [m appendFormat:@" switch OFF: %@.", [on componentsJoinedByString:@", "]];
			if (off.count) [m appendFormat:@"%@ switch ON: %@.", on.count ? @" Then" : @"", [off componentsJoinedByString:@", "]];
			[m appendString:@" Then respring."];
			message = m; offerICleaner = YES;
		}
	} else {
		title = @"Choicy is needed";
		message = @"Install Choicy (or iCleaner Pro) so MacStatusBar&Dock can stop the other window engines from loading. Until then every installed engine loads.";
	}
	if (!title) return;
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
	if (offerRespring) [alert addAction:[UIAlertAction actionWithTitle:@"Respring Now" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { MSBRespring(); }]];
	if (offerICleaner) [alert addAction:[UIAlertAction actionWithTitle:@"Open iCleaner Pro" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
		[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"icleaner://"] options:@{} completionHandler:nil];
	}]];
	[alert addAction:[UIAlertAction actionWithTitle:offerRespring ? @"Later" : @"OK" style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

@end
