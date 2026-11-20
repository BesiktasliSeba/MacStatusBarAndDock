// MSBAppSizesController: Settings > Windows & Multitasking > App Window Sizes (1.8.8, KT 12 Nov: a launch size per app, the row right under Window
// Size opening its own page; plans/design-1.8.8-app-sizes.md 3.2 and 4.4 with the closing round 4 amendments). Two plain PSListControllers of ours:
//  - MSBAppSizesController, the list: the apps with a size of their own, by name (icon, name, the size on the right; an app no longer installed by
//    its bundle id with "Not Installed" under it, as the Go menu's list), each opening its page; then Add App, AltList's single-app picker as Custom
//    Shortcuts' App row uses it (ATLApplicationListSelectionController). The picker's class is looked up by name only: no AltList class is
//    subclassed or named in an interface here and the bundle is not linked against AltList, so a missing AltList only takes Add App away.
//  - MSBAppSizeController, one app's page: Small, Medium, Large, Fill or iPhone, and Remove App.
// The stored list is common/AppWindowSize.h's: one dictionary, appWindowSizes in com.besiktasliseba.macstatusbar (bundle id -> "small" / "medium" /
// "large" / "fill" / "iphone"), read here through the read rule SpringBoard uses. It is written only by a tap on a size or on Remove App
// (MSBDAppSizesWith: that one entry changed, the others kept as stored, the key removed with the last app), then prefsChanged, so the app's next
// window opens at it (no respring). Add App alone writes nothing.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#import <unistd.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
#import "MSBAppSizesController.h"
#import "MSBSettingsStack.h"
#import "../../common/AppWindowSize.h"

#define kMSBASDomain CFSTR("com.besiktasliseba.macstatusbar")
static NSString *const kMSBASBundleKey = @"msbBundle";   // (the app of a list row and of its page: the specifier's property)

@interface UIImage (MSBAppSizesIcon)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleID format:(int)format scale:(CGFloat)scale;
@end

@interface MSBAppSizeController : PSListController
- (NSString *)msbBundle;
@end
@interface MSBAppSizesController : PSListController
@end

static void MSBASLog(NSString *line) {   // (debug builds: the Settings probe's log, as MSBRootListController.m's page links; device row S1 reads it)
#if DEBUG
	FILE *f = fopen("/tmp/msbd-settings.log", "a");
	if (f) { fprintf(f, "%.3f [appsize] %s\n", CFAbsoluteTimeGetCurrent(), line.UTF8String); fclose(f); }
#else
	(void)line;
#endif
}

// ---- the stored list ----
static id MSBASStored(void) {   // (as it is stored: the write keeps every entry it does not change)
	CFPreferencesAppSynchronize(kMSBASDomain);
	CFPropertyListRef v = CFPreferencesCopyValue(CFSTR(kMSBDAppWindowSizesKey), kMSBASDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	return v ? CFBridgingRelease(v) : nil;
}
// The apps with a size, as SpringBoard reads them (the read rule: bundle id -> the choice; at most 200).
static NSDictionary<NSString *, NSNumber *> *MSBASListed(void) { return CFBridgingRelease(MSBDAppSizesRead((__bridge CFTypeRef)MSBASStored(), NULL, NULL, NULL)); }
static int MSBASChoiceIn(NSDictionary *listed, NSString *bundle) { return MSBDAppSizeIn((__bridge CFDictionaryRef)listed, (__bridge CFStringRef)bundle); }
// The one write (a tap on a size, or Remove App with None): that app's entry, the key removed with the last app, SpringBoard told.
static void MSBASWrite(NSString *bundle, int choice) {
	CFDictionaryRef next = MSBDAppSizesWith((__bridge CFTypeRef)MSBASStored(), (__bridge CFStringRef)bundle, choice);
	CFPreferencesSetValue(CFSTR(kMSBDAppWindowSizesKey), next, kMSBASDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);   // (NULL: the key removed)
	CFIndex left = next ? CFDictionaryGetCount(next) : 0;
	if (next) CFRelease(next);
	CFPreferencesSynchronize(kMSBASDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	notify_post("com.besiktasliseba.macstatusbar/prefsChanged");
	const char *name = MSBDAppSizeName(choice);
	MSBASLog([NSString stringWithFormat:@"%@ %s (%ld stored)", bundle, name ? name : "removed", (long)left]);
}
NSString *MSBAppSizesRowValue(void) {
	char text[32];
	MSBDAppSizesCountText((CFIndex)MSBASListed().count, text, sizeof text);
	return @(text);
}

// ---- the apps ----
static id MSBASValue(id obj, NSString *key) { @try { return [obj valueForKey:key]; } @catch (NSException *e) { return nil; } }
// The installed apps and their names, from the system's app records as the Go menu's list reads them (LSApplicationWorkspace).
static NSDictionary<NSString *, NSString *> *MSBASInstalledApps(void) {
	NSMutableDictionary *out = [NSMutableDictionary dictionary];
	id ws = ((id (*)(id, SEL))objc_msgSend)(objc_getClass("LSApplicationWorkspace"), NSSelectorFromString(@"defaultWorkspace"));
	SEL all = NSSelectorFromString(@"allInstalledApplications");
	NSArray *apps = [ws respondsToSelector:all] ? ((id (*)(id, SEL))objc_msgSend)(ws, all) : nil;
	for (id p in apps) {
		NSString *bid = MSBASValue(p, @"bundleIdentifier"), *name = MSBASValue(p, @"localizedName");
		if (![bid isKindOfClass:[NSString class]] || !bid.length) continue;
		out[bid] = [name isKindOfClass:[NSString class]] && name.length ? name : bid;
	}
	return out;
}
// One app's name, from its record (LSApplicationProxy's localizedName), else its bundle id: this bundle's own (Custom Shortcuts' MSCSAppName is
// the macsettings tweak's).
static NSString *MSBASAppName(NSString *bundle) {
	Class c = objc_getClass("LSApplicationProxy");
	SEL make = NSSelectorFromString(@"applicationProxyForIdentifier:");
	id proxy = bundle.length && [(id)c respondsToSelector:make] ? ((id (*)(id, SEL, id))objc_msgSend)((id)c, make, bundle) : nil;
	NSString *name = MSBASValue(proxy, @"localizedName");
	return [name isKindOfClass:[NSString class]] && name.length ? name : bundle;
}
// AltList's single-app picker, by name only (the bundle's constructor has loaded AltList, MSBRootListController.m MSBLoadAltList). Nil without
// AltList (a package dependency, never seen): no Add App row and no footer of its own.
static Class MSBASPickerClass(void) {
#if DEBUG
	if (access("/tmp/msbd-appsize-no-altlist", F_OK) == 0) return Nil;   // (debug builds: device row S1's look at a missing AltList)
#endif
	return NSClassFromString(@"ATLApplicationListSelectionController");
}
static PSSpecifier *MSBASSpecAt(PSListController *c, NSIndexPath *ip) {
	NSInteger i = [c indexForIndexPath:ip];
	return i >= 0 && i < (NSInteger)[c specifiers].count ? [c specifierAtIndex:i] : nil;
}

// An app no longer installed: its bundle id with "Not Installed" under it, the Go menu's words in the Go menu's place (MSBGoAppsController.m).
@interface MSBAppSizeMissingCell : PSTableCell
@end
@implementation MSBAppSizeMissingCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid specifier:(PSSpecifier *)specifier {
	return [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:rid specifier:specifier];
}
- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
	[super refreshCellContentsWithSpecifier:specifier];
	self.detailTextLabel.text = @"Not Installed";
	self.detailTextLabel.textColor = [UIColor secondaryLabelColor];
}
@end

// ---- one app's page ----
@implementation MSBAppSizeController
- (NSString *)msbBundle { id b = [self.specifier propertyForKey:kMSBASBundleKey]; return [b isKindOfClass:[NSString class]] && [b length] ? b : nil; }
- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = MSBASAppName(self.msbBundle);
}
- (NSMutableArray *)specifiers {
	if (!_specifiers) {
		NSString *b = self.msbBundle;
		int now = b ? MSBASChoiceIn(MSBASListed(), b) : MSBDAppSizeNone;   // (opened from Add App for an app with no size: nothing checked)
		NSMutableArray *s = [NSMutableArray array];
		PSSpecifier *g = [PSSpecifier groupSpecifierWithName:@"Opens At"];
		const char *footer = MSBDAppSizeFooter(now);
		if (footer) [g setProperty:@(footer) forKey:@"footerText"];
		[s addObject:g];
		for (int i = 0; MSBDAppSizeChoiceAt(i) != MSBDAppSizeNone; i++) {
			int c = MSBDAppSizeChoiceAt(i);
			PSSpecifier *r = [PSSpecifier preferenceSpecifierNamed:@(MSBDAppSizeTitle(c)) target:self set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
			r.buttonAction = @selector(msbPickSize:);
			[r setProperty:@(c) forKey:@"msbSize"];
			[r setProperty:@YES forKey:@"msbPlain"];
			if (c == now) [r setProperty:@YES forKey:@"msbChecked"];
			[r setIdentifier:[NSString stringWithFormat:@"APP_SIZE_%s", MSBDAppSizeName(c)]];
			[s addObject:r];
		}
		if (MSBDAppSizeValid(now)) {   // (only once the app has a size)
			[s addObject:[PSSpecifier groupSpecifierWithName:nil]];
			PSSpecifier *d = [PSSpecifier preferenceSpecifierNamed:@"Remove App" target:self set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
			d.buttonAction = @selector(msbRemoveApp:);
			[d setProperty:@YES forKey:@"msbDestructive"];
			[d setIdentifier:@"APP_SIZE_REMOVE"];
			[s addObject:d];
		}
		_specifiers = s;
	}
	return _specifiers;
}
// The rows' looks, as Custom Shortcuts' action rows (CustomShortcuts.x): the sizes as plain rows with the chosen one checked, Remove App in red.
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *c = [super tableView:tv cellForRowAtIndexPath:ip];
	PSSpecifier *sp = MSBASSpecAt(self, ip);
	if ([[sp propertyForKey:@"msbPlain"] boolValue]) {
		c.textLabel.textColor = [UIColor labelColor];
		c.accessoryType = [[sp propertyForKey:@"msbChecked"] boolValue] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	} else if ([[sp propertyForKey:@"msbDestructive"] boolValue]) {
		c.textLabel.textColor = [UIColor systemRedColor];
	}
	return c;
}
// A tap on a size: the first write of an app opened from Add App (only then is it listed), or its new size.
- (void)msbPickSize:(PSSpecifier *)spec {
	NSString *b = self.msbBundle;
	int c = [[spec propertyForKey:@"msbSize"] intValue];
	if (!b || !MSBDAppSizeValid(c)) return;
	NSDictionary *listed = MSBASListed();
	int now = MSBASChoiceIn(listed, b);
	if (now == c) return;
	if (now == MSBDAppSizeNone && !MSBDAppSizesCanAdd((CFIndex)listed.count)) return;   // (200 listed: no other app is added)
	MSBASWrite(b, c);
	_specifiers = nil; [self reloadSpecifiers];
}
// Remove App: the entry goes, and so does this page: back to the App Window Sizes list, which reloads (after a pick the picker is no longer in the
// navigation stack). The list's entry in the stack: the list itself, or on 18 the controller that hosts it (MSBSettingsStack.h).
- (void)msbRemoveApp:(PSSpecifier *)spec {
	NSString *b = self.msbBundle;
	if (b) MSBASWrite(b, MSBDAppSizeNone);
	UINavigationController *nav = self.navigationController;
	UIViewController *list = nil;
	for (UIViewController *vc in nav.viewControllers.reverseObjectEnumerator) if (MSBSSPageIn(vc, [MSBAppSizesController class])) { list = vc; break; }
	if (list) [nav popToViewController:list animated:YES];
	else [nav popViewControllerAnimated:YES];
}
@end

// ---- the list ----
@implementation MSBAppSizesController {
	NSString *_picked;   // the app taken from Add App's picker, until its page opens
	BOOL _pickOpen;      // Add App's picker opened and no app taken from it yet: AltList's setter is followed once per opening
	__weak UIViewController *_closedPicker;   // the picker this list closed for the pick, until the page is pushed (the debug log reads its parent)
}
- (NSMutableArray *)specifiers {
	if (!_specifiers) {
		NSDictionary *listed = MSBASListed(), *installed = MSBASInstalledApps();
		NSMutableArray *s = [NSMutableArray array];
		if (listed.count) {   // (the list's group only with apps in it: its footer points at them)
			PSSpecifier *g = [PSSpecifier groupSpecifierWithName:@"Apps"];
			[g setProperty:@"These apps open at their own size instead of Window Size. You can still resize them." forKey:@"footerText"];
			[s addObject:g];
		}
		NSArray *bundles = [listed.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *x, NSString *y) {
			return [(installed[x] ?: x) localizedCaseInsensitiveCompare:(installed[y] ?: y)];
		}];
		CGFloat scale = [UIScreen mainScreen].scale;
		for (NSString *b in bundles) {
			NSString *name = installed[b];
			PSSpecifier *r = [PSSpecifier preferenceSpecifierNamed:name ?: b target:self set:NULL get:@selector(msbAppValue:) detail:[MSBAppSizeController class] cell:PSLinkListCell edit:Nil];
			[r setProperty:b forKey:kMSBASBundleKey];
			[r setIdentifier:[@"APP_SIZE_" stringByAppendingString:b]];
			if (!name) [r setProperty:[MSBAppSizeMissingCell class] forKey:@"cellClass"];   // (no icon; a tap still opens its page, to remove it)
			else if ([UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) {
				UIImage *icon = [UIImage _applicationIconImageForBundleIdentifier:b format:0 scale:scale];
				if (icon) [r setProperty:icon forKey:@"iconImage"];
			}
			[s addObject:r];
		}
		Class picker = MSBASPickerClass();
		if (picker) {
			BOOL canAdd = MSBDAppSizesCanAdd((CFIndex)listed.count);
			PSSpecifier *ag = [PSSpecifier groupSpecifierWithName:nil];
			if (!listed.count) [ag setProperty:@"Apps you add here open at their own size instead of Window Size." forKey:@"footerText"];   // (an empty list: Add App's own line)
			if (!canAdd) [ag setProperty:@"You can add up to 200 apps." forKey:@"footerText"];
			[s addObject:ag];
			// (AltList's picker reads and writes through this row's getter and setter, the bundle id, as Custom Shortcuts' App row)
			PSSpecifier *a = [PSSpecifier preferenceSpecifierNamed:@"Add App…" target:self set:@selector(msbPickedApp:specifier:) get:@selector(msbPickerApp:) detail:picker cell:PSLinkListCell edit:Nil];
			[a setProperty:@[@{ @"sectionType": @"Visible" }] forKey:@"sections"];   // (AltList: the apps on the Home Screen)
			[a setProperty:@YES forKey:@"useSearchBar"];
			[a setProperty:@YES forKey:@"hideSearchBarWhileScrolling"];
			[a setProperty:@(canAdd) forKey:@"enabled"];
			[a setIdentifier:@"APP_SIZES_ADD"];
			[s addObject:a];
		}
		_specifiers = s;
	}
	return _specifiers;
}
- (id)msbAppValue:(PSSpecifier *)spec {   // (a listed app's size on the right; one not installed shows "Not Installed" under its name instead)
	NSString *b = [spec propertyForKey:kMSBASBundleKey];
	if ([spec propertyForKey:@"cellClass"]) return nil;
	const char *t = MSBDAppSizeTitle(MSBASChoiceIn(MSBASListed(), b));
	return t ? @(t) : nil;
}
- (id)msbPickerApp:(PSSpecifier *)spec { return nil; }   // (no app checked: the picker opens clean every time)
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *c = [super tableView:tv cellForRowAtIndexPath:ip];
	if ([[MSBASSpecAt(self, ip) identifier] isEqualToString:@"APP_SIZES_ADD"]) c.detailTextLabel.text = nil;   // (Add App shows no value)
	return c;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	// (a tap on any row of the list ends a pick still waiting for its page, so it never opens a page on another route later; Add App: a new opening
	//  of the picker)
	if (_picked) MSBASLog([NSString stringWithFormat:@"picker: the pick of %@ dropped, a row of the list tapped", _picked]);
	_picked = nil;
	_pickOpen = [[MSBASSpecAt(self, ip) identifier] isEqualToString:@"APP_SIZES_ADD"];
	[super tableView:tv didSelectRowAtIndexPath:ip];
}
// AltList's selection: writes nothing. The app is kept and its page opened later, once AltList's own handling has finished and the picker is gone.
// Whether AltList calls this at the tap or as its picker goes is not in our code: both are handled, and a second call for the same opening (a save
// as the picker goes) is ignored, so the page is pushed once (amendment 3).
- (void)msbPickedApp:(id)value specifier:(PSSpecifier *)spec {
	if (![value isKindOfClass:[NSString class]] || ![value length]) return;
	if (!_pickOpen) { MSBASLog([NSString stringWithFormat:@"picker: a later call for %@ ignored (the pick was taken)", value]); return; }
	_pickOpen = NO;
	_picked = [value copy];
	MSBASLog([NSString stringWithFormat:@"picker: %@ picked, %@", value, [self msbPickerOnTop] ? @"the picker in front" : @"the picker going"]);
	__weak MSBAppSizesController *weakSelf = self;
	dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf msbOpenPickedNextTurn]; });
}
// AltList's picker in front, pushed from this list. The stack's entries are the pages themselves on 15 to 17 and the controllers that host them on
// 18 (MSBSettingsStack.h), so each is read through its entry: read as pages, neither the picker nor this list was ever found on 18, the pick met
// neither safe point below and its page waited for Back (A12Z 18.5, row S1 of the s01 pass).
- (BOOL)msbPickerOnTop {
	UINavigationController *nav = self.navigationController;
	NSArray *vcs = nav.viewControllers;
	return vcs.count >= 2 && MSBSSPageIn(vcs.lastObject, MSBASPickerClass()) && vcs[vcs.count - 2] == MSBSSEntryOf(self, nav);
}
// One change to Settings' navigation stack at a time, each from the end of the one before, as Settings' own pages make them: the picker closes with
// a slide back to this list (Back's own slide, the call Remove App makes), then the app's page is pushed from the list settled (two slides, about
// 1 s from the tap, on 15 to 18 alike). On 18 the stack is SwiftUI's: SwiftUI takes a pop into its own record of the stack only as UIKit shows it
// (from the slide's start), and Settings' push goes into that record. A pop with no slide and a push in the same turn (F1) put the push into a
// record that still held the picker: Settings put the picker's hosting controller back on the stack with the page's, then took both pages out of
// them, and the two stayed on the stack empty (A12Z 18.5, row E1 of p03: a page with a title and no rows, Back onto an empty "Add App...").
// The pick's next turn: with the picker in front and nothing moving, it closes, and nothing is pushed in this turn. A transition running (the
// picker's own push still ending, its search closing, AltList closing it, a rotation): the same checks one turn after it ends, and again after each
// further one. The list in front: no pop is pending, the settled opener decides.
- (void)msbOpenPickedNextTurn {
	if (!_picked) return;
	UINavigationController *nav = self.navigationController;
	UIViewController *picker = [self msbPickerOnTop] ? MSBSSPageIn(nav.topViewController, MSBASPickerClass()) : nil;
	id<UIViewControllerTransitionCoordinator> moving = nav.transitionCoordinator ?: picker.transitionCoordinator;   // (the picker's own: its search)
	if (moving) {
		MSBASLog(@"picker: a transition is running, the pick waits for its end");
		[self msbAfter:moving then:^(MSBAppSizesController *me) { [me msbOpenPickedNextTurn]; }];
		return;
	}
	if (picker) {
		_closedPicker = picker;
		[nav popToViewController:MSBSSEntryOf(self, nav) animated:YES];
		MSBASLog(@"picker: closed with a slide, the page opens when the list is back");
		return;
	}
	[self msbOpenPickedWhenSettled];
}
// The app's page, pushed only from this list settled: its entry on top of Settings' stack, its view in the window, nothing moving. Queued from the
// list's viewDidAppear (a turn after the pop's slide has ended; on 18 SwiftUI took the pop into its record at the slide's start, about 0.5 s before)
// and from the pick's next turn with the list in front: the first to find the list settled pushes, once. A transition running: the same checks one
// turn after it ends. The list not in front once nothing moves (gone from the stack, out of its window, another page over it): the pick is dropped,
// so it never opens a page later on another route.
- (void)msbOpenPickedWhenSettled {
	if (!_picked) return;   // (two callers: one push)
	UINavigationController *nav = self.navigationController;
	id<UIViewControllerTransitionCoordinator> moving = nav.transitionCoordinator;
	if (moving) {
		MSBASLog(@"list: a transition is running, the page waits for its end");
		[self msbAfter:moving then:^(MSBAppSizesController *me) { [me msbOpenPickedWhenSettled]; }];
		return;
	}
	if (!nav || !self.view.window || nav.topViewController != MSBSSEntryOf(self, nav)) {
		MSBASLog([NSString stringWithFormat:@"picker: the pick of %@ dropped, the list %@", _picked, !nav ? @"has left its navigation stack" : !self.view.window ? @"has left its window" : @"is not on top"]);
		_picked = nil; _closedPicker = nil;
		return;
	}
	NSString *b = _picked;
	_picked = nil;   // (cleared before the push: one push only)
	UIViewController *parent = _closedPicker.parentViewController;   // (debug log: on 18, the picker still in a parent here means SwiftUI had not taken the close in)
	_closedPicker = nil;
	MSBASLog([NSString stringWithFormat:@"picker parent %@", parent ? NSStringFromClass([parent class]) : @"none"]);
	[self msbOpenAppPage:b];
	MSBASLog([NSString stringWithFormat:@"page of %@ opened once the list was back", b]);
}
// One turn after the running transition ends (completed or cancelled), the given step again: its checks see the stack as the transition left it.
// A coordinator that does not take the completion: looked at again a moment later.
- (void)msbAfter:(id<UIViewControllerTransitionCoordinator>)moving then:(void (^)(MSBAppSizesController *me))step {
	__weak MSBAppSizesController *weakSelf = self;
	void (^again)(void) = ^{ MSBAppSizesController *me = weakSelf; if (me) step(me); };
	if (![moving animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> ctx) { dispatch_async(dispatch_get_main_queue(), again); }]) {
		MSBASLog(@"a transition's end not offered: looked at again in 0.1 s");
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), again);
	}
}
- (void)msbOpenAppPage:(NSString *)bundle {   // (the list's own way of showing a page: the controller for a link specifier, shown)
	MSBAppSizeController *open = MSBSSPageIn(self.navigationController.topViewController, [MSBAppSizeController class]);
	if ([open.msbBundle isEqualToString:bundle]) return;   // (already open)
	PSSpecifier *link = [PSSpecifier preferenceSpecifierNamed:MSBASAppName(bundle) target:self set:NULL get:NULL detail:[MSBAppSizeController class] cell:PSLinkCell edit:Nil];
	[link setProperty:bundle forKey:kMSBASBundleKey];
	SEL make = NSSelectorFromString(@"controllerForSpecifier:");
	UIViewController *page = [self respondsToSelector:make] ? ((id (*)(id, SEL, id))objc_msgSend)(self, make, link) : nil;
	if (![page isKindOfClass:[MSBAppSizeController class]]) return;
	[self showController:(PSViewController *)page animate:YES];
}
- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"App Window Sizes";
}
- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	_specifiers = nil; [self reloadSpecifiers];   // (back from an app's page or the picker: the list as stored now; nothing is opened from here)
}
- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	if (!_picked) return;   // (a pick waiting for the list to be back: its page a turn later, from the list settled; never pushed from here)
	__weak MSBAppSizesController *weakSelf = self;
	dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf msbOpenPickedWhenSettled]; });
}
@end
