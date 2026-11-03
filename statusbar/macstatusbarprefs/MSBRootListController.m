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
#import "../../common/AppleMultitasking.h"   // (Apple's multitasking settings on the Windows & Multitasking page, 1.6.0: AppleMultitaskingTable.h)
#import "../../common/EngineBuilds.h"
#import "../../common/StageManagerAvailable.h"
#import "../../common/DesktopCheck.h"   // (Show Desktop Icons on iPadOS 17+: SpringBoard's check of the Home Screen parts the desktop uses)
#import "../../common/OtherTweaks.h"   // (Single Mute showing the mute icon: said under the Audio group)
#import "../SMSwitchOn.h"   // (DMSMConsentFrom: the stored Stage Manager answers, read as SpringBoard reads them)
#import "../../common/MenuBarSize.h"   // (Menu Bar Size, 1.7.3: the stored value read as SpringBoard reads it)
#import "../../common/DesktopIconSize.h"   // (the desktop's Icon Size, 1.7.5: its range, steps and the size in force, as SpringBoard reads them)
#import "../../common/DesktopAppCorner.h"   // (the desktop's App Icon Corner Radius, 1.7.9: its steps, the Home Screen's shape SpringBoard published)
#import "../../common/PrewarmArmed.h"   // (Prewarm Apps, 1.7.7: offered only where the prewarm block in dasd is armed)
#import "../../common/PrewarmDefault.h"   // (Prewarm Apps, 1.7.7: never set, off on a 2 GB iPad and on with more, as SpringBoard reads it)
#import "../../common/TailspinGuard.h"   // (Keep Tailspin Off, 1.7.9: never set, on with 2 GB; offered where the helper found it does something)
#import "../../common/OwnPageState.h"   // (1.7.9: the conditions and rows this page leaves out, shared with the Settings search -- OwnPageRows.h)
@interface PSListController (MSBURL)
- (void)handleURL:(NSDictionary *)url withCompletion:(id)completion;   // (Settings' link to a place on a page: -handleURL:withCompletion: below)
@end

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
// ---- Stage Manager consent (1.5.1, Havoc rule 2.5; statusbar/SMSwitchOn.h) ----
// SpringBoard's reading of Stage Manager (StatusBar.x DMSMPublishOn): 1 on, 2 off, 0 not known.
static int MSBStageManagerOnState(void) {
	int t = 0; uint64_t v = 0;
	if (notify_register_check("com.besiktasliseba.macstatusbar.smon", &t) == NOTIFY_STATUS_OK) { notify_get_state(t, &v); notify_cancel(t); }
	return v <= 2 ? (int)v : 0;
}
// smConsentOn / smHoldConsent (SMSwitchOn.h DMSMConsent: 1 yes, 2 done, 3 no; absent: unasked)
static int MSBStageManagerConsent(CFStringRef key) {
	CFPreferencesAppSynchronize(CFSTR("com.besiktasliseba.macstatusbar"));
	CFPropertyListRef v = CFPreferencesCopyValue(key, CFSTR("com.besiktasliseba.macstatusbar"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	int c = DMSMConsentFrom((__bridge id)v);
	if (v) CFRelease(v);
	return c;
}
static void MSBSetStageManagerConsent(CFStringRef key, int value) {
	CFPreferencesSetValue(key, (__bridge CFNumberRef)@(value), CFSTR("com.besiktasliseba.macstatusbar"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	CFPreferencesSynchronize(CFSTR("com.besiktasliseba.macstatusbar"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	notify_post("com.besiktasliseba.macstatusbar/prefsChanged");   // (SpringBoard reads it again: DMLoadPrefs)
}

// ---- Window Engine list (2026-09-24): every engine this iOS supports is listed; one that is not installed is shown greyed out and cannot be
// picked (stock-looking disabled row), and an installed build our integration has not been tested with is picked as a plain engine that runs on
// its own, without any of our window features, and its row says so (1.5.0; greyed and unselectable before -- the one list of tested builds is
// common/EngineBuilds.h).
// "Installed" = its library is in TweakInject, as .dylib or as iCleaner's .disabled (Choicy's deny list does not make an engine uninstalled).
// 0 = not installed, 1 = installed but not a tested build, 2 = installed and tested
// Stage Manager as the engine (iPadOS 16+): usable where Stage Manager runs -- natively (iPad Pro 2018 and later, M1/M2 iPads: iPad8/13/14,x) or
// through TrollPad on older iPads.
// (and where SpringBoard's self-check of the engine found the system methods it uses missing or different on this iPadOS version, it is not
// offered either: the row greyed, "Not Supported Yet" -- the same verdict as SpringBoard and the root helper, common/StageManagerAvailable.h)
static BOOL MSBStageManagerAvailable(void) { return MSBDStageManagerEngineUsable(); }   // (common/StageManagerAvailable.h)
static BOOL MSBStageManagerUnsupported(NSString **os) {   // (Stage Manager is here, but the engine's self-check failed on this iPadOS build)
	return MSBDStageManagerAvailable() && MSBDStageManagerVerdict(NULL, os) == 0;
}
#if DEBUG
// (debug: /tmp/msb-engine-notinstalled names engines to show as not installed -- the GET button --, "<engine>-untested" as an untested build, and
//  "stagemanager" as an iPad without Stage Manager: its row greyed and the why under the Native group, 1.5.2)
static NSString *MSBEnginePretend(void) { return [NSString stringWithContentsOfFile:@"/tmp/msb-engine-notinstalled" encoding:NSUTF8StringEncoding error:nil]; }
#endif
// (the rule, the debug pretend file included, is common/OwnPageState.h's: the Settings search asks the same one for the Windows group's rows)
static int MSBEngineState(NSString *engine) { return MSBDEngineState(engine); }
// An installed build our integration has not been tested with is still the user's to pick (1.5.0): it runs on its own -- MacStatusBar&Dock
// doesn't drive its windows, but it never keeps it from loading either. Greyed and unselectable until 1.4.5, so an engine update (Aerial 5.1)
// could not be picked, our exclusivity kept it out of SpringBoard, and its license (checked in SpringBoard) could not be activated (24 Oct).
static NSString *MSBEngineName(NSString *engine) {
	return @{@"aerial": @"Aerial", @"milkyway": @"MilkyWay4", @"zetsu": @"Zetsu", @"stagemanager": @"Stage Manager"}[engine] ?: engine;
}
static NSString *MSBEngineNameVersion(NSString *engine) {   // ("Aerial 5.1": the installed package's version)
	NSString *pkg = @{@"aerial": @"jp.uzra.aerial", @"milkyway": @"jp.akusio.milkyway4", @"zetsu": @"jp.dcsyhi.zetsu"}[engine];
	NSString *v = pkg ? MSBDPackageVersion(pkg) : nil;
	return v.length ? [NSString stringWithFormat:@"%@ %@", MSBEngineName(engine), v] : MSBEngineName(engine);
}
// The Window Engine page's footer: a license is checked in SpringBoard, and only the picked engine loads there.
static NSString *const kMSBLicenseHint = @"Activating an engine's license? Pick it here and respring first: only the picked engine loads, and its license is checked in SpringBoard.";
// The engine a row of the Window Engine page stands for: PSListItemsController gives each row specifier its value as its only value (-itemsFromParent).
static NSString *MSBEngineValueOf(PSSpecifier *s) {
	SEL vs = NSSelectorFromString(@"values");
	id v = s && s.cellType != PSGroupCell && [s respondsToSelector:vs] ? ((id (*)(id, SEL))objc_msgSend)(s, vs) : nil;
	id x = [v isKindOfClass:[NSArray class]] ? [(NSArray *)v firstObject] : nil;
	return [x isKindOfClass:[NSString class]] ? x : nil;
}
// The engine the Window Engine row shows as picked (-readPreferenceValue: below): the stored one when this iPadOS offers it and it is installed (an
// untested build too: it is the one that loads, on its own); else the same single rule as SpringBoard and the helper (EngineBuilds.h: Aerial of any
// build, else MilkyWay4, else Zetsu); "none" with no engine at all.
static NSString *MSBEngineShown(id value, NSArray *offered) { return MSBDEngineShown(value, offered); }   // (common/OwnPageState.h)
// The same without the row (1.6.0: the row is on the Windows & Multitasking page, Report a Problem stays on the Status Bar page): the stored value or
// the row's default, and the row's values (Windows.plist) less what -specifiers takes out on this iPadOS (Stage Manager before 16, MilkyWay4 on 16+).
static NSString *MSBEngineShownWithoutRow(void) { return MSBDEngineShownWithoutRow(); }   // (common/OwnPageState.h: the search asks the same)
@interface MSBEngineListController : PSListItemsController
@end
@implementation MSBEngineListController
// The page in two groups (1.5.2, KT): "Native" -- Stage Manager, Apple's own windowing, natively or through TrollPad: on iPadOS 16 and later, its row
// greyed where it can't run yet, with why under it -- and "Third-Party" -- the engines to install, as this iPad offers them, with the license hint
// under them. A group with no row is left out (iPadOS 15: no Native). PSListItemsController makes one group of the row's values (-itemsFromParent);
// its own row specifiers are regrouped here. Its checkmark and pick go by the specifier's place in the whole list (-setRowToSelect,
// -indexForIndexPath:, -listItemSelected:, read on 18.5), so they follow a row into the second group once the selected row is worked out again.
- (NSMutableArray *)specifiers {
	if (!_specifiers) {
		NSArray *flat = [super specifiers];
		NSMutableArray *native = [NSMutableArray array], *thirdParty = [NSMutableArray array];
		NSUInteger groups = 0;
		for (PSSpecifier *s in flat) {
			if (s.cellType == PSGroupCell) { groups++; continue; }
			[([MSBEngineValueOf(s) isEqualToString:@"stagemanager"] ? native : thirdParty) addObject:s];
		}
		if (groups == 1 && flat.count && ((PSSpecifier *)flat[0]).cellType == PSGroupCell) {   // (the one-group page it makes; anything else stays as it is)
			NSMutableArray *grouped = [NSMutableArray array];
			if (native.count) {
				PSSpecifier *g = [PSSpecifier groupSpecifierWithID:@"MSB_ENGINE_NATIVE"];
				g.name = @"Native";
				NSString *why = MSBDStageManagerFooter();   // (nil where Stage Manager can be picked)
#if DEBUG
				if ([MSBEnginePretend() containsString:@"stagemanager"]) why = MSBDStageManagerWhyText(2, 1, nil);
#endif
				if (why) [g setProperty:why forKey:@"footerText"];
				[grouped addObject:g];
				[grouped addObjectsFromArray:native];
			}
			if (thirdParty.count) {
				PSSpecifier *g = [PSSpecifier groupSpecifierWithID:@"MSB_ENGINE_THIRD_PARTY"];
				g.name = @"Third-Party";
				[g setProperty:kMSBLicenseHint forKey:@"footerText"];
				[grouped addObject:g];
				[grouped addObjectsFromArray:thirdParty];
			}
			_specifiers = grouped;
			SEL row = NSSelectorFromString(@"setRowToSelect");   // (the checkmark's place in the new order)
			if ([self respondsToSelector:row]) ((void (*)(id, SEL))objc_msgSend)(self, row);
		}
	}
	return _specifiers;
}
- (NSString *)msb_valueForRow:(NSIndexPath *)ip {   // (by the row's specifier, whichever group it is in)
	NSInteger i = [self indexForIndexPath:ip];
	return i >= 0 && i < (NSInteger)_specifiers.count ? MSBEngineValueOf(_specifiers[i]) : nil;
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *cell = [super tableView:tv cellForRowAtIndexPath:ip];
	NSString *v = [self msb_valueForRow:ip];
	int state = v ? MSBEngineState(v) : 2;
	BOOL usable = state >= 1;   // (an untested build too: it runs on its own, and the row says so)
	cell.userInteractionEnabled = usable || state == 0;   // (a not-installed row stays greyed and unselectable, but its GET button can be tapped)
	cell.selectionStyle = usable ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
	cell.textLabel.enabled = usable;
	if (state == 1) cell.textLabel.text = [NSString stringWithFormat:@"%@ (Untested, Runs on Its Own)", MSBEngineNameVersion(v)];   // (never "Recommended": not tested)
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
	} else if ([v isEqualToString:@"stagemanager"] && MSBDStageManagerAvailable() && MSBDStageManagerVerdict(NULL, NULL) != 1) {   // (greyed, and why, where the checkmark would be)
		UILabel *why = [UILabel new];
		why.text = MSBStageManagerUnsupported(NULL) ? @"Not Supported Yet" : @"Respring to Check";   // (not checked on this build: SpringBoard checks at its start)
		why.font = [UIFont systemFontOfSize:15.0];
		why.textColor = [UIColor secondaryLabelColor];
		[why sizeToFit];
		cell.accessoryView = why;
	} else cell.accessoryView = nil;
	return cell;
}
- (NSIndexPath *)tableView:(UITableView *)tv willSelectRowAtIndexPath:(NSIndexPath *)ip {
	NSString *v = [self msb_valueForRow:ip];
	return (v && MSBEngineState(v) == 0) ? nil : ip;   // (not installed only: an untested build is picked as a plain engine)
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
static BOOL MSBStockBarStored(void) { return MSBDStockBarStored(); }   // (common/OwnPageState.h: the Settings search reads it the same way)
static void MSBSetStockBarStored(BOOL on) {
	CFPreferencesSetValue(CFSTR("stockStatusBar"), on ? kCFBooleanTrue : kCFBooleanFalse, kMSBBarDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	CFPreferencesSynchronize(kMSBBarDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	notify_post("com.besiktasliseba.macstatusbar/prefsChanged");
}

// The desktop's Icon Size (1.7.5 item 4): the stored number (nil: never set -- the Home Screen's own size, as before), and what the slider shows.
static NSNumber *MSBDesktopIconStored(void) {
	CFPreferencesAppSynchronize(kMSBBarDomain);
	CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR(MSBD_DESKTOP_ICON_KEY), kMSBBarDomain);
	NSNumber *n = v && CFGetTypeID(v) == CFNumberGetTypeID() ? [(__bridge NSNumber *)v copy] : nil;
	if (v) CFRelease(v);
	return n;
}
static uint64_t MSBDesktopHomeState(void) {   // (the Home Screen's icon side as SpringBoard published it, quarter points; 0 unknown)
	static int token = 0;
	if (!token && notify_register_check(MSBD_DESKTOP_HOMESIDE_STATE, &token) != NOTIFY_STATUS_OK) token = 0;
	uint64_t home = 0;
	if (token) notify_get_state(token, &home);
	return home;
}
static double MSBDesktopIconShownNow(void) {
	NSNumber *n = MSBDesktopIconStored();
	return MSBDDesktopIconShown(n != nil, n.doubleValue, MSBDesktopHomeState());
}
// The step written last while the slider is dragged (-1: none yet, read from the store at the first move): the store is not asked at every move
// (each read is a round trip to the preferences daemon, many a second -- 1.7.5 review). 0: "the Home Screen's", nothing stored.
static double gMSBDesktopIconWritten = -1;

// The desktop's App Icon Corner Radius (1.7.9 item 4): the stored fraction (nil: never set -- the Home Screen's shape, followed as it changes), the
// Home Screen's shape as SpringBoard published it, and what the slider shows. Moving the slider always stores the user's own corner, even where the
// Home Screen's is (KT 2 Nov: a later theme change must leave it alone); only Match Home Screen Icons removes it.
static NSNumber *MSBDesktopCornerStored(void) {
	CFPreferencesAppSynchronize(kMSBBarDomain);
	CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR(MSBD_DESKTOP_CORNER_KEY), kMSBBarDomain);
	NSNumber *n = v && CFGetTypeID(v) == CFNumberGetTypeID() ? [(__bridge NSNumber *)v copy] : nil;
	if (v) CFRelease(v);
	return n;
}
static uint64_t MSBDesktopThemeCornerNow(void) {
	static int token = 0;
	if (!token && notify_register_check(MSBD_DESKTOP_THEMECORNER_STATE, &token) != NOTIFY_STATUS_OK) token = 0;
	uint64_t state = 0;
	if (token) notify_get_state(token, &state);
	return state;
}
static double MSBDesktopCornerShownNow(void) {
	NSNumber *n = MSBDesktopCornerStored();
	return MSBDDesktopCornerShown(n != nil, n.doubleValue, MSBDesktopThemeCornerNow());
}
static double gMSBDesktopCornerWritten = -2;   // (the step written last while the slider is dragged; -2 not read yet, -1 nothing stored)

// Prewarm Apps as SpringBoard reads it (common/PrewarmDefault.h): a boolean stored, else the default for this iPad's RAM -- off with 2 GB (1.7.7).
// The switch shows that (-readPreferenceValue: below); the default is never written, only a tap stores a value.
static BOOL MSBPrewarmAppsInForce(void) {
	CFPreferencesAppSynchronize(kMSBBarDomain);
	CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("prewarmApps"), kMSBBarDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	int stored = MSBDPrewarmAppsStored(v);
	if (v) CFRelease(v);
	return MSBDPrewarmAppsOn(stored, MSBDPrewarmRAM()) != 0;
}
// Keep Tailspin Off as the root helper applies it (common/TailspinGuard.h): a boolean stored, else on with 2 GB of RAM (1.7.9). The same way.
static BOOL MSBTailspinOffInForce(void) {
	CFPreferencesAppSynchronize(kMSBBarDomain);
	CFPropertyListRef v = CFPreferencesCopyValue(CFSTR(kMSBDTailspinKey), kMSBBarDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	int stored = MSBDTailspinOffStored(v);
	if (v) CFRelease(v);
	return MSBDTailspinOffOn(stored, MSBDPrewarmRAM()) != 0;
}

// ---- Menu Bar Size (1.7.3, common/MenuBarSize.h): a "Menu Bar Size" row (Small / Medium / Large) in the Status Bar group, opening a three-item picker
// page (Root.plist: PSLinkListCell, PSListItemsController, key menuBarSize, validValues 0 / 1 / 2). Stored as a number, so the crash guard can set it
// back as it does a switch (false): -readPreferenceValue: below shows anything that is not 1 or 2 as Small, as SpringBoard reads it
// (MSBDMenuBarSizeFrom). SpringBoard sizes iOS's bar once, when it starts (StatusBar.x DMBarSizeInit), so a change offers a respring, as Status Bar
// Style does. With the stock status bar the row is hidden with its group (stockHides).
static int MSBMenuBarSizeStored(void) {
	CFPreferencesAppSynchronize(kMSBBarDomain);
	CFPropertyListRef v = CFPreferencesCopyValue(CFSTR(kMSBDMenuBarSizeKey), kMSBBarDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	double d = 0.0; int isNumber = 0;
	if (v) { if (CFGetTypeID(v) == CFNumberGetTypeID()) isNumber = CFNumberGetValue((CFNumberRef)v, kCFNumberDoubleType, &d); CFRelease(v); }
	return MSBDMenuBarSizeFrom(isNumber, d);
}

// ---- Two pages, one controller (1.6.0, KT): the Status Bar page (Root.plist) and the Windows & Multitasking page (Windows.plist: Windowing, Window
// Engine with its notes and Turn On Stage Manager, Windows, Resize Apps to Fit Windows, Traffic Lights, Multitasking), its own row next to Status Bar
// (StatusBarSettingsRow.x). MSBWindowsListController (below) is this controller with the other plist: every rule here works on the rows it finds, so
// each page keeps the rules of its own rows.
@interface MSBRootListController (MSBPages)
- (NSString *)msb_plistName;
- (BOOL)msb_windowsPage;
- (BOOL)msb_desktopPage;
- (BOOL)msb_rootPage;
- (void)msb_prewarmMaybeChanged;
- (void)msb_tailspinMaybeChanged;
@end
// The Windows & Multitasking row is in Settings' list next to ours (StatusBarSettingsRow.x: the sidebar on 15-17, General's group on 18). Where it is
// not -- the row tweak not loaded, or Settings' list not as expected, so this page came from PreferenceLoader's entry --, a link to that page takes
// the place its settings had here, so they can always be reached.
static BOOL MSBWindowsRowListed(void) {
	BOOL (*listed)(void) = (BOOL (*)(void))dlsym(RTLD_DEFAULT, "MSBDWindowsRowListed");
	return listed && listed();
}
static UIImage *MSBWindowsIcon(void) { return [UIImage imageNamed:@"windows" inBundle:[NSBundle bundleForClass:[MSBRootListController class]] compatibleWithTraitCollection:nil]; }
// The Desktop page (1.7.5, KT 31 Oct: the desktop's rows out of the Status Bar page, right after it): the same, by its own row (MAC_DESKTOP).
static BOOL MSBDesktopRowListed(void) {
	BOOL (*listed)(void) = (BOOL (*)(void))dlsym(RTLD_DEFAULT, "MSBDDesktopRowListed");
	return listed && listed();
}
static UIImage *MSBDesktopIcon(void) { return [UIImage imageNamed:@"desktop" inBundle:[NSBundle bundleForClass:[MSBRootListController class]] compatibleWithTraitCollection:nil]; }
// Finder as stored (finderEnabled, on unless set): the desktop is Finder's, so its page notes when Finder is off.
static BOOL MSBFinderStored(void) { return MSBDFinderStored(); }   // (as SpringBoard reads it: common/OwnPageState.h, the Dock page's and the search's too)

@implementation MSBRootListController {
	int _msbConsentToken, _msbSMOnToken;   // (Stage Manager's state and the consent answers, followed while the page exists)
	NSMutableArray *_msbApplePages;   // (the Windows & Multitasking page: Apple's pages whose rows it shows, never shown themselves -- AppleMultitasking.h)
	BOOL _msbPrewarmShown;   // (the Windows & Multitasking page: whether the prewarm block was armed when the list was built -- msb_prewarmMaybeChanged)
	BOOL _msbTailspinShown;   // (... and whether the root helper found Keep Tailspin Off doing something then -- the same)
}
- (NSString *)msb_plistName { return @"Root"; }
- (BOOL)msb_windowsPage { return NO; }
- (BOOL)msb_desktopPage { return NO; }
- (BOOL)msb_rootPage { return ![self msb_windowsPage] && ![self msb_desktopPage]; }   // (the Status Bar page itself)

MSBD_LINE_SWITCH_METHODS

// SpringBoard switched Stage Manager on or off, or a consent answer changed (its question, Apple's introduction): the engine's footer and Turn On Stage
// Manager follow at once, while the page is open (logic test I1).
- (void)viewDidLoad {
	[super viewDidLoad];
	if (!MSBStageManagerAvailable()) return;
	__weak MSBRootListController *weakSelf = self;
	void (^follow)(int) = ^(int t) { MSBRootListController *me = weakSelf; if (!me) return; me->_specifiers = nil; [me reloadSpecifiers]; };
	notify_register_dispatch("com.besiktasliseba.macstatusbar.smconsent", &_msbConsentToken, dispatch_get_main_queue(), follow);
	notify_register_dispatch("com.besiktasliseba.macstatusbar.smon", &_msbSMOnToken, dispatch_get_main_queue(), follow);
}
- (void)dealloc {
	if (_msbConsentToken) notify_cancel(_msbConsentToken);
	if (_msbSMOnToken) notify_cancel(_msbSMOnToken);
}

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

- (void)msb_menuBarSizeChanged:(int)size {
	dispatch_async(dispatch_get_main_queue(), ^{   // (after the picker's own callback)
		NSString *name = size == MSBDMenuBarLarge ? @"Large" : size == MSBDMenuBarMedium ? @"Medium" : @"Small";
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Respring to Finish" message:[NSString stringWithFormat:@"The menu bar changes to %@ after a respring.", name] preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:@"Respring Now" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ MSBRespring(); });
		}]];
		[alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
		[self presentViewController:alert animated:YES completion:nil];
	});
}

- (void)msb_reportProblem:(PSSpecifier *)specifier {
	NSString *engine = MSBEngineShownWithoutRow();   // (the engine that really runs, as the Window Engine row shows it: -readPreferenceValue: below)
	MSBDOpenReport(MSBDReportProblemURL([engine isKindOfClass:[NSString class]] && ![engine isEqualToString:@"none"] ? engine : nil));
}

// The page is opened from a row we add to Settings ourselves, not from a PreferenceLoader entry, so say where the
// bundle is instead of relying on the entry to tell Settings.
- (NSBundle *)bundle {
	return [NSBundle bundleForClass:[MSBRootListController class]];
}

static void MSBURLLog(NSString *line) {   // (debug builds: how a link reached the page, in the Settings probe's log)
#if DEBUG
	FILE *f = fopen("/tmp/msbd-settings.log", "a");
	if (f) { fprintf(f, "%.3f [pageurl] %s\n", CFAbsoluteTimeGetCurrent(), line.UTF8String); fclose(f); }
#else
	(void)line;
#endif
}
// A link to a place on the page (1.6.0, iPadOS 18: SpringBoard's "Edit Go Menu..." and the engine notice's "Choose Engine" open the page by Settings'
// own link, which carries the place -- prefs:root=General&path=MSBD_PL_MacStatusBarPrefs/GO_APPS, or MAC_WINDOWS/WINDOW_ENGINE for the Windows &
// Multitasking page, common/SettingsRoot.h -- as 15-17's main list row is picked by Settings itself): that row's page opens, as a tap does.
// WINDOW_ENGINE on the Status Bar page (an older link) goes on to the Windows & Multitasking page. Any other path goes on as before.
- (void)msb_openRowForPath:(NSString *)path attempt:(int)attempt {
	PSSpecifier *row = nil;
	for (PSSpecifier *sp in [self specifiers]) {
		if ([path isEqualToString:@"GO_APPS"] ? [[sp identifier] isEqualToString:@"GO_APPS"] : [[sp propertyForKey:@"key"] isEqual:@"windowEngine"]) { row = sp; break; }
	}
	NSIndexPath *ip = row ? [self indexPathForSpecifier:row] : nil;
	UITableView *t = [self respondsToSelector:@selector(table)] ? [self table] : nil;
	// (and Settings done moving its pages: on a cold start the link comes twice -- SpringBoard opens it again once Settings is in front -- and Settings
	//  puts its pages back each time; a row opened while it did went with them, so the picker never stayed (A12Z 18.5, cold "Choose Engine").
	//  The page is on top of its navigation stack, directly or inside the controller that hosts it there on 18, and nothing is moving.)
	UINavigationController *nav = self.navigationController;
	UIViewController *mine = self;
	while (mine.parentViewController && mine.parentViewController != nav) mine = mine.parentViewController;
	BOOL settled = self.view.window && (!nav || (nav.topViewController == mine && !nav.transitionCoordinator));
	if (!ip || !t || !settled || ip.section >= t.numberOfSections || ip.row >= [t numberOfRowsInSection:ip.section]) {   // (the page still being pushed and laid out)
		if (attempt == 0 || attempt == 15) MSBURLLog([NSString stringWithFormat:@"%@ %@: try %d, row %d ip %d table %d window %d settled %d", NSStringFromClass([self class]), path, attempt, row != nil, ip != nil, t != nil, self.view.window != nil, settled]);
		__weak MSBRootListController *weakSelf = self;
		if (attempt < 16 || (attempt >= 100 && attempt < 104)) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [weakSelf msb_openRowForPath:path attempt:attempt + 1]; });
		return;
	}
	[t scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
	[self tableView:t didSelectRowAtIndexPath:ip];
	MSBURLLog([NSString stringWithFormat:@"%@ %@: row opened (try %d)", NSStringFromClass([self class]), path, attempt]);
	// (looked at once more a moment later: the page on top again and settled means its row's list was taken away by Settings -- opened again, once)
	if (attempt >= 100) return;
	__weak MSBRootListController *weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		MSBRootListController *me = weakSelf;
		UINavigationController *n = me.navigationController;
		UIViewController *m = me;
		while (m.parentViewController && m.parentViewController != n) m = m.parentViewController;
		if (me && me.view.window && n && n.topViewController == m && !n.transitionCoordinator) { MSBURLLog(@"its list was taken away: opened again"); [me msb_openRowForPath:path attempt:100]; }
	});
}
- (void)handleURL:(NSDictionary *)url withCompletion:(id)completion {
	NSString *path = [url isKindOfClass:[NSDictionary class]] ? url[@"path"] : nil;
	MSBURLLog([NSString stringWithFormat:@"%@ handleURL %@ (in window %d)", NSStringFromClass([self class]), url, self.isViewLoaded && self.view.window != nil]);
	if ([path isEqual:@"WINDOW_ENGINE"] && ![self msb_windowsPage]) {   // (1.6.0: the Window Engine row is on the Windows & Multitasking page)
		__weak MSBRootListController *weakSelf = self;
		dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf msb_openWindowsPageForPath:path]; });
		if (completion) ((void (^)(void))completion)();
		return;
	}
	if ([path isEqual:@"GO_APPS"] || [path isEqual:@"WINDOW_ENGINE"]) {
		__weak MSBRootListController *weakSelf = self;
		dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf msb_openRowForPath:path attempt:0]; });
		if (completion) ((void (^)(void))completion)();
		return;
	}
	// (1.6.0: a link into one of Apple's multitasking rows this page shows -- sent here from Apple's own page, StatusBarSettingsRow.x: scrolled to)
	if ([self msb_windowsPage] && [path isKindOfClass:[NSString class]] && path.length && [self specifiers] && _msbApplePages.count && [self specifierForID:path]) {
		__weak MSBRootListController *weakSelf = self;
		dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf msb_scrollToRowID:path attempt:0]; });
		if (completion) ((void (^)(void))completion)();
		return;
	}
	[super handleURL:url withCompletion:completion];
}
// One of Apple's rows on this page brought into view (its group at the top), once the page is on screen and Settings' navigation has settled.
- (void)msb_scrollToRowID:(NSString *)rowID attempt:(int)attempt {
	PSSpecifier *row = [self specifierForID:rowID];
	NSUInteger at = row ? [_specifiers indexOfObjectIdenticalTo:row] : NSNotFound;
	PSSpecifier *cellRow = row;   // (a group: the first row after it)
	if (row.cellType == PSGroupCell) { cellRow = nil; for (NSUInteger i = at + 1; at != NSNotFound && i < _specifiers.count; i++) { if (((PSSpecifier *)_specifiers[i]).cellType != PSGroupCell) cellRow = _specifiers[i]; break; } }
	NSIndexPath *ip = cellRow ? [self indexPathForSpecifier:cellRow] : nil;
	UITableView *t = [self respondsToSelector:@selector(table)] ? [self table] : nil;
	UINavigationController *nav = self.navigationController;
	UIViewController *mine = self;
	while (mine.parentViewController && mine.parentViewController != nav) mine = mine.parentViewController;
	BOOL settled = self.view.window && (!nav || (nav.topViewController == mine && !nav.transitionCoordinator));
	if (!ip || !t || !settled || ip.section >= t.numberOfSections || ip.row >= [t numberOfRowsInSection:ip.section]) {
		__weak MSBRootListController *weakSelf = self;
		if (attempt < 16) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [weakSelf msb_scrollToRowID:rowID attempt:attempt + 1]; });
		else MSBURLLog([NSString stringWithFormat:@"%@: not scrolled (row %d ip %d settled %d)", rowID, row != nil, ip != nil, settled]);
		return;
	}
	[t layoutIfNeeded];
	CGRect r = row == cellRow ? [t rectForRowAtIndexPath:ip] : [t rectForSection:ip.section];
	CGFloat maxY = MAX(-t.adjustedContentInset.top, t.contentSize.height + t.adjustedContentInset.bottom - t.bounds.size.height);
	[t setContentOffset:CGPointMake(t.contentOffset.x, MIN(MAX(r.origin.y - t.adjustedContentInset.top, -t.adjustedContentInset.top), maxY)) animated:NO];
	MSBURLLog([NSString stringWithFormat:@"%@: scrolled to (try %d, section %ld)", rowID, attempt, (long)ip.section]);
}

// The Windows & Multitasking page pushed from this one, as a tap on its row does (PSListController's own way: the controller for a link specifier,
// shown), then the place on it.
- (void)msb_openWindowsPageForPath:(NSString *)path {
	Class c = NSClassFromString(@"MSBWindowsListController");
	if (!c) return;
	PSSpecifier *link = [PSSpecifier preferenceSpecifierNamed:@"Windows & Multitasking" target:self set:NULL get:NULL detail:c cell:PSLinkCell edit:Nil];
	link.identifier = @"MAC_WINDOWS";
	SEL make = NSSelectorFromString(@"controllerForSpecifier:");
	UIViewController *page = [self respondsToSelector:make] ? ((id (*)(id, SEL, id))objc_msgSend)(self, make, link) : nil;
	if (![page isKindOfClass:c]) return;
	[self showController:(PSViewController *)page animate:NO];
	if (path.length && [page respondsToSelector:@selector(handleURL:withCompletion:)]) [(PSListController *)page handleURL:@{@"path": path} withCompletion:nil];
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
// A link row to one of Apple's pages (17: Multitasking & Gestures by Apple's own link, AppleMultitasking.h): Settings opens it, as a search result.
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	NSInteger i = [self indexForIndexPath:ip];
	PSSpecifier *sp = i >= 0 && i < (NSInteger)_specifiers.count ? _specifiers[i] : nil;
	NSString *link = [sp propertyForKey:@"msbdAppleLink"];
	if ([link isKindOfClass:[NSString class]]) {
		[tv deselectRowAtIndexPath:ip animated:YES];
		MSBURLLog([NSString stringWithFormat:@"Apple's link opened: %@", link]);
		MSAMOpenLink(link);
		return;
	}
	[super tableView:tv didSelectRowAtIndexPath:ip];
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *cell = [super tableView:tv cellForRowAtIndexPath:ip];
	if ([NSStringFromClass([cell class]) containsString:@"Slider"]) {
		MSBFitValueLabels(cell);
		dispatch_async(dispatch_get_main_queue(), ^{ MSBFitValueLabels(cell); });   // (the value label may be made during the first layout)
		// (the desktop's Icon Size, 1.7.5: its value goes out while it is dragged -- the icons follow live -- whatever the cell's own default)
		PSSpecifier *sp = [cell respondsToSelector:@selector(specifier)] ? [(PSTableCell *)cell specifier] : nil;
		if ([[sp propertyForKey:@"key"] isEqual:@MSBD_DESKTOP_ICON_KEY] || [[sp propertyForKey:@"key"] isEqual:@MSBD_DESKTOP_CORNER_KEY]) {   // (and App Icon Corner Radius, 1.7.9)
			NSMutableArray *views = [NSMutableArray arrayWithObject:cell];
			for (NSUInteger k = 0; k < views.count && k < 80; k++) { UIView *v = views[k]; if ([v isKindOfClass:[UISlider class]]) ((UISlider *)v).continuous = YES; else [views addObjectsFromArray:v.subviews]; }
		}
	}
	return cell;
}

- (NSArray *)specifiers {
	if (!_specifiers) {
		_specifiers = [self loadSpecifiersFromPlistName:[self msb_plistName] target:self];
		if ([self msb_rootPage]) {
			NSArray *untested = [self msbd_untestedSpecifiers];   // (on top: "Enable Anyway" on an untested iPadOS version, or the crash guard's note)
			if (untested.count) { NSMutableArray *all = [untested mutableCopy]; [all addObjectsFromArray:_specifiers]; _specifiers = all; }
			if (!MSBWindowsRowListed()) {   // (where the Windows & Multitasking row is not in Settings' list: a link to its page, where its rows were)
				PSSpecifier *g = [PSSpecifier groupSpecifierWithID:@"WINDOWS_LINK_GROUP"];
				[g setProperty:@YES forKey:@"stockHides"];   // (in stock mode that page has only its note: the link goes with the other window rows)
				PSSpecifier *link = [PSSpecifier preferenceSpecifierNamed:@"Windows & Multitasking" target:self set:NULL get:NULL detail:NSClassFromString(@"MSBWindowsListController") cell:PSLinkCell edit:Nil];
				link.identifier = @"MAC_WINDOWS";
				UIImage *icon = MSBWindowsIcon();
				if (icon) [link setProperty:icon forKey:@"iconImage"];
				NSUInteger at = _specifiers.count;
				for (NSUInteger i = 0; i < _specifiers.count; i++) if ([((PSSpecifier *)_specifiers[i]).identifier isEqualToString:@"REPORT_GROUP"]) { at = i; break; }
				NSMutableArray *all = [_specifiers mutableCopy];
				[all insertObjects:@[g, link] atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(at, 2)]];
				_specifiers = all;
			}
			if (!MSBDesktopRowListed()) {   // (the same for the Desktop page: a link in the Finder group, right after Finder, where its rows were)
				PSSpecifier *link = [PSSpecifier preferenceSpecifierNamed:@"Desktop" target:self set:NULL get:NULL detail:NSClassFromString(@"MSBDesktopListController") cell:PSLinkCell edit:Nil];
				link.identifier = @"MAC_DESKTOP";
				UIImage *icon = MSBDesktopIcon();
				if (icon) [link setProperty:icon forKey:@"iconImage"];
				NSUInteger at = NSNotFound;
				for (NSUInteger i = 0; i < _specifiers.count; i++) if ([((PSSpecifier *)_specifiers[i]).identifier isEqualToString:@"FINDER"]) { at = i + 1; break; }
				NSMutableArray *all = [_specifiers mutableCopy];
				if (at != NSNotFound) [all insertObject:link atIndex:at];
				else { [all addObject:[PSSpecifier groupSpecifierWithID:@"DESKTOP_LINK_GROUP"]]; [all addObject:link]; }
				_specifiers = all;
			}
		}
		// The Control Center size only resizes BigSurCenter's own drop-down panel opened from our status bar; with the stock Control Center, or the
		// stock status bar, it does nothing, so then its slider and its footer are left out of the Control Center group (Hide Grabber stays).
		if (!MSBDBigSurCenterInstalled() || MSBStockBarStored()) {   // (common/OwnPageRows.h: the Settings search leaves it out the same way)
			NSMutableArray *kept = [_specifiers mutableCopy];
			for (PSSpecifier *spec in _specifiers) {
				if ([[spec propertyForKey:@"key"] isEqual:kMSBDCCScaleKey]) [kept removeObject:spec];
				if ([spec.identifier isEqualToString:@"CC_GROUP"]) {
					if ([spec respondsToSelector:@selector(removePropertyForKey:)]) [spec removePropertyForKey:@"footerText"]; else [spec setProperty:@"" forKey:@"footerText"];
				}
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
		// The desktop's Icon Size (1.7.5 item 4): a small and a large folder at its ends, the same way, no number (as Apple's own size sliders).
		for (PSSpecifier *spec in _specifiers) {
			if (![[spec propertyForKey:@"key"] isEqual:@"desktopIconSize"]) continue;
			UIImage *small = [UIImage systemImageNamed:@"folder" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightRegular]];
			UIImage *large = [UIImage systemImageNamed:@"folder" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightRegular]];
			small = [small imageWithTintColor:[UIColor secondaryLabelColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
			large = [large imageWithTintColor:[UIColor secondaryLabelColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
			if (small && large) { [spec setProperty:small forKey:@"leftImage"]; [spec setProperty:large forKey:@"rightImage"]; }
		}
		// The desktop's App Icon Corner Radius (1.7.9 item 4): a square and a circle at its ends, the same way. Where an icon theme gives app icons a
		// shape of its own (no rounded square), its footer says what the slider does then (SpringBoard's reading, DesktopAppCorner.h).
		for (PSSpecifier *spec in _specifiers) {
			if ([[spec propertyForKey:@"key"] isEqual:@MSBD_DESKTOP_CORNER_KEY]) {
				UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightRegular];
				UIImage *square = [[UIImage systemImageNamed:@"square" withConfiguration:cfg] imageWithTintColor:[UIColor secondaryLabelColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
				UIImage *circle = [[UIImage systemImageNamed:@"circle" withConfiguration:cfg] imageWithTintColor:[UIColor secondaryLabelColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
				if (square && circle) { [spec setProperty:square forKey:@"leftImage"]; [spec setProperty:circle forKey:@"rightImage"]; }
			}
			int custom = 0;
			if ([spec.identifier isEqualToString:@"DESKTOP_CORNER_GROUP"] && MSBDDesktopThemeCornerFromState(MSBDesktopThemeCornerNow(), &custom) >= 0 && custom) {
				NSString *footer = [spec propertyForKey:@"footerText"];
				if ([footer isKindOfClass:[NSString class]]) [spec setProperty:[footer stringByAppendingString:@"\n\nYour icon theme gives app icons a shape of its own. Moving the slider gives desktop app icons rounded corners instead."] forKey:@"footerText"];
			}
		}
		// The desktop's icons on iPadOS 17+: offered, unless SpringBoard's check of the Home Screen parts they use failed on this iPadOS build
		// (common/DesktopCheck.h) -- then they stay off there and the switch is left out. The Mac Switcher is offered on 17+ (off unless switched on,
		// as everywhere). On 18+ both need SpringBoard's typed keyboard focus lock (StatusBar.x DMFocusLock18OK): left out where its check failed on
		// this build.
		if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 17) {
			// (the conditions and the rows: common/OwnPageState.h, OwnPageRows.h -- the Settings search leaves them out the same way)
			BOOL noFocus18 = MSBDFocusLock18Failed();
			BOOL desktopFailed = MSBDDesktopRowsFailed();
			NSMutableArray *kept = [_specifiers mutableCopy];
			for (PSSpecifier *spec in _specifiers) if ((desktopFailed && MSBDDesktopCheckRow([spec propertyForKey:@"key"], spec.identifier))
			                                           || (noFocus18 && [[spec propertyForKey:@"key"] isEqual:kMSBDMacSwitcherKey])) [kept removeObject:spec];
			if (desktopFailed && [self msb_desktopPage]) for (PSSpecifier *spec in kept) if ([spec.identifier isEqualToString:@"DESKTOP_GROUP"])   // (the page with nothing else: says why)
				[spec setProperty:@"The desktop isn't available on this iPadOS version." forKey:@"footerText"];
			if (noFocus18) {   // (and its group: Go to the App's Desktop, 1.7.1, is the Mac Switcher's)
				BOOL inGroup = NO;
				for (PSSpecifier *spec in _specifiers) {
					if (spec.cellType == PSGroupCell) inGroup = [spec.identifier isEqualToString:kMSBDMacSwitcherGroupID];
					if (inGroup) [kept removeObject:spec];
				}
			}
			_specifiers = kept;
		}
		// Stage Manager as an engine only exists on iPadOS 16+ (and only where Stage Manager runs, MSBEngineState greys it out elsewhere).
		if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion < 16) for (PSSpecifier *spec in _specifiers) {
			if (![[spec propertyForKey:@"key"] isEqual:@"windowEngine"] || ![spec respondsToSelector:NSSelectorFromString(@"values")] || ![spec respondsToSelector:NSSelectorFromString(@"setValues:titles:shortTitles:")]) continue;
			NSArray *v = ((id (*)(id, SEL))objc_msgSend)(spec, NSSelectorFromString(@"values"));
			NSDictionary *td = ((id (*)(id, SEL))objc_msgSend)(spec, NSSelectorFromString(@"titleDictionary"));
			NSDictionary *sd = ((id (*)(id, SEL))objc_msgSend)(spec, NSSelectorFromString(@"shortTitleDictionary"));
			NSMutableArray *values = [NSMutableArray array], *titles = [NSMutableArray array], *shorts = [NSMutableArray array];
			for (NSString *x in v) { if ([x isEqual:@"stagemanager"]) continue; [values addObject:x]; [titles addObject:td[x] ?: x]; [shorts addObject:sd[x] ?: td[x] ?: x]; }
			((void (*)(id, SEL, id, id, id))objc_msgSend)(spec, NSSelectorFromString(@"setValues:titles:shortTitles:"), values, titles, shorts);
			[spec setProperty:kMSBLicenseHint forKey:@"staticTextMessage"];   // (the picker page's footer, as on 16+)
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
					// (1.5.0: no engine is marked any more -- the Stage Manager engine is out of "Experimental" and a first install picks it where it runs,
					//  sshtoggled FreezeOldDefaults; Aerial lost its "Recommended")
					// (sm-160: where the engine's check passed through a way Settings offers as untested -- iPadOS 16.0 -- the row says so; 16.1 is offered normally)
					BOOL untested = [v[i] isEqual:@"stagemanager"] && MSBDStageManagerUntested(NULL);
					[titles addObject:untested ? @"Stage Manager (Untested)" : (td[v[i]] ?: v[i])];
					[shorts addObject:sd[v[i]] ?: td[v[i]] ?: v[i]];
				}
				((void (*)(id, SEL, id, id, id))objc_msgSend)(spec, NSSelectorFromString(@"setValues:titles:shortTitles:"), values, titles, shorts);
				// (the picker page's footer says why Stage Manager is greyed there: no Stage Manager on this iPad, iPadOS 16.0, not checked yet, or not
				//  supported on this iPadOS version -- the row alone said nothing in the first case; staticTextMessage = the list's footer, as on the
				//  Status Bar Style page. Since 1.5.2 MSBEngineListController puts the why under Native and the hint under Third-Party itself; this
				//  one-group footer is what the page shows only if PSListItemsController ever builds it differently)
				NSString *why = MSBDStageManagerFooter();
				[spec setProperty:why ? [NSString stringWithFormat:@"%@\n\n%@", why, kMSBLicenseHint] : kMSBLicenseHint forKey:@"staticTextMessage"];
			}
		}
		// No working engine (none installed, or the one that would run is an untested build, which runs on its own): the Window Engine row says
		// "None" and the Windows group (whose switches only work through an engine) is left out, with a short note (StatusBar.x shows the dots then).
		for (PSSpecifier *spec in [_specifiers copy]) {
			if (![[spec propertyForKey:@"key"] isEqual:@"windowEngine"]) continue;
			NSString *engine = [self readPreferenceValue:spec];
			if ([engine isKindOfClass:[NSString class]] && ![engine isEqualToString:@"none"] && MSBEngineState(engine) == 2) break;
			BOOL onItsOwn = [engine isKindOfClass:[NSString class]] && ![engine isEqualToString:@"none"] && MSBEngineState(engine) == 1;   // (an untested build: runs on its own)
			SEL setShort = NSSelectorFromString(@"setShortTitleDictionary:"), setTitles = NSSelectorFromString(@"setTitleDictionary:");
			if ([spec respondsToSelector:setShort] && [spec respondsToSelector:setTitles] && [engine isKindOfClass:[NSString class]]) {
				NSMutableDictionary *sd = [NSMutableDictionary dictionary];
				NSDictionary *oldShort = [spec respondsToSelector:NSSelectorFromString(@"shortTitleDictionary")] ? ((id (*)(id, SEL))objc_msgSend)(spec, NSSelectorFromString(@"shortTitleDictionary")) : nil;
				NSDictionary *oldTitles = [spec respondsToSelector:NSSelectorFromString(@"titleDictionary")] ? ((id (*)(id, SEL))objc_msgSend)(spec, NSSelectorFromString(@"titleDictionary")) : nil;
				if ([oldShort isKindOfClass:[NSDictionary class]]) [sd addEntriesFromDictionary:oldShort];
				sd[engine] = onItsOwn ? [NSString stringWithFormat:@"%@ (On Its Own)", MSBEngineNameVersion(engine)] : @"None";   // (the row only: the picker's own rows say "Untested, Runs on Its Own")
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
				if (sp.cellType == PSGroupCell) hiding = [sp.identifier isEqualToString:kMSBDWindowsGroupID];
				if ([sp.identifier isEqualToString:@"ENGINE_GROUP"]) [sp setProperty:onItsOwn ? [NSString stringWithFormat:@"%@ hasn't been tested with MacStatusBar&Dock yet, so it runs on its own and the window features are off.", MSBEngineNameVersion(engine)]
				                                                                               : @"No tested window engine is installed, so the window features are off." forKey:@"footerText"];
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
				if (sp.cellType == PSGroupCell) hiding = [sp.identifier isEqualToString:kMSBDWindowsGroupID];
				if ([sp.identifier isEqualToString:@"ENGINE_GROUP"])
					[sp setProperty:MSBStageManagerOnState() == 2 ? @"Stage Manager is off, so apps open full screen. Tap Turn On Stage Manager, or turn it on in Control Center."
					                                               : @"Apple's Stage Manager does the windowing, with the Mac look on top. Other engines are not loaded." forKey:@"footerText"];
				// (the window handles are Stage Manager's own windows' too: their style and tint stay)
				BOOL handles = MSBDHandlesRow([sp propertyForKey:@"key"]);   // (common/OwnPageRows.h)
				if (!hiding || handles || (sp.cellType == PSGroupCell && [sp.identifier isEqualToString:kMSBDWindowsGroupID])) [kept addObject:sp];
				// (Stage Manager off -- the user said Not Now, declined Apple's introduction, or switched it off: nothing is written for them; this button is
				//  their yes, and SpringBoard turns it on -- 1.5.1, consent)
				if (sp == spec && MSBStageManagerOnState() == 2) {
					PSSpecifier *b = [PSSpecifier preferenceSpecifierNamed:@"Turn On Stage Manager" target:self set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
					[b setIdentifier:@"MSB_SM_TURN_ON"];
					b.buttonAction = @selector(msb_turnOnStageManager:);
					[kept addObject:b];
				}
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
		// A third-party engine on an iPad with Stage Manager (1.6.0, the Windows & Multitasking page: one explanation of how the two go together): the
		// engine's footer says what the pick did to Apple's setting (smHoldConsent: kept off while that engine runs, back as it was without windowing).
		// Only for an engine that has a library of its own (Aerial, Zetsu, MilkyWay4): MSBEngineState answers 2 for any other name, "none" too, and
		// with no engine at all this footer took the place of "No tested window engine is installed" (iPad 2 16.7.7: "... while none runs").
		for (PSSpecifier *spec in [_specifiers copy]) {
			if (![[spec propertyForKey:@"key"] isEqual:@"windowEngine"]) continue;
			NSString *engine = [self readPreferenceValue:spec];
			if (!MSBStageManagerAvailable() || ![engine isKindOfClass:[NSString class]] || !MSBEngineLibraries()[engine] || MSBEngineState(engine) != 2) break;
			for (PSSpecifier *sp in _specifiers) if ([sp.identifier isEqualToString:@"ENGINE_GROUP"])
				[sp setProperty:[NSString stringWithFormat:@"Only the chosen engine is loaded. Stage Manager stays off while %@ runs, and comes back as you had it when you turn off windowing.", MSBEngineName(engine)] forKey:@"footerText"];
			break;
		}
		// "Resize Handles" (ours or Stage Manager's) is only a choice with Stage Manager as the engine: the other engines always have ours.
		for (PSSpecifier *spec in [_specifiers copy]) {
			if (![[spec propertyForKey:@"key"] isEqual:@"windowEngine"]) continue;
			NSString *engine = [self readPreferenceValue:spec];
			if ([engine isKindOfClass:[NSString class]] && [engine isEqualToString:@"stagemanager"]) break;
			NSMutableArray *kept = [NSMutableArray array];
			for (PSSpecifier *sp in _specifiers) if (![[sp propertyForKey:@"key"] isEqual:kMSBDResizeHandlesKey]) [kept addObject:sp];
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
				if (sp.cellType == PSGroupCell) hiding = [sp.identifier isEqualToString:kMSBDResizeGroupID];
				if (!hiding) [kept addObject:sp];
			}
			_specifiers = kept;
			break;
		}
		// The Wi-Fi Menu on iPadOS 18+ needs SpringBoard's typed keyboard focus lock for its password sheet (WiFiMenu.h DMWiFiOSOK): its switch is
		// left out where that check failed on this build.
		if (MSBDFocusLock18Failed()) {
			NSMutableArray *kept = [NSMutableArray array];
			BOOL hiding = NO;
			for (PSSpecifier *sp in _specifiers) {
				if (sp.cellType == PSGroupCell) hiding = [sp.identifier isEqualToString:kMSBDWiFiGroupID];
				if (!hiding) [kept addObject:sp];
			}
			_specifiers = kept;
		}
		// Prewarm Apps (1.7.5) works only through the prewarm block in dasd: its group, footer and switch are left out where the block is not armed
		// -- dasd's record of its last start, or no quit set kept by SpringBoard (common/PrewarmArmed.h) --, as the switch would do nothing there
		// (1.7.7 item 5). The Settings search leaves the row out the same way (common/TweakSpotlight.h MTSShownRows).
		if ([self msb_windowsPage]) {
			_msbPrewarmShown = MSBDPrewarmAppsShown() != 0;
			NSMutableArray *kept = [NSMutableArray array];
			BOOL hiding = NO;
			for (PSSpecifier *sp in _specifiers) {
				if (sp.cellType == PSGroupCell) hiding = !_msbPrewarmShown && [sp.identifier isEqualToString:@"PREWARM_GROUP"];
				if (!hiding) [kept addObject:sp];
			}
			_specifiers = kept;
		}
		// Keep Tailspin Off (1.7.9) the same way: its group, footer and switch are left out where the root helper has not found perfdiagsselfenabled
		// reading the key it sets (its state file, common/TailspinGuard.h). The Settings search leaves the row out the same way (MTSShownRows).
		if ([self msb_windowsPage]) {
			_msbTailspinShown = MSBDTailspinRowShown() != 0;
			NSMutableArray *kept = [NSMutableArray array];
			BOOL hiding = NO;
			for (PSSpecifier *sp in _specifiers) {
				if (sp.cellType == PSGroupCell) hiding = !_msbTailspinShown && [sp.identifier isEqualToString:@"TAILSPIN_GROUP"];
				if (!hiding) [kept addObject:sp];
			}
			_specifiers = kept;
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
				if ([spec.identifier isEqualToString:kMSBDReportRowID]) report = spec;
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
		if ([self msb_windowsPage]) _specifiers = [self msb_windowsPageNotes:_specifiers];
		if ([self msb_desktopPage]) _specifiers = [self msb_desktopPageNotes:_specifiers];
		// Apple's own multitasking settings, live and still Apple's, after ours (AppleMultitasking.h: per iPadOS version where Apple keeps them; 16: General's
		// Picture in Picture and Gestures). Only while this page is the place for them -- the same answer that takes Apple's rows out of their page
		// (StatusBarSettingsRow.x) -- and only an entry whose page is there with the rows it must have.
		if ([self msb_windowsPage] && MSAMWanted(MSBWindowsRowListed())) {
			_msbApplePages = [NSMutableArray array];
			NSMutableArray *all = [_specifiers mutableCopy];
			for (NSNumber *n in MSAMSourcesFor(MSAMOS())) {
				if (!MSAMEntryOK(n.intValue)) continue;
				NSArray *rows = MSAMEntryRows(n.intValue, self, _msbApplePages);
				if (rows.count) [all addObjectsFromArray:rows];
			}
			_specifiers = all;
		}
		// Where Apple's page has no rows to show (17, 18: Multitasking & Gestures is a SwiftUI page), a row of ours that opens it: by Apple's own link where
		// Settings has its URL handler (17), else Apple's page shown from here (18). Apple's own row stays; no row where the way to the page is not there.
		if ([self msb_windowsPage] && MSAMPageLive()) {
			NSMutableArray *all = nil;
			for (NSNumber *n in MSAMSourcesFor(MSAMOS())) {
				if (kMSAMSources[n.intValue].kind == MSAMRows) continue;
				PSSpecifier *row = MSAMLinkRowSpecifier(n.intValue, self);
				if (!row) continue;
				if (!all) { all = [_specifiers mutableCopy]; [all addObject:[PSSpecifier groupSpecifierWithID:@"MSAM_LINK_GROUP"]]; }
				[all addObject:row];
			}
			if (all) _specifiers = all;
		}
		// The last SpringBoard crash (24 h) was another tweak's: one quiet line at the bottom of the page, nothing else (CrashExplain.h).
		NSString *other = [self msb_rootPage] ? MSBDOtherTweakCrashNote() : nil;
		if (other) {
			PSSpecifier *note = [PSSpecifier groupSpecifierWithID:@"MSBD_OTHER_CRASH"];
			[note setProperty:other forKey:@"footerText"];
			_specifiers = [[_specifiers arrayByAddingObject:note] mutableCopy];
		}
		[self msb_updateSearchTweaksRow:NO];
		[self msb_updateGoToDesktopRow:NO];
		[self msb_updateDesktopNamesRow:NO];
	}
	return _specifiers;
}
// The Windows & Multitasking page when its rows cannot work: MacStatusBar off (its switch is on the Status Bar page) -- only a note, as that page
// shows only its switch then; the stock status bar -- its rows are left out as on the Status Bar page (stockHides), and a note says what runs;
// MacStatusBar&Dock not running on this iPadOS version or in safe mode -- the rows are greyed (msbd_hideRowsWhenLineOff), a note says where to look.
- (NSMutableArray *)msb_windowsPageNotes:(NSArray *)specs {
	NSString *why = nil;
	if (!MSBDLineEnabled(@"MacStatusBar")) why = @"MacStatusBar is off, and with it the window features. Turn it on in Status Bar to change these settings. Takes effect after a respring.";
	else if (MSBStockBarStored()) why = @"With the stock status bar, your window engine works on its own, with its own settings.";
	else if (!MSBDGateWanted()) why = @"MacStatusBar&Dock is not running right now, so these settings can't be changed. See Status Bar.";
	if (!why) return [specs mutableCopy];
	PSSpecifier *note = [PSSpecifier groupSpecifierWithID:@"MSB_WINDOWS_NOTE"];
	[note setProperty:why forKey:@"footerText"];
	if (MSBDLineEnabled(@"MacStatusBar") && !MSBStockBarStored()) return [[@[note] arrayByAddingObjectsFromArray:specs] mutableCopy];   // (greyed rows below)
	// (Keep Tailspin Off stays under the note: the root helper applies it whatever the status bar does -- no stockHides on its group)
	NSMutableArray *kept = [@[note] mutableCopy];
	BOOL tailspin = NO;
	for (PSSpecifier *sp in specs) {
		if (sp.cellType == PSGroupCell) tailspin = MSBDBarOffKeepsGroup(sp.identifier);   // (common/OwnPageRows.h: Keep Tailspin Off's group)
		if (tailspin) [kept addObject:sp];
	}
	return kept;
}
// The Desktop page (1.7.5) when its rows cannot work: MacStatusBar off -- only a note, as on the Windows & Multitasking page; MacStatusBar&Dock not
// running on this iPadOS version or in safe mode -- the rows greyed (msbd_hideRowsWhenLineOff) under a note; Finder off -- the desktop is Finder's,
// so a note and the rows greyed (msb_updateDesktopNamesRow). The stock status bar keeps the desktop: nothing to say then.
- (NSMutableArray *)msb_desktopPageNotes:(NSArray *)specs {
	NSString *why = nil;
	BOOL onlyNote = !MSBDLineEnabled(@"MacStatusBar");
	if (onlyNote) why = @"MacStatusBar is off, and with it the desktop. Turn it on in Status Bar to change these settings. Takes effect after a respring.";
	else if (!MSBDGateWanted()) why = @"MacStatusBar&Dock is not running right now, so these settings can't be changed. See Status Bar.";
	else if (!MSBFinderStored()) why = @"Finder is off, so the desktop is off too. Turn on Finder in Status Bar.";
	if (!why) return [specs mutableCopy];
	PSSpecifier *note = [PSSpecifier groupSpecifierWithID:@"MSB_DESKTOP_NOTE"];
	[note setProperty:why forKey:@"footerText"];
	if (onlyNote) return [@[note] mutableCopy];
	return [[@[note] arrayByAddingObjectsFromArray:specs] mutableCopy];   // (greyed rows below)
}

// "Include Tweak Settings" adds to the search field's results: greyed while "Search Field in Settings" is off (as Apple greys a row that depends on
// another switch), live when that switch changes.
- (void)msb_updateSearchTweaksRow:(BOOL)reload {
	CFPreferencesAppSynchronize(CFSTR("com.besiktasliseba.macsettings"));
	CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("sidebarSearch"), CFSTR("com.besiktasliseba.macsettings"));
	BOOL field = !(v && CFGetTypeID(v) == CFBooleanGetTypeID() && !CFBooleanGetValue(v));   // (never set: on)
	if (v) CFRelease(v);
	if (!MSBDGateWanted()) field = NO;   // (untested iPadOS / safe mode: every row greyed, LineSwitch.h -- this one stays so)
	for (PSSpecifier *spec in _specifiers) {
		if (![spec.identifier isEqualToString:@"SEARCH_TWEAK_SETTINGS"]) continue;
		[spec setProperty:@(field) forKey:@"enabled"];
		if (reload) [self reloadSpecifier:spec animated:YES];
		break;
	}
}

// "Go to the App's Desktop" (1.7.1) is the Mac Switcher's: greyed while the Mac Switcher is off (as Apple greys a row that depends on another
// switch), live when that switch changes -- as Include Tweak Settings above.
- (void)msb_updateGoToDesktopRow:(BOOL)reload {
	CFPreferencesAppSynchronize(kMSBBarDomain);
	CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("macSwitcher"), kMSBBarDomain);
	BOOL on = v && CFGetTypeID(v) == CFBooleanGetTypeID() && CFBooleanGetValue(v);   // (never set: off)
	if (v) CFRelease(v);
	if (!MSBDGateWanted()) on = NO;   // (untested iPadOS / safe mode: every row greyed, LineSwitch.h -- this one stays so)
	for (PSSpecifier *spec in _specifiers) {
		if (![spec.identifier isEqualToString:@"MSW_GO_TO_APP_DESKTOP"]) continue;
		[spec setProperty:@(on) forKey:@"enabled"];
		if (reload) [self reloadSpecifier:spec animated:YES];
		break;
	}
}

// "Hide Desktop Icon Names" (1.7.2) and Icon Size (1.7.5) are the desktop's: greyed while Finder or Show Desktop Icons is off (both on unless set),
// live when either changes -- as Go to the App's Desktop above. On the Desktop page (1.7.5) Show Desktop Icons itself is greyed while Finder is off
// (the page's note says why: Finder is on the Status Bar page).
- (void)msb_updateDesktopNamesRow:(BOOL)reload {
	CFPreferencesAppSynchronize(kMSBBarDomain);
	BOOL finder = MSBFinderStored(), on = finder;
	CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("desktopIcons"), kMSBBarDomain);
	if (v && CFGetTypeID(v) == CFBooleanGetTypeID() && !CFBooleanGetValue(v)) on = NO;   // (never set: on)
	if (v) CFRelease(v);
	if (!MSBDGateWanted()) on = finder = NO;   // (untested iPadOS / safe mode: every row greyed, LineSwitch.h -- these stay so)
	for (PSSpecifier *spec in _specifiers) {
		BOOL icons = [spec.identifier isEqualToString:@"DESKTOP_ICONS"];
		if (!icons && ![spec.identifier isEqualToString:@"DESKTOP_HIDE_NAMES"] && ![spec.identifier isEqualToString:@"DESKTOP_ICON_SIZE"]
		    && ![spec.identifier isEqualToString:@"DESKTOP_APP_CORNER"]) continue;
		if (icons && ![self msb_desktopPage]) continue;
		[spec setProperty:@(icons ? finder : on) forKey:@"enabled"];
		if (reload) [self reloadSpecifier:spec animated:YES];
	}
	[self msb_setCornerMatchRow:MSBDesktopCornerStored() != nil reload:reload];
}
// Match Home Screen Icons (1.7.9 item 4): there to use while a corner of the user's own is stored and the desktop's rows are on. When the slider's
// first move stores one, only this row is reloaded: reloading the slider's own cell while it is dragged ended the drag (M1, 1.7.9~r03: Settings
// sent one value as the finger went down and the next only as it lifted).
- (void)msb_setCornerMatchRow:(BOOL)stored reload:(BOOL)reload {
	PSSpecifier *match = [self specifierForID:@"DESKTOP_CORNER_MATCH"], *slider = [self specifierForID:@"DESKTOP_APP_CORNER"];
	if (!match) return;
	id rows = [slider propertyForKey:@"enabled"];
	[match setProperty:@(stored && slider && (!rows || [rows boolValue])) forKey:@"enabled"];
	if (reload) [self reloadSpecifier:match animated:YES];
}
// Match Home Screen Icons pressed: the user's corner removed -- the desktop's app icons have the Home Screen's shape again and follow it; the
// slider goes back to where that shape is, and the row greys until the slider is moved again.
- (void)msb_matchHomeScreenCorners:(PSSpecifier *)spec {
	CFPreferencesSetAppValue(CFSTR(MSBD_DESKTOP_CORNER_KEY), NULL, kMSBBarDomain);
	CFPreferencesAppSynchronize(kMSBBarDomain);
	gMSBDesktopCornerWritten = -1;
	notify_post("com.besiktasliseba.macstatusbar.finder.pref");
	PSSpecifier *slider = [self specifierForID:@"DESKTOP_APP_CORNER"];
	if (slider) [self reloadSpecifier:slider animated:YES];
	[self msb_setCornerMatchRow:NO reload:YES];
}

// Back on the Windows & Multitasking page: Prewarm Apps comes or goes when the prewarm block's state changed since the list was built (a dasd
// started again since, the quit set's file gone or back: common/PrewarmArmed.h) -- the list built again, as the Desktop page does for its note.
- (void)msb_prewarmMaybeChanged {
	if (!_specifiers || ![self msb_windowsPage] || (MSBDPrewarmAppsShown() != 0) == _msbPrewarmShown) return;
	_specifiers = nil;
	[self reloadSpecifiers];
}
// ... and Keep Tailspin Off when the root helper's answer changed since (an iPadOS update, the helper's first look after an install).
- (void)msb_tailspinMaybeChanged {
	if (!_specifiers || ![self msb_windowsPage] || (MSBDTailspinRowShown() != 0) == _msbTailspinShown) return;
	_specifiers = nil;
	[self reloadSpecifiers];
}

// The saved engine can name one this device does not offer (MilkyWay4 saved before an update to iPadOS 16, or an engine since removed): the tweak
// then runs the default one (DMActiveEngine / MSBDDefaultEngine), so that is the one shown as picked (an untested Aerial too: "Untested, Runs on Its Own").
- (id)readPreferenceValue:(PSSpecifier *)specifier {
	if ([[specifier propertyForKey:@"key"] isEqual:@"stockStatusBar"]) return MSBStockBarStored() ? @"stock" : @"mac";   // the row and its picker page show/pick these two strings
	if ([[specifier propertyForKey:@"key"] isEqual:@(kMSBDMenuBarSizeKey)]) return @(MSBMenuBarSizeStored());   // (0 / 1 / 2: the crash guard's false is Small)
	if ([[specifier propertyForKey:@"key"] isEqual:@MSBD_DESKTOP_ICON_KEY]) return @(MSBDesktopIconShownNow());   // (never set: the Home Screen's size, as SpringBoard uses it)
	if ([[specifier propertyForKey:@"key"] isEqual:@MSBD_DESKTOP_CORNER_KEY]) return @(MSBDesktopCornerShownNow());   // (never set: the Home Screen's shape, as SpringBoard read it)
	if ([[specifier propertyForKey:@"key"] isEqual:@"prewarmApps"]) return @(MSBPrewarmAppsInForce());   // (never set: off on a 2 GB iPad, as SpringBoard reads it)
	if ([[specifier propertyForKey:@"key"] isEqual:@kMSBDTailspinKey]) return @(MSBTailspinOffInForce());   // (never set: on with 2 GB, as the root helper reads it)
	id value = [super readPreferenceValue:specifier];
	if (![[specifier propertyForKey:@"key"] isEqual:@"windowEngine"]) return value;
	NSArray *offered = [specifier respondsToSelector:NSSelectorFromString(@"values")] ? ((id (*)(id, SEL))objc_msgSend)(specifier, NSSelectorFromString(@"values")) : nil;
	return MSBEngineShown(value, offered);   // ("none": no engine at all, shown as "None", see -specifiers)
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
	if ([[specifier propertyForKey:@"key"] isEqual:@(kMSBDMenuBarSizeKey)]) {   // Small / Medium / Large from the picker page: 0 / 1 / 2
		int size = [value respondsToSelector:@selector(doubleValue)] ? MSBDMenuBarSizeFrom(1, [value doubleValue]) : MSBDMenuBarSmall;
		if (size == MSBMenuBarSizeStored()) return;   // the size in force tapped again
		[super setPreferenceValue:@(size) specifier:specifier];
		[self msb_menuBarSizeChanged:size];
		return;
	}
	if ([[specifier propertyForKey:@"key"] isEqual:@MSBD_DESKTOP_ICON_KEY]) {   // (1.7.5: the slider, while it is dragged -- SpringBoard resizes the icons live)
		double side = [value respondsToSelector:@selector(doubleValue)] ? MSBDDesktopIconSnap([value doubleValue]) : 0.0;
		if (side <= 0.0) return;
		// (the Home Screen's own step is "the same as the Home Screen", as never set: nothing stored, so the icons follow the Home Screen again)
		double home = MSBDDesktopHomeSideFromState(MSBDesktopHomeState());
		double want = home > 0.0 && MSBDDesktopIconSnap(home) == side ? 0.0 : side;
		if (gMSBDesktopIconWritten < 0) { NSNumber *n = MSBDesktopIconStored(); gMSBDesktopIconWritten = n ? MSBDDesktopIconSnap(n.doubleValue) : 0.0; }
		if (want == gMSBDesktopIconWritten) return;   // (the same step: nothing written, nothing posted)
		gMSBDesktopIconWritten = want;
		if (want > 0.0) { [super setPreferenceValue:@(want) specifier:specifier]; return; }
		CFPreferencesSetAppValue(CFSTR(MSBD_DESKTOP_ICON_KEY), NULL, kMSBBarDomain);
		CFPreferencesAppSynchronize(kMSBBarDomain);
		notify_post("com.besiktasliseba.macstatusbar.finder.pref");
		return;
	}
	if ([[specifier propertyForKey:@"key"] isEqual:@MSBD_DESKTOP_CORNER_KEY]) {   // (1.7.9: the slider, while it is dragged -- SpringBoard draws the app icons live)
		double corner = [value respondsToSelector:@selector(doubleValue)] ? MSBDDesktopCornerSnap([value doubleValue]) : -1.0;
		if (corner < 0.0) return;
		if (gMSBDesktopCornerWritten < -1.5) { NSNumber *n = MSBDesktopCornerStored(); gMSBDesktopCornerWritten = n ? MSBDDesktopCornerSnap(n.doubleValue) : -1.0; }
		if (corner == gMSBDesktopCornerWritten) return;   // (the same step: nothing written, nothing posted)
		BOOL first = gMSBDesktopCornerWritten < 0.0;
		gMSBDesktopCornerWritten = corner;
		[super setPreferenceValue:@(corner) specifier:specifier];   // (always stored once moved, the Home Screen's own step too: the user's corner from now on)
		if (first) [self msb_setCornerMatchRow:YES reload:YES];   // (Match Home Screen Icons can be used now -- that row only, never the slider being dragged)
		return;
	}
	[super setPreferenceValue:value specifier:specifier];
	if ([[specifier propertyForKey:@"key"] isEqual:@"finderEnabled"]) { [self msb_updateDesktopNamesRow:YES]; notify_post("com.besiktasliseba.dockmagnification/prefsChanged"); return; }   // (the Dock shows or hides its Finder icon too)
	if ([[specifier propertyForKey:@"key"] isEqual:@"desktopIcons"]) { [self msb_updateDesktopNamesRow:YES]; return; }
	if ([[specifier propertyForKey:@"key"] isEqual:@"sidebarSearch"]) { [self msb_updateSearchTweaksRow:YES]; return; }
	if ([[specifier propertyForKey:@"key"] isEqual:@"macSwitcher"]) { [self msb_updateGoToDesktopRow:YES]; return; }
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
			if (MSBEngineState(engine) == 1) message = [message stringByAppendingFormat:@" %@ hasn't been tested with MacStatusBar&Dock yet, so it runs on its own.", MSBEngineNameVersion(engine)];
			offerRespring = YES;
		}
	} else if (MSBiCleanerInstalled() && access("/var/jb/usr/libexec/sshtoggled", X_OK) == 0) {
		// MacSettings' root helper does iCleaner's renaming for us (it re-reads the choice from our preferences itself; see sshtoggled/main.m)
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ notify_post("com.besiktasliseba.msb.engines.apply"); });
		title = @"Respring to Switch Engines";
		message = [NSString stringWithFormat:@"Only %@ will load after a respring.", names[engine] ?: engine];
		if (MSBEngineState(engine) == 1) message = [message stringByAppendingFormat:@" %@ hasn't been tested with MacStatusBar&Dock yet, so it runs on its own.", MSBEngineNameVersion(engine)];
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
	// (1.5.1, consent: Apple's Stage Manager setting is the user's. Picking another engine keeps it off while that engine runs -- said here, and this pick
	//  is the yes (smHoldConsent); picking Stage Manager asks before it is turned on, in SpringBoard. Only where Stage Manager exists.)
	if (MSBStageManagerAvailable()) {
		if (![engine isEqualToString:@"stagemanager"]) {
			MSBSetStageManagerConsent(CFSTR("smHoldConsent"), 1);
			message = [message stringByAppendingFormat:@" Stage Manager stays off while %@ runs, and comes back on as you had it when you turn off windowing.", names[engine] ?: engine];
		} else {   // (Stage Manager picked: what happens to Apple's setting, by the stored answer -- logic test W3; on already or a yes: nothing to say)
			int c = MSBStageManagerConsent(CFSTR("smConsentOn"));
			if (c == DMSMConsentNo && MSBStageManagerOnState() != 1)
				message = [message stringByAppendingString:@" Stage Manager is off, as you chose. To use it, tap Turn On Stage Manager or turn it on in Control Center."];
			else if (c == DMSMConsentUnasked && MSBStageManagerOnState() != 1)
				message = [message stringByAppendingString:@" MacStatusBar&Dock asks before it turns Stage Manager on."];
		}
	}
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
	if (offerRespring) [alert addAction:[UIAlertAction actionWithTitle:@"Respring Now" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { MSBRespring(); }]];
	if (offerICleaner) [alert addAction:[UIAlertAction actionWithTitle:@"Open iCleaner Pro" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
		[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"icleaner://"] options:@{} completionHandler:nil];
	}]];
	[alert addAction:[UIAlertAction actionWithTitle:offerRespring ? @"Later" : @"OK" style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}
// Turn On Stage Manager (shown while it is off with Stage Manager as the engine): the user's yes. SpringBoard turns it on (Apple's introduction first, if it
// was never on), then the page shows the usual footer again.
- (void)msb_turnOnStageManager:(PSSpecifier *)spec {
	MSBSetStageManagerConsent(CFSTR("smConsentOn"), 1);
	notify_post("com.besiktasliseba.macstatusbar.smturnon");   // (a tap, even with the yes already stored: SpringBoard ends a wait for Apple's introduction -- W2)
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ _specifiers = nil; [self reloadSpecifiers]; });
}

@end

// ---- The Windows & Multitasking page (1.6.0): the Status Bar page's controller with Windows.plist ----
@interface MSBWindowsListController : MSBRootListController
@end
@implementation MSBWindowsListController
- (NSString *)msb_plistName { return @"Windows"; }
- (BOOL)msb_windowsPage { return YES; }
- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self msb_prewarmMaybeChanged];   // (Prewarm Apps where the prewarm block is armed now)
	[self msb_tailspinMaybeChanged];   // (Keep Tailspin Off where the root helper found it doing something now)
}
@end

// ---- The Desktop page (1.7.5 item 1): the Status Bar page's controller with Desktop.plist -- Show Desktop Icons and Hide Desktop Icon Names
// (moved here from the Status Bar page's Finder group, same keys), Icon Size (item 4) ----
@interface MSBDesktopListController : MSBRootListController
@end
@implementation MSBDesktopListController
- (NSString *)msb_plistName { return @"Desktop"; }
- (BOOL)msb_desktopPage { return YES; }
// Back on the page: Finder, MacStatusBar or the gate changed elsewhere -- the note comes or goes (built again); otherwise the greyed rows follow
// Finder and Show Desktop Icons, and the slider shows the size in force (the Home Screen's may have been measured since).
- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	gMSBDesktopIconWritten = -1;   // (the slider's last step read from the store again: it may have changed elsewhere)
	gMSBDesktopCornerWritten = -2;   // (the same for App Icon Corner Radius, 1.7.9)
	PSSpecifier *shown = [self specifierForID:@"MSB_DESKTOP_NOTE"], *wanted = [[self msb_desktopPageNotes:@[]] firstObject];
	NSString *a = [shown propertyForKey:@"footerText"], *b = [wanted propertyForKey:@"footerText"];
	if ((a || b) && ![a isEqual:b]) { _specifiers = nil; [self reloadSpecifiers]; return; }
	[self msb_updateDesktopNamesRow:YES];
	PSSpecifier *size = [self specifierForID:@"DESKTOP_ICON_SIZE"];
	if (size) [self reloadSpecifier:size animated:NO];
	PSSpecifier *corner = [self specifierForID:@"DESKTOP_APP_CORNER"];   // (never set: where the Home Screen's shape is now -- a theme may have changed it)
	if (corner) [self reloadSpecifier:corner animated:NO];
}
@end
