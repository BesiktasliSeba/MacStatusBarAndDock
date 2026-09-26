// MSBGoAppsController -- Settings > Status Bar > Go Menu > Apps (2026-09-25). Laid out like Apple's Control Center customization list: the apps in
// the Go menu first, in the menu's order, with red remove buttons and grab handles to reorder them; every other app below, by name, with green add
// buttons. The goApps array IS the menu's order (SpringBoard shows it as stored). Reynard, when it is not installed, stays offered at the very
// bottom (new installs have it in the menu, with GET), so it can be removed like any other app and added back. "Terminal" (@terminal, new installs)
// stands for the first installed terminal app: shown with that app's icon, and that app is not offered below meanwhile; no terminal: Not Installed.
// (A list of our own instead of AltList's picker: AltList has no reordering and only lists installed apps.)
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#import <Preferences/PSViewController.h>
#import <Preferences/PSSpecifier.h>

#define kGADomain CFSTR("com.besiktasliseba.macstatusbar")
static NSString *const kGAReynard = @"com.minh-ton.Reynard";
static NSString *const kGATerminal = @"@terminal";
#define kGATerminalApps (@[@"dev.diffterm.app", @"ws.hbang.Terminal", @"com.officialscheduler.mterminal", @"com.googlecode.mobileterminal.Terminal"])   // (same list in StatusBar.x)

@interface UIImage (MSBGoAppsIcon)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleID format:(int)format scale:(CGFloat)scale;
@end

@interface MSBGoAppsController : PSViewController <UITableViewDataSource, UITableViewDelegate>
@end

@implementation MSBGoAppsController {
	UITableView *_table;
	NSMutableArray<NSString *> *_chosen;   // the Go menu, in order
	NSArray<NSString *> *_others;          // everything else, by name (Reynard not installed: last)
	NSMutableDictionary<NSString *, NSString *> *_names;
	NSMutableDictionary<NSString *, UIImage *> *_icons;
	NSSet<NSString *> *_installed;
	NSString *_terminal;                   // the app "Terminal" stands for (nil: none installed)
}

static id GAProxy(NSString *bundleID) {
	Class c = objc_getClass("LSApplicationProxy");
	SEL s = NSSelectorFromString(@"applicationProxyForIdentifier:");
	return [(id)c respondsToSelector:s] ? ((id (*)(id, SEL, id))objc_msgSend)((id)c, s, bundleID) : nil;
}
static id GAValue(id obj, NSString *key) { @try { return [obj valueForKey:key]; } @catch (NSException *e) { return nil; } }

// The apps a person can open from the Home Screen: installed, not launch-prohibited, not tagged hidden.
static NSDictionary<NSString *, NSString *> *GAVisibleApps(void) {
	NSMutableDictionary *out = [NSMutableDictionary dictionary];
	id ws = ((id (*)(id, SEL))objc_msgSend)(objc_getClass("LSApplicationWorkspace"), NSSelectorFromString(@"defaultWorkspace"));
	SEL all = NSSelectorFromString(@"allInstalledApplications");
	NSArray *apps = [ws respondsToSelector:all] ? ((id (*)(id, SEL))objc_msgSend)(ws, all) : nil;
	for (id p in apps) {
		NSString *bid = GAValue(p, @"bundleIdentifier"), *name = GAValue(p, @"localizedName");
		if (![bid isKindOfClass:[NSString class]] || !bid.length) continue;
		if ([GAValue(p, @"isLaunchProhibited") boolValue]) continue;
		NSArray *tags = GAValue(p, @"appTags");
		if ([tags isKindOfClass:[NSArray class]] && [tags containsObject:@"hidden"]) continue;
		out[bid] = [name isKindOfClass:[NSString class]] && name.length ? name : bid;
	}
	return out;
}

// The stored list; the first time, the order the Go menu had before it could be reordered (Calendar and Reynard, then the rest by name) -- the same
// rule SpringBoard uses when it converts (DMGoAppBundleIDs), so an update keeps its menu order whichever side converts first.
static NSArray<NSString *> *GAStoredOrder(NSDictionary<NSString *, NSString *> *names) {
	CFPreferencesAppSynchronize(kGADomain);
	CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("goApps"), kGADomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	id stored = v ? CFBridgingRelease(v) : nil;
	NSMutableArray *list = [NSMutableArray array];
	if ([stored isKindOfClass:[NSArray class]]) { for (id b in stored) if ([b isKindOfClass:[NSString class]] && ![list containsObject:b]) [list addObject:b]; }
	else if ([stored isKindOfClass:[NSDictionary class]]) { for (NSString *b in stored) if ([stored[b] boolValue]) [list addObject:b]; }
	else if (!stored) return @[@"com.apple.mobilecal", kGATerminal, @"com.apple.Maps", kGAReynard];   // (never saved: SpringBoard's seed, in order)
	CFPropertyListRef o = CFPreferencesCopyValue(CFSTR("goAppsOrdered"), kGADomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	BOOL ordered = o != NULL; if (o) CFRelease(o);
	if (ordered) return list;
	NSArray *original = @[@"com.apple.mobilecal", kGAReynard];   // (legacy lists only: the same rule as StatusBar.x)
	NSMutableArray *front = [NSMutableArray array], *rest = [NSMutableArray array];
	for (NSString *b in original) if ([list containsObject:b]) [front addObject:b];
	for (NSString *b in list) if (![original containsObject:b]) [rest addObject:b];
	[rest sortUsingComparator:^NSComparisonResult(NSString *x, NSString *y) {
		NSString *nx = names[x] ?: GAValue(GAProxy(x), @"localizedName") ?: x, *ny = names[y] ?: GAValue(GAProxy(y), @"localizedName") ?: y;
		return [nx localizedCaseInsensitiveCompare:ny];
	}];
	[front addObjectsFromArray:rest];
	return front;
}

- (void)save {
	CFPreferencesSetValue(CFSTR("goApps"), (__bridge CFPropertyListRef)[_chosen copy], kGADomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	CFPreferencesSetValue(CFSTR("goAppsOrdered"), kCFBooleanTrue, kGADomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	CFPreferencesSynchronize(kGADomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	notify_post("com.besiktasliseba.macstatusbar/prefsChanged");
}

- (void)reloadLists {
	NSDictionary *visible = GAVisibleApps();
	_installed = [NSSet setWithArray:visible.allKeys];
	_names = [visible mutableCopy];
	if (!_names[kGAReynard]) _names[kGAReynard] = @"Reynard";
	_names[kGATerminal] = @"Terminal";
	_terminal = nil;
	for (NSString *t in kGATerminalApps) if ([_installed containsObject:t]) { _terminal = t; break; }
	// (a built-in choice, when not installed, by its name instead of its bundle ID)
	NSDictionary *known = @{ @"com.apple.mobilecal": @"Calendar" };
	for (NSString *b in known) if (!_names[b]) _names[b] = known[b];
	_chosen = [GAStoredOrder(visible) mutableCopy];
	NSMutableArray *others = [NSMutableArray array];
	for (NSString *b in visible) if (![_chosen containsObject:b] && !([b isEqualToString:_terminal] && [_chosen containsObject:kGATerminal])) [others addObject:b];
	[others sortUsingComparator:^NSComparisonResult(NSString *x, NSString *y) { return [self->_names[x] localizedCaseInsensitiveCompare:self->_names[y]]; }];
	if (![_installed containsObject:kGAReynard] && ![_chosen containsObject:kGAReynard]) [others addObject:kGAReynard];   // (least prominent: last)
	_others = others;
}

- (void)loadView {
	_table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	_table.dataSource = self; _table.delegate = self;
	_table.editing = YES;
	_table.allowsSelectionDuringEditing = YES;
	self.view = _table;
}
- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Apps";
	_icons = [NSMutableDictionary dictionary];
	[self reloadLists];
	CFPropertyListRef o = CFPreferencesCopyValue(CFSTR("goAppsOrdered"), kGADomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	if (o) CFRelease(o); else [self save];   // (the order the menu had, written down once)
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return section == 0 ? _chosen.count : _others.count; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section { return section == 0 ? @"Include" : @"More Apps"; }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section { return section == 0 ? @"Drag to change the order of the apps in the Go menu." : nil; }
- (NSString *)bundleAt:(NSIndexPath *)ip { return ip.section == 0 ? _chosen[ip.row] : _others[ip.row]; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"app"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"app"];
	NSString *b = [self bundleAt:ip];
	cell.textLabel.text = _names[b] ?: b;
	NSString *detail = nil;
	if ([b isEqualToString:kGATerminal]) {   // shown as the app it stands for (its name underneath, unless that is "Terminal" too)
		b = _terminal ?: kGATerminal;
		if (_terminal && ![_names[_terminal] isEqualToString:@"Terminal"]) detail = _names[_terminal];
	}
	BOOL missing = ![_installed containsObject:b];
	cell.detailTextLabel.text = missing ? @"Not Installed" : detail;
	cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
	UIImage *icon = _icons[b];
	if (!icon && !missing && [UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) {
		icon = [UIImage _applicationIconImageForBundleIdentifier:b format:0 scale:[UIScreen mainScreen].scale];
		if (icon) _icons[b] = icon;
	}
	if (!icon) {   // (not installed: a plain placeholder the size of an app icon)
		UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(29, 29)];
		icon = [r imageWithActions:^(UIGraphicsImageRendererContext *c) {
			[[UIColor tertiarySystemFillColor] setFill];
			[[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 29, 29) cornerRadius:6.5] fill];
		}];
	}
	cell.imageView.image = icon;
	cell.showsReorderControl = ip.section == 0;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	return cell;
}
- (UITableViewCellEditingStyle)tableView:(UITableView *)tv editingStyleForRowAtIndexPath:(NSIndexPath *)ip {
	return ip.section == 0 ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleInsert;
}
- (NSString *)tableView:(UITableView *)tv titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)ip { return @"Remove"; }
- (BOOL)tableView:(UITableView *)tv canMoveRowAtIndexPath:(NSIndexPath *)ip { return ip.section == 0; }
- (NSIndexPath *)tableView:(UITableView *)tv targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)from toProposedIndexPath:(NSIndexPath *)to {
	if (to.section == 0) return to;
	return [NSIndexPath indexPathForRow:(NSInteger)_chosen.count - 1 inSection:0];   // (stays in the menu: removing is the red button)
}
- (void)tableView:(UITableView *)tv moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
	NSString *b = _chosen[from.row];
	[_chosen removeObjectAtIndex:from.row];
	[_chosen insertObject:b atIndex:to.row];
	[self save];
}
- (void)tableView:(UITableView *)tv commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)ip {
	NSString *b = [self bundleAt:ip];
	if (style == UITableViewCellEditingStyleDelete) [_chosen removeObject:b];
	else if (style == UITableViewCellEditingStyleInsert) [_chosen addObject:b];
	else return;
	[self save];
	[self reloadLists];
	[tv reloadData];
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {   // a tap on an app below adds it, like its green button
	if (ip.section == 1) [self tableView:tv commitEditingStyle:UITableViewCellEditingStyleInsert forRowAtIndexPath:ip];
}
- (BOOL)tableView:(UITableView *)tv shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)ip { return YES; }
@end
