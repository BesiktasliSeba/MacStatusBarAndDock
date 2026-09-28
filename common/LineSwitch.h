// LineSwitch.h -- the on/off switch at the top of the Status Bar and Dock pages (MacStatusBar&Dock, 2026-09-25).
//
// The package shows two lines in Choicy / iCleaner Pro: MacStatusBar (everything except the Dock) and MacDock (the Dock). Each page's switch turns
// its line off or on exactly the way the user would in those apps, so they always agree:
//  - Choicy: the line's name in Choicy's global "denied tweaks" list (and, if SpringBoard has its own Choicy configuration in force, in that list
//    too). Written here, as mobile, the same way Choicy's own Settings page writes it, then Choicy is told to reload. Every change is recorded in
//    MacStatusBar-LineChanges.plist, so removing the package can take exactly our entries out again.
//  - iCleaner Pro only: iCleaner renames <line>.dylib to <line>.disabled in TweakInject, which needs root. The wanted state is written to our
//    preferences and the root helper (sshtoggled) is asked to rename; it re-reads the wish itself and only ever renames our own two loaders.
// The switch shows the real state (read from Choicy / TweakInject every time), so a change made in Choicy or iCleaner itself shows here too.
// Switching MacStatusBar off: the root helper notices at once and gives the window engines their own settings back; one respring finishes it.
#import <UIKit/UIKit.h>
#import <notify.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "VersionGate.h"
#import "CrashGuard.h"
#import "CrashExplain.h"

#define MSBD_TWEAKDIR @"/var/jb/usr/lib/TweakInject"
#define MSBD_CHOICY @"/var/jb/var/mobile/Library/Preferences/com.opa334.choicyprefs.plist"
#define MSBD_LINERECORD @"/var/jb/var/mobile/Library/Preferences/MacStatusBar-LineChanges.plist"
#define MSBD_DOMAIN CFSTR("com.besiktasliseba.macstatusbaranddock")

static BOOL MSBDFileExists(NSString *p) { return [[NSFileManager defaultManager] fileExistsAtPath:p]; }
static BOOL MSBDChoicyInstalled(void) {
	return MSBDFileExists([MSBD_TWEAKDIR stringByAppendingPathComponent:@"ChoicySB.dylib"]) || MSBDFileExists([MSBD_TWEAKDIR stringByAppendingPathComponent:@"Choicy.dylib"]);
}
static NSInteger MSBDChoicyMode(NSDictionary *sb) {   // 1 allow list, 2 deny list, 0 unknown (missing = 1)
	id m = sb[@"allowDenyMode"];
	if (!m) return 1;
	if (![m isKindOfClass:[NSNumber class]]) return 0;
	NSInteger v = [m integerValue];
	return (v == 1 || v == 2) ? v : 0;
}
static BOOL MSBDLineEnabled(NSString *line) {
	NSString *dylib = [MSBD_TWEAKDIR stringByAppendingPathComponent:[line stringByAppendingString:@".dylib"]];
	NSString *disabled = [MSBD_TWEAKDIR stringByAppendingPathComponent:[line stringByAppendingString:@".disabled"]];
	if (!MSBDFileExists(dylib) && MSBDFileExists(disabled)) return NO;   // iCleaner Pro
	if (!MSBDChoicyInstalled()) return YES;
	NSDictionary *c = [NSDictionary dictionaryWithContentsOfFile:MSBD_CHOICY];
	if ([c[@"globalDeniedTweaks"] isKindOfClass:[NSArray class]] && [c[@"globalDeniedTweaks"] containsObject:line]) return NO;
	NSDictionary *sb = [c[@"appSettings"] isKindOfClass:[NSDictionary class]] ? c[@"appSettings"][@"com.apple.springboard"] : nil;
	if ([sb isKindOfClass:[NSDictionary class]] && [sb[@"customTweakConfigurationEnabled"] boolValue] && ![sb[@"tweakInjectionDisabled"] boolValue]) {
		NSInteger mode = MSBDChoicyMode(sb);
		NSArray *list = mode == 2 ? sb[@"deniedTweaks"] : (mode == 1 ? sb[@"allowedTweaks"] : nil);
		BOOL listed = [list isKindOfClass:[NSArray class]] && [list containsObject:line];
		if (mode == 2 && listed) return NO;
		if (mode == 1 && !listed) return NO;
	}
	return YES;
}
static void MSBDRecord(NSMutableDictionary *record, NSString *listKey, NSString *entry, BOOL added) {
	NSMutableDictionary *l = [record[listKey] isKindOfClass:[NSDictionary class]] ? [record[listKey] mutableCopy] : [NSMutableDictionary new];
	NSString *before = l[entry];
	if ((added && [before isEqual:@"removed"]) || (!added && [before isEqual:@"added"])) [l removeObjectForKey:entry];   // back to the user's own state
	else l[entry] = added ? @"added" : @"removed";
	if (l.count) record[listKey] = l; else [record removeObjectForKey:listKey];
}
// Choicy: returns YES if its configuration changed
static BOOL MSBDChoicySetLine(NSString *line, BOOL on) {
	NSMutableDictionary *prefs = [[NSDictionary dictionaryWithContentsOfFile:MSBD_CHOICY] mutableCopy] ?: [NSMutableDictionary new];
	NSMutableDictionary *record = [[NSDictionary dictionaryWithContentsOfFile:MSBD_LINERECORD] mutableCopy] ?: [NSMutableDictionary new];
	BOOL changed = NO;
	NSMutableArray *global = [prefs[@"globalDeniedTweaks"] isKindOfClass:[NSArray class]] ? [prefs[@"globalDeniedTweaks"] mutableCopy] : [NSMutableArray new];
	if (!on && ![global containsObject:line]) { [global addObject:line]; MSBDRecord(record, @"globalDeniedTweaks", line, YES); changed = YES; }
	if (on && [global containsObject:line]) { while ([global containsObject:line]) [global removeObject:line]; MSBDRecord(record, @"globalDeniedTweaks", line, NO); changed = YES; }
	prefs[@"globalDeniedTweaks"] = global;
	if (on) {   // SpringBoard's own Choicy configuration, when in force, must not keep it off either
		NSMutableDictionary *apps = [prefs[@"appSettings"] isKindOfClass:[NSDictionary class]] ? [prefs[@"appSettings"] mutableCopy] : nil;
		NSMutableDictionary *sb = [apps[@"com.apple.springboard"] isKindOfClass:[NSDictionary class]] ? [apps[@"com.apple.springboard"] mutableCopy] : nil;
		NSInteger mode = MSBDChoicyMode(sb);
		if ([sb[@"customTweakConfigurationEnabled"] boolValue] && mode) {
			NSString *key = mode == 2 ? @"deniedTweaks" : @"allowedTweaks";
			NSMutableArray *list = [sb[key] isKindOfClass:[NSArray class]] ? [sb[key] mutableCopy] : [NSMutableArray new];
			NSString *rk = [@"app.com.apple.springboard." stringByAppendingString:key];
			if (mode == 2 && [list containsObject:line]) { while ([list containsObject:line]) [list removeObject:line]; MSBDRecord(record, rk, line, NO); changed = YES; }
			if (mode == 1 && ![list containsObject:line]) { [list addObject:line]; MSBDRecord(record, rk, line, YES); changed = YES; }
			sb[key] = list; apps[@"com.apple.springboard"] = sb; prefs[@"appSettings"] = apps;
		}
	}
	if (!changed) return NO;
	if (!prefs[@"preferenceVersion"]) prefs[@"preferenceVersion"] = @1;
	[record writeToFile:MSBD_LINERECORD atomically:YES];
	[prefs writeToFile:MSBD_CHOICY atomically:YES];
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.opa334.choicyprefs/ReloadPrefs"), NULL, NULL, YES);
	return YES;
}
static void MSBDRespringNow(void) {
	dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_NOW);
	dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW);
	Class actionClass = objc_getClass("SBSRelaunchAction"), serviceClass = objc_getClass("FBSSystemService");
	id action = actionClass ? ((id (*)(id, SEL, id, NSUInteger, id))objc_msgSend)(actionClass, NSSelectorFromString(@"actionWithReason:options:targetURL:"), @"RestartRenderServer", 4, nil) : nil;
	id service = serviceClass ? ((id (*)(id, SEL))objc_msgSend)(serviceClass, NSSelectorFromString(@"sharedService")) : nil;
	if (action && service) ((void (*)(id, SEL, id, id))objc_msgSend)(service, NSSelectorFromString(@"sendActions:withResult:"), [NSSet setWithObject:action], nil);
}
// Every respring from our Settings pages. (The VPN check, VPNRespring.h, is SpringBoard's: its restart gate holds this request while a respring could
// hang, and asks there.)
static void MSBDRespring(void) { MSBDRespringNow(); }
// The switch changed: apply it, then offer the respring that makes it real.
static void MSBDSetLine(NSString *line, BOOL on, UIViewController *presenter, void (^refresh)(void)) {
	NSString *title = nil, *message = nil;
	BOOL respring = NO;
	if (MSBDChoicyInstalled()) {
		MSBDChoicySetLine(line, on);
		respring = MSBDLineEnabled(line) == on;
		if (!respring) { title = @"Could Not Change"; message = [NSString stringWithFormat:@"Choicy still keeps %@ %@. Check Choicy's settings for SpringBoard.", line, on ? @"off" : @"on"]; }
	} else if (MSBDFileExists(@"/var/jb/usr/libexec/sshtoggled")) {
		CFPreferencesSetValue((__bridge CFStringRef)[@"line" stringByAppendingString:line], on ? kCFBooleanTrue : kCFBooleanFalse, MSBD_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
		CFPreferencesSynchronize(MSBD_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
		notify_post("com.besiktasliseba.lines.apply");
		respring = YES;
	} else { title = @"Choicy or iCleaner Pro Needed"; message = @"Switch it in Choicy or iCleaner Pro."; }
	if (respring) {
		title = @"Respring to Finish";
		message = on ? [NSString stringWithFormat:@"%@ turns on after a respring.", line] : [NSString stringWithFormat:@"%@ turns off after a respring.", line];
		// Both lines off: no part of ours loads in Settings any more, so both pages (and this switch) are gone after the respring (Loader.c)
		NSString *other = [line isEqualToString:@"MacDock"] ? @"MacStatusBar" : @"MacDock";
		if (!on && !MSBDLineEnabled(other))
			message = [message stringByAppendingFormat:@" With %@ off too, both pages leave Settings. To turn them back on, use %@.", other, MSBDChoicyInstalled() ? @"Choicy" : @"iCleaner Pro"];
	}
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
	if (respring) [alert addAction:[UIAlertAction actionWithTitle:@"Respring Now" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
		// (iCleaner Pro: the helper renames within a moment; wait for it, at most 3 s, before the respring -- off the main thread, so Settings
		// stays responsive meanwhile)
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
			for (int i = 0; i < 30 && MSBDLineEnabled(line) != on; i++) [NSThread sleepForTimeInterval:0.1];
			[NSThread sleepForTimeInterval:0.4];   // (the helper gives the engines back as soon as it sees the switch-off)
			dispatch_async(dispatch_get_main_queue(), ^{ MSBDRespring(); });
		});
	}]];
	[alert addAction:[UIAlertAction actionWithTitle:respring ? @"Later" : @"OK" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) { if (refresh) refresh(); }]];
	[presenter presentViewController:alert animated:YES completion:nil];
}

// "Enable Anyway" (only shown on an untested iPadOS version, see VersionGate.h): saved, then the respring that makes it real is offered.
#define MSBD_UNTESTED_CHANGED "com.besiktasliseba.macstatusbaranddock.untestedChanged"
static inline BOOL MSBDLineRuns(NSString *line) { return MSBDLineEnabled(line) && MSBDGateWanted(); }   // (the Settings rows' On / Off)
static void MSBDSetUntested(BOOL on, UIViewController *presenter, void (^refresh)(void)) {
	CFPreferencesSetValue(CFSTR(MSBD_GATE_KEY), on ? kCFBooleanTrue : kCFBooleanFalse, MSBD_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	CFPreferencesSetValue(CFSTR(MSBD_GUARD_ACTION_KEY), NULL, MSBD_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);   // (the crash guard's note goes)
	CFPreferencesSynchronize(MSBD_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	notify_post(MSBD_UNTESTED_CHANGED);
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Respring to Finish" message:on ? @"MacStatusBar&Dock turns on after a respring." : @"MacStatusBar&Dock turns off after a respring." preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"Respring Now" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { MSBDRespring(); }]];
	[alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) { if (refresh) refresh(); }]];
	[presenter presentViewController:alert animated:YES completion:nil];
}

// "Turn Back On" (15/16, after the crash guard switched its safe mode on): saved, then the respring that makes it real is offered.
static void MSBDLeaveSafeMode(UIViewController *presenter, void (^refresh)(void)) {
	NSString *message = MSBDSafeMode() ? @"MacStatusBar&Dock turns on after a respring." : @"What was turned off turns back on after a respring.";   // (the latter: step 1b's parts)
	CFPreferencesSetValue(CFSTR(MSBD_SAFE_KEY), NULL, MSBD_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	CFPreferencesSetValue(CFSTR(MSBD_GUARD_ACTION_KEY), NULL, MSBD_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	CFPreferencesSynchronize(MSBD_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	notify_post(MSBD_UNTESTED_CHANGED);
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Respring to Finish" message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"Respring Now" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { MSBDRespring(); }]];
	[alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) { if (refresh) refresh(); }]];
	[presenter presentViewController:alert animated:YES completion:nil];
}
static int MSBDGuardAction(void) { return MSBDExplainAction(); }   // (what the crash guard did: CrashGuard.h, 0 = nothing)
// The untested-version footer: what the crash guard did and why (CrashExplain.h, from its record), until "Enable Anyway" is changed again.
static NSString *MSBDUntestedFooter(void) {
	return MSBDGuardExplanation(MSBDGuardAction(), YES, NO) ?: @"Not tested on this iPadOS version. Enable at your own risk.";
}
// 15/16: the crash guard's footer (nil = nothing to say). Step 1's note goes once a switch on the pages is changed; the safe mode's with "Turn Back On".
static NSString *MSBDSafeModeFooter(void) {
	int action = MSBDGuardAction();
	if (MSBDSafeMode()) return MSBDGuardExplanation(action == 3 ? 3 : 2, NO, NO);
	if (action == 1 || action == 4) return MSBDGuardExplanation(action, NO, NO);   // (4: step 1b, only what crashed went off, CrashStep.h)
	return nil;
}
// The crash guard's note of a feature switch turned on on this page: the time, its domain, key and row title (what the guard's explanation names).
// Turned off, it is taken out; entries older than 10 min go (the guard only looks 2 min back). On 15/16 a change also ends the guard's "features
// turned off" note (step 1).
static void MSBDNoteSwitch(NSString *domain, NSString *key, NSString *title, BOOL was, BOOL on) {
	if (on == was || ![domain isKindOfClass:[NSString class]] || ![key isKindOfClass:[NSString class]] || ![domain hasPrefix:@"com.besiktasliseba."] || !key.length) return;
	int guardAction = MSBDGuardAction();   // (step 1b's note goes the same way, unless a part is no longer loaded: that one has "Turn Back On")
	if (!MSBDSafeMode() && ((MSBDVersionTested() && guardAction == 1) || (guardAction == 4 && !MSBDStepPartsOff(MSBDCrashRecord())))) {   // (step 1b's note on any version: it names the switch, not Enable Anyway)
		CFPreferencesSetValue(CFSTR(MSBD_GUARD_ACTION_KEY), NULL, MSBD_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
		CFPreferencesSynchronize(MSBD_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	}
	if ([key rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound) return;
	NSString *entry = [NSString stringWithFormat:@" %@ %@", domain, key];
	title = [[([title isKindOfClass:[NSString class]] ? title : @"") componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" "];
	if (title.length > 80) title = [title substringToIndex:80];
	long now = (long)time(NULL);
	NSMutableArray *lines = [NSMutableArray array];
	for (NSString *l in [[NSString stringWithContentsOfFile:@MSBD_GUARD_RECENT encoding:NSUTF8StringEncoding error:nil] componentsSeparatedByString:@"\n"]) {
		NSArray *p = [l componentsSeparatedByString:@" "];   // "<time> <domain> <key> <title...>"
		BOOL same = p.count >= 3 && [p[1] isEqualToString:domain] && [p[2] isEqualToString:key];
		if (l.length && !same && now - (long)[l longLongValue] < 600) [lines addObject:l];
	}
	if (on) [lines addObject:[NSString stringWithFormat:@"%ld%@%@%@", now, entry, title.length ? @" " : @"", title]];
	if (lines.count) [[[lines componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"] writeToFile:@MSBD_GUARD_RECENT atomically:YES encoding:NSUTF8StringEncoding error:nil];
	else unlink(MSBD_GUARD_RECENT);
}

// Opens the Report a Problem link (test builds: logged, and with /tmp/msb-report-dryrun not opened).
static void MSBDOpenReport(NSURL *url) {
#if DEBUG
	if (access("/tmp/macsettings-debug", F_OK) == 0) {   // (the exact address, for checking what the issue is filled with)
		FILE *f = fopen("/tmp/macsettings.log", "a"); if (f) { fprintf(f, "[report] %s\n", url.absoluteString.UTF8String); fclose(f); }
		if (access("/tmp/msb-report-dryrun", F_OK) == 0) return;
	}
#endif
	if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

// For the page's list controller (Root.plist: get msbd_lineEnabled:, set msbd_setLine:specifier:, and the line's name in "lineName").
#define MSBD_LINE_SWITCH_METHODS \
- (id)msbd_lineEnabled:(PSSpecifier *)specifier { return @(MSBDLineRuns([specifier propertyForKey:@"lineName"])); }   /* (what really runs: Off on an untested iPadOS or in safe mode) */ \
- (void)msbd_setLine:(id)value specifier:(PSSpecifier *)specifier { \
	__weak typeof(self) weakSelf = self; \
	if (!MSBDGateWanted()) { [self reloadSpecifier:specifier animated:NO]; return; }   /* (greyed then: Enable Anyway / Turn Back On come first) */ \
	MSBDSetLine([specifier propertyForKey:@"lineName"], [value boolValue], self, ^{ [weakSelf reloadSpecifier:specifier animated:NO]; [weakSelf msbd_lineMaybeChanged]; }); \
	[self msbd_lineMaybeChanged]; \
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [weakSelf msbd_lineMaybeChanged]; });   /* (iCleaner Pro: the helper renames a moment later) */ \
} \
/* The line switched off: only the switch stays (the rows below it would look live but do nothing), its footer says why, as Apple hides rows */ \
/* that depend on an off switch. (Call on the loaded specifiers, before they are returned.) */ \
- (NSMutableArray *)msbd_hideRowsWhenLineOff:(NSArray *)specs offFooter:(NSString *)footer { \
	NSUInteger at = NSNotFound; \
	for (NSUInteger i = 0; i < specs.count; i++) if ([((PSSpecifier *)specs[i]).identifier isEqualToString:@"MSBD_LINE"]) { at = i; break; } \
	NSMutableArray *out = [specs mutableCopy]; \
	if (at != NSNotFound && !MSBDLineEnabled([(PSSpecifier *)specs[at] propertyForKey:@"lineName"])) { \
		for (NSInteger i = (NSInteger)at - 1; i >= 0; i--) { PSSpecifier *g = specs[i]; if (g.cellType == PSGroupCell) { [g setProperty:footer forKey:@"footerText"]; break; } } \
		out = [[specs subarrayWithRange:NSMakeRange(0, at + 1)] mutableCopy]; \
	} \
	/* Untested iPadOS without Enable Anyway, or the crash guard's safe mode: nothing below runs, so every row is greyed (not live, and nothing */ \
	/* rewrites Choicy); only Enable Anyway / Turn Back On and Report a Problem stay live. */ \
	if (!MSBDGateWanted()) { \
		NSArray *live = @[@"MSBD_UNTESTED", @"MSBD_SAFE_ON", @"MSBD_GUARD_REPORT", @"REPORT_PROBLEM"]; \
		for (PSSpecifier *sp in out) if (sp.cellType != PSGroupCell && ![live containsObject:sp.identifier ?: @""]) [sp setProperty:@NO forKey:@"enabled"]; \
	} \
	return out; \
} \
- (void)msbd_lineMaybeChanged { \
	PSSpecifier *line = [self specifierForID:@"MSBD_LINE"]; \
	if (!line) return; \
	BOOL on = MSBDLineEnabled([line propertyForKey:@"lineName"]); \
	BOOL shown = NO;   /* (rows after the switch; the "last crash came from X" note, MSBD_OTHER_CRASH, does not count) */ \
	NSArray *all = [self specifiers]; \
	NSUInteger at = [all indexOfObjectIdenticalTo:line]; \
	for (NSUInteger i = at == NSNotFound ? all.count : at + 1; i < all.count; i++) if (![((PSSpecifier *)all[i]).identifier isEqualToString:@"MSBD_OTHER_CRASH"]) { shown = YES; break; } \
	if (on != shown) { _specifiers = nil; [self reloadSpecifiers]; } \
} \
- (NSArray *)msbd_untestedSpecifiers { \
	if (MSBDVersionTested()) { \
		NSString *footer = MSBDSafeModeFooter(); \
		if (!footer) return @[]; \
		PSSpecifier *group = [PSSpecifier groupSpecifierWithID:@"MSBD_SAFE_GROUP"]; \
		[group setProperty:footer forKey:@"footerText"]; \
		PSSpecifier *button = [PSSpecifier preferenceSpecifierNamed:@"Turn Back On" target:self set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil]; \
		button.identifier = @"MSBD_SAFE_ON"; \
		button.buttonAction = @selector(msbd_leaveSafeMode:); \
		if (!MSBDSafeMode()) return MSBDStepPartsOff(MSBDCrashRecord()) && MSBDGuardAction() == 4 ? @[group, button, [self msbd_reportButton]] : @[group, [self msbd_reportButton]];   /* (step 1b: a part is no longer loaded) */ \
		return @[group, button, [self msbd_reportButton]]; \
	} \
	PSSpecifier *group = [PSSpecifier groupSpecifierWithID:@"MSBD_UNTESTED_GROUP"]; \
	[group setProperty:MSBDUntestedFooter() forKey:@"footerText"]; \
	PSSpecifier *sw = [PSSpecifier preferenceSpecifierNamed:@"Enable Anyway" target:self set:@selector(msbd_setUntested:specifier:) get:@selector(msbd_untested:) detail:Nil cell:PSSwitchCell edit:Nil]; \
	sw.identifier = @"MSBD_UNTESTED"; \
	return MSBDGuardAction() ? @[group, sw, [self msbd_reportButton]] : @[group, sw]; \
} \
/* The crash guard's footer asks for Report a Problem: the button is right there, on both pages (CrashExplain.h builds the text). */ \
- (PSSpecifier *)msbd_reportButton { \
	PSSpecifier *b = [PSSpecifier preferenceSpecifierNamed:@"Report a Problem…" target:self set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil]; \
	b.identifier = @"MSBD_GUARD_REPORT"; \
	b.buttonAction = @selector(msbd_reportProblem:); \
	return b; \
} \
- (void)msbd_reportProblem:(PSSpecifier *)specifier { \
	SEL own = NSSelectorFromString(@"msb_reportProblem:");   /* (the Status Bar page knows the engine that really runs) */ \
	if ([self respondsToSelector:own]) { ((void (*)(id, SEL, id))objc_msgSend)(self, own, specifier); return; } \
	CFPropertyListRef e = CFPreferencesCopyValue(CFSTR("windowEngine"), CFSTR("com.besiktasliseba.macstatusbar"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost); \
	NSString *engine = e && CFGetTypeID(e) == CFStringGetTypeID() ? [(__bridge NSString *)e copy] : nil; \
	if (e) CFRelease(e); \
	MSBDOpenReport(MSBDReportProblemURL(engine)); \
} \
- (id)msbd_untested:(PSSpecifier *)specifier { return @(MSBDUntestedOptIn() != 0); } \
- (void)msbd_setUntested:(id)value specifier:(PSSpecifier *)specifier { \
	__weak typeof(self) weakSelf = self; \
	MSBDSetUntested([value boolValue], self, ^{ [weakSelf reloadSpecifier:specifier animated:NO]; }); \
	[self msbd_reloadUntestedFooter]; \
} \
- (void)msbd_leaveSafeMode:(PSSpecifier *)specifier { \
	__weak typeof(self) weakSelf = self; \
	MSBDLeaveSafeMode(self, ^{ typeof(self) me = weakSelf; if (me) { me->_specifiers = nil; [me reloadSpecifiers]; } }); \
} \
- (void)msbd_reloadUntestedFooter { \
	PSSpecifier *group = [self specifierForID:@"MSBD_UNTESTED_GROUP"]; \
	if (!group) return; \
	[group setProperty:MSBDUntestedFooter() forKey:@"footerText"]; \
	[self reloadSpecifier:group animated:NO]; \
	if (!MSBDGuardAction() && [self specifierForID:@"MSBD_GUARD_REPORT"]) [self removeSpecifierID:@"MSBD_GUARD_REPORT" animated:YES];   /* (the guard's note is gone) */ \
} \
/* (call first in -setPreferenceValue:specifier:) */ \
- (void)msbd_noteSwitch:(id)value specifier:(PSSpecifier *)specifier { \
	if (specifier.cellType != PSSwitchCell) return; \
	NSString *noteTitle = [specifier propertyForKey:@"msbGuardTitle"] ?: specifier.name;   /* (a row whose title alone says little, "Safari": the plist names it fully) */ \
	MSBDNoteSwitch([specifier propertyForKey:@"defaults"], [specifier propertyForKey:@"key"], [[specifier propertyForKey:@"msbInvert"] boolValue] ? nil : noteTitle, [[self readPreferenceValue:specifier] boolValue], [value boolValue]); \
	__weak typeof(self) weakSelf = self;   /* (the guard's note just went: its footer and button go too) */ \
	if (MSBDVersionTested() && [self specifierForID:@"MSBD_SAFE_GROUP"] && !MSBDSafeModeFooter()) \
		dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf removeSpecifierID:@"MSBD_GUARD_REPORT" animated:YES]; [weakSelf removeSpecifierID:@"MSBD_SAFE_GROUP" animated:YES]; }); \
	else if (!MSBDVersionTested() && !MSBDGuardAction() && [self specifierForID:@"MSBD_GUARD_REPORT"]) \
		dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf msbd_reloadUntestedFooter]; }); \
} \
- (void)viewWillAppear:(BOOL)animated { \
	[super viewWillAppear:animated]; \
	PSSpecifier *line = [self specifierForID:@"MSBD_LINE"]; \
	if (line) [self reloadSpecifier:line animated:NO]; \
	[self msbd_lineMaybeChanged]; \
	PSSpecifier *untested = [self specifierForID:@"MSBD_UNTESTED"]; \
	if (untested) { [self reloadSpecifier:untested animated:NO]; [self msbd_reloadUntestedFooter]; } \
}
