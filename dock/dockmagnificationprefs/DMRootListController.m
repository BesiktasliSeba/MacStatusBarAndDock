#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import "DMRootListController.h"
#import <Preferences/PSSpecifier.h>
#import "../../common/LineSwitch.h"
#import "../../common/MacDockActive.h"
#import "../../common/NativeEmbed.h"

// The "Other Apps" row uses AltList's app picker (ATLApplicationListMultiSelectionController). That class only exists once
// AltList's library is loaded, and this bundle is not linked against it, so load it as soon as the bundle is loaded.
__attribute__((constructor)) static void DMLoadAltList(void) {
	dlopen("/var/jb/Library/Frameworks/AltList.framework/AltList", RTLD_NOW);
}

@interface PSListController (MSBDURL)
- (void)handleURL:(NSDictionary *)url withCompletion:(id)completion;
- (NSInteger)indexOfSpecifierID:(NSString *)identifier;
- (NSIndexPath *)indexPathForIndex:(NSInteger)index;
@end

@implementation DMRootListController {
	NSMutableArray *_msNativePages;   // Apple's Home Screen page (never shown), whose App Library switch is on this page
}

MSBD_LINE_SWITCH_METHODS

// A link to the Downloads section (prefs:root=DOCK_MAGNIFICATION&path=DOWNLOADS, the gear in the Dock's Downloads panel, 2026-09-26): the page
// opens scrolled down to Show Downloads in Dock, with Downloads From (Safari, Other Apps) under it. A switch row is not a page Settings can push,
// so the scroll is ours; any other path goes on as before.
- (void)handleURL:(NSDictionary *)url withCompletion:(id)completion {
	// (also Show Finder in Dock: prefs:root=DOCK_MAGNIFICATION&path=FINDER, from the Finder icon's "Remove from Dock" question)
	NSString *path = [url isKindOfClass:[NSDictionary class]] ? url[@"path"] : nil;
	if ([path isEqual:@"DOWNLOADS"] || [path isEqual:@"FINDER"]) {
		__weak DMRootListController *weakSelf = self;
		void (^scroll)(void) = ^{
			DMRootListController *me = weakSelf;
			UITableView *table = [me respondsToSelector:@selector(table)] ? [me table] : nil;
			if (!me || !table) return;
			NSInteger i = [me indexOfSpecifierID:path];
			NSIndexPath *ip = i == NSNotFound ? nil : [me indexPathForIndex:i];
			if (ip && ip.section < table.numberOfSections && ip.row < [table numberOfRowsInSection:ip.section])
				[table scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionTop animated:NO];
		};
		dispatch_async(dispatch_get_main_queue(), scroll);
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), scroll);   // (a page still being laid out)
		if (completion) ((void (^)(void))completion)();
		return;
	}
	[super handleURL:url withCompletion:completion];
}

// The page is opened from a row we add to Settings ourselves, not from a PreferenceLoader entry, so say where the
// bundle is instead of relying on the entry to tell Settings.
- (NSBundle *)bundle {
	return [NSBundle bundleForClass:[DMRootListController class]];
}

// While MacDock is active, Apple's "Show App Library in Dock" switch is here (its own row from Apple's Home Screen page, live; that page no longer
// shows it, see DockSettingsRow.x), first in the App Library group, whose footer says where the other Home Screen options are.
- (NSArray *)specifiers {
	if (!_specifiers) {
		NSMutableArray *specs = [[self loadSpecifiersFromPlistName:@"Root" target:self] mutableCopy];
		NSArray *untested = [self msbd_untestedSpecifiers];   // (on top: "Enable Anyway" on an untested iPadOS version, or the crash guard's note)
		if (untested.count) [specs insertObjects:untested atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, untested.count)]];
		if (MSBDMacDockActive()) {
			if (!_msNativePages) _msNativePages = [NSMutableArray array];
			NSArray *lib = MSNESpecifiers(self, @"DBSHomeScreenPadListController", @[], @"Home Screen", _msNativePages, @[@"SHOW_APP_LIBRARY"]);
			for (NSUInteger i = 0; i < specs.count && lib.count; i++) {
				PSSpecifier *g = specs[i];
				if (g.cellType != PSGroupCell || ![g.name isEqualToString:@"App Library"]) continue;
				[specs insertObject:lib.firstObject atIndex:i + 1];
				NSString *home = [NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 16 ? @"Home Screen & Multitasking" : @"Home Screen";
				[g setProperty:[NSString stringWithFormat:@"Home Screen options are in %@.", home] forKey:@"footerText"];
				break;
			}
		}
		// (Finder switched off in Mac Status Bar's settings: no Finder in the Dock, so no row for it)
		CFPreferencesAppSynchronize(CFSTR("com.besiktasliseba.macstatusbar"));
		CFPropertyListRef fe = CFPreferencesCopyValue(CFSTR("finderEnabled"), CFSTR("com.besiktasliseba.macstatusbar"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
		BOOL finderOff = fe && CFGetTypeID(fe) == CFBooleanGetTypeID() && !CFBooleanGetValue(fe);
		if (fe) CFRelease(fe);
		if (finderOff) for (PSSpecifier *sp in [specs copy]) if ([sp.identifier isEqual:@"FINDER"] || [sp.identifier isEqual:@"FINDER_GROUP"]) [specs removeObject:sp];
		_specifiers = [self msbd_hideRowsWhenLineOff:specs offFooter:@"The Dock features are off. Turn them on to change their settings. Takes effect after a respring."];
	}
	return _specifiers;
}

// Number of Recent Apps and Apple's "Show Suggested and Recent Apps in Dock" (com.apple.springboard SBRecentsEnabled) stay in step while MacDock is
// active: None switches Apple's off, a number switches it on, and Apple's switched off reads as None.
static BOOL DMStockRecentsOff(void) {
	CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("SBRecentsEnabled"), CFSTR("com.apple.springboard"));
	BOOL off = v && CFGetTypeID(v) == CFBooleanGetTypeID() && !CFBooleanGetValue(v);
	if (v) CFRelease(v);
	return off;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
	id value = [super readPreferenceValue:specifier];
	if ([[specifier propertyForKey:@"msbInvert"] boolValue]) return [value boolValue] ? @NO : @YES;
	if ([[specifier propertyForKey:@"key"] isEqual:@"dockRecentsCount"] && MSBDMacDockActive() && DMStockRecentsOff()) return @0;
	return value;
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	[self msbd_noteSwitch:value specifier:specifier];   // (crash guard: LineSwitch.h)
	// (@YES / @NO, a real boolean: `@(!x)` is an int in C, and the tweaks read only a boolean, so a switched-off row was stored as 1 and ignored.)
	if ([[specifier propertyForKey:@"msbInvert"] boolValue]) value = [value boolValue] ? @NO : @YES;
	[super setPreferenceValue:value specifier:specifier];
	if (![[specifier propertyForKey:@"key"] isEqual:@"dockRecentsCount"] || !MSBDMacDockActive()) return;
	CFPreferencesSetAppValue(CFSTR("SBRecentsEnabled"), [value integerValue] > 0 ? kCFBooleanTrue : kCFBooleanFalse, CFSTR("com.apple.springboard"));
	CFPreferencesAppSynchronize(CFSTR("com.apple.springboard"));
}

@end
