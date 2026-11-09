#import <objc/message.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <notify.h>
#import "DMRootListController.h"
#import <Preferences/PSSpecifier.h>
#import "../../common/DockAppLibrary.h"   // (1.8.4.1 item 2: Apple's App Library switch on this page applies at once)
#import "../../common/LineSwitch.h"
#import "../../common/MacDockActive.h"
#import "../../common/NativeEmbed.h"
#import "../../common/OwnPageState.h"   // (1.7.9: Finder as stored and the rows this page leaves out, shared with the Settings search)

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
				// (iPadOS 15: SpringBoard reads this setting at its start and its Dock doesn't follow a change: its own getter still gave the old value right after its own setter, M1 15.6.1, plans/regression-1.8.4.1-evidence/m1/applib-z03-2.txt)
				BOOL respring = [NSProcessInfo processInfo].operatingSystemVersion.majorVersion < 16;
				[g setProperty:[NSString stringWithFormat:@"Home Screen options are in %@.%@", home, respring ? @" Show App Library in Dock takes effect after a respring." : @""] forKey:@"footerText"];
				break;
			}
		}
		// (iPadOS 17+: our Home Screen group, which 15/16 show on Apple's Home Screen page, is here, after the App Library group -- Apple's page is a
		//  SwiftUI page there, see DockSettingsRow.x +msbdHomeScreenSpecifiersForOwnPage; nil on 15/16 or when that part is not loaded)
		Class hsRows = NSClassFromString(@"DMHomeScreenRows");
		SEL hsSel = NSSelectorFromString(@"msbdHomeScreenSpecifiersForOwnPage");
		NSArray *hs = [hsRows respondsToSelector:hsSel] ? ((NSArray *(*)(id, SEL))objc_msgSend)(hsRows, hsSel) : nil;
		if ([hs isKindOfClass:[NSArray class]] && hs.count) {
			NSUInteger at = specs.count;
			for (NSUInteger i = 0; i < specs.count; i++) if ([[specs[i] identifier] isEqual:@"FINDER_GROUP"]) { at = i; break; }   // (after App Library: in front of Finder)
			[specs insertObjects:hs atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(at, hs.count)]];
		}
		// (Finder switched off in Mac Status Bar's settings: no Finder in the Dock, so no row for it -- Finder read as SpringBoard reads it, and the
		//  Settings search leaves the row out the same way: common/OwnPageState.h, OwnPageRows.h)
		if (!MSBDFinderStored()) for (PSSpecifier *sp in [specs copy]) if ([sp.identifier isEqual:kMSBDDockFinderRowID] || [sp.identifier isEqual:kMSBDDockFinderGroupID]) [specs removeObject:sp];
		_specifiers = [self msbd_hideRowsWhenLineOff:specs offFooter:@"The Dock features are off. Turn them on to change their settings. Takes effect after a respring."];
	}
	return _specifiers;
}

// Apple's App Library switch above is Apple's own row: it writes as on Apple's page, and nothing of ours hears of it. With a window engine Settings is a
// window, so the full-screen transition after which SpringBoard puts its parked Dock change in never came, and the icon stayed until a respring (KT
// 7 Nov, the M1, 15.6.1). Its switch gets one more target -- after Apple's own, never in its place -- that tells the Dock part, which then lays the
// Dock out with it at once (common/DockAppLibrary.h, Dock.x DMAppLibraryInDockChanged). Cells are reused, for any row of their kind: ours comes off
// every row's control and goes back on the App Library row's only, once -- a cell that had that row before must not tell SpringBoard when another
// row's switch on it is flipped (review 1.8.4.1 L1).
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
	SEL specSel = NSSelectorFromString(@"specifier"), controlSel = NSSelectorFromString(@"control");   // (PSTableCell's row, PSControlTableCell's switch)
	id control = [cell respondsToSelector:controlSel] ? ((id (*)(id, SEL))objc_msgSend)(cell, controlSel) : nil;
	if (![control isKindOfClass:[UIControl class]]) return cell;
	[(UIControl *)control removeTarget:self action:@selector(msbd_appLibrarySwitched:) forControlEvents:UIControlEventValueChanged];
	PSSpecifier *sp = [cell respondsToSelector:specSel] ? ((id (*)(id, SEL))objc_msgSend)(cell, specSel) : nil;
	if ([sp isKindOfClass:[PSSpecifier class]] && [sp.identifier isEqualToString:@kMSBDDockAppLibraryRowID])
		[(UIControl *)control addTarget:self action:@selector(msbd_appLibrarySwitched:) forControlEvents:UIControlEventValueChanged];
	return cell;
}
- (void)msbd_appLibrarySwitched:(id)sender {
	notify_post(kMSBDDockAppLibraryNote);   // (the Dock part looks three times over the next second: SpringBoard hears of Apple's write in its own time)
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
