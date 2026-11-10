// CustomShortcuts.x -- Settings > Keyboard > Custom Shortcuts (1.8.5 item 2, off unless switched on): make your own keyboard shortcuts, each opening
// an app or a URL, laying out the front window or going Home. The rules: common/CustomShortcutsRule.h; SpringBoard runs them
// (statusbar/CustomShortcuts.h). Based on KeyPilot by wanghuangjie (MIT; the notice in CustomShortcutsRule.h and third_party/KeyPilot/LICENSE): its
// rule format and actions; its app's recording page is rebuilt here as Settings pages, its app picker as AltList's (a dependency already).
// While KeyPilot is installed ours step aside (both would run each key) and its shortcuts can be imported.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#import <dlfcn.h>
#import "../common/ChoicePage.h"            // (kMSBDKeyPilotApp)
#import "../common/CustomShortcutsRule.h"

@interface PSSpecifier : NSObject
+ (instancetype)preferenceSpecifierNamed:(NSString *)name target:(id)target set:(SEL)set get:(SEL)get detail:(Class)detail cell:(long long)cell edit:(Class)edit;
+ (instancetype)groupSpecifierWithName:(NSString *)name;
- (id)propertyForKey:(NSString *)key;
- (void)setProperty:(id)value forKey:(NSString *)key;
- (void)setIdentifier:(NSString *)identifier;
- (NSString *)identifier;
- (void)setValues:(NSArray *)values titles:(NSArray *)titles shortTitles:(NSArray *)shortTitles;
@property (nonatomic) SEL buttonAction;
@end
@interface PSListController : UIViewController { NSMutableArray *_specifiers; }
- (NSMutableArray *)specifiers;
- (void)reloadSpecifiers;
- (PSSpecifier *)specifier;
- (void)reloadSpecifier:(PSSpecifier *)specifier;
- (PSSpecifier *)specifierForID:(NSString *)identifier;
- (NSInteger)indexForIndexPath:(NSIndexPath *)ip;
- (PSSpecifier *)specifierAtIndex:(NSInteger)i;
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip;
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip;
@end

enum { kCSCellLinkList = 2, kCSCellTitleValue = 4, kCSCellSwitch = 6, kCSCellButton = 13 };
BOOL MSKeyPilotIsInstalled(void);   // (KeyboardSettings.x: its app registered)

// ---- the rules, as stored ----
static NSArray<NSDictionary *> *MSCSRules(void) {
    CFPreferencesAppSynchronize(CFSTR(kMSBDCSDomain));
    NSArray *a = CFBridgingRelease(CFPreferencesCopyValue(CFSTR(kMSBDCSRules), CFSTR(kMSBDCSDomain), kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    NSMutableArray *out = [NSMutableArray array];
    for (id r in [a isKindOfClass:[NSArray class]] ? a : @[]) if ([r isKindOfClass:[NSDictionary class]]) [out addObject:r];
    return out;
}
static void MSCSSaveRules(NSArray *rules) {
    CFPreferencesSetValue(CFSTR(kMSBDCSRules), (__bridge CFPropertyListRef)rules, CFSTR(kMSBDCSDomain), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesAppSynchronize(CFSTR(kMSBDCSDomain));
    notify_post(kMSBDCSChanged);
}
static BOOL MSCSSwitchOn(void) {
    CFPreferencesAppSynchronize(CFSTR(kMSBDCSDomain));
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR(kMSBDCSEnabled), CFSTR(kMSBDCSDomain), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    BOOL on = v && CFGetTypeID(v) == CFBooleanGetTypeID() && CFBooleanGetValue(v);
    if (v) CFRelease(v);
    return on;
}
static NSArray *MSCSKeyPilotRules(void) {
    CFPreferencesAppSynchronize(CFSTR(kMSBDCSKeyPilotDomain));
    NSArray *a = CFBridgingRelease(CFPreferencesCopyValue(CFSTR(kMSBDCSKeyPilotRules), CFSTR(kMSBDCSKeyPilotDomain), kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    return [a isKindOfClass:[NSArray class]] ? a : @[];
}
// An app's name, from its bundle ID (the system's app record), or the ID.
static NSString *MSCSAppName(NSString *bundleID) {
    Class c = objc_getClass("LSApplicationProxy");
    SEL make = NSSelectorFromString(@"applicationProxyForIdentifier:");
    id proxy = [(id)c respondsToSelector:make] ? ((id (*)(id, SEL, id))objc_msgSend)((id)c, make, bundleID) : nil;
    NSString *name = nil;
    @try { name = [proxy valueForKey:@"localizedName"]; } @catch (NSException *e) {}
    return [name isKindOfClass:[NSString class]] && name.length ? name : bundleID;
}
// What a rule does, in words: "Open Calculator", "Open apple.com", "Left Half", "Home".
static NSString *MSCSActionTitle(NSString *action) {
    const char *v = MSBDCSActionValue(action.UTF8String);
    switch (MSBDCSActionKind(action.UTF8String)) {
        case kMSBDCSActApp: return [NSString stringWithFormat:@"Open %@", MSCSAppName(v ? @(v) : @"")];
        case kMSBDCSActURL: {
            NSURL *u = [NSURL URLWithString:v ? @(v) : @""];
            return [NSString stringWithFormat:@"Open %@", u.host.length ? u.host : (v ? @(v) : @"")];
        }
        case kMSBDCSActWindow: { const char *t = MSBDCSLayoutTitle(v); return t ? @(t) : @"Window Layout"; }
        case kMSBDCSActHome: return @"Home";
        default: return @"No Action";
    }
}
static NSString *MSCSRuleShortcut(NSDictionary *r) {
    if (![r[@"keyCode"] isKindOfClass:[NSNumber class]] || [r[@"keyCode"] longValue] <= 0) return @"None";
    return MSBDCSShortcutText([r[@"keyCode"] longValue], [r[@"key"] isKindOfClass:[NSString class]] ? r[@"key"] : @"", [r[@"modifiers"] unsignedLongLongValue]);
}
static void MSCSSetRecording(BOOL on) {
    static int token = 0;
    if (!token && notify_register_check(kMSBDCSRecordingNote, &token) != NOTIFY_STATUS_OK) { token = 0; return; }
    notify_set_state(token, on ? 1 : 0);
    notify_post(kMSBDCSRecordingNote);
}

// ======================================================================================================================================================
// One shortcut: its keys (recorded), what it does, and Delete. A new one is saved once it has both; each change of a saved one is saved at once.
@interface MSCSEditController : PSListController
@end
@implementation MSCSEditController {
    NSMutableDictionary *_rule;
    NSInteger _index;        // (its place in the saved rules; -1 while new and not saved yet)
    BOOL _recording;
    NSString *_message;      // (why the last keys can't be the shortcut, under the Shortcut row)
}
- (void)msLoadRule {
    if (_rule) return;
    NSNumber *i = [[self specifier] propertyForKey:@"msIndex"];
    NSArray *rules = MSCSRules();
    _index = [i isKindOfClass:[NSNumber class]] && i.integerValue >= 0 && i.integerValue < (NSInteger)rules.count ? i.integerValue : -1;
    _rule = _index >= 0 ? [rules[_index] mutableCopy] : [@{ @"enabled": @YES, @"action": @"" } mutableCopy];
}
- (void)msSave {
    BOOL hasKey = [_rule[@"keyCode"] longValue] > 0;
    int kind = MSBDCSActionKind([_rule[@"action"] UTF8String]);
    BOOL complete = hasKey && kind != kMSBDCSActNone && kind != kMSBDCSActShell;
    NSMutableArray *rules = [MSCSRules() mutableCopy];
    NSMutableDictionary *stored = [_rule mutableCopy];
    [stored removeObjectForKey:@"msPendingKind"];   // (the page's own note, never stored)
    if (_index >= 0 && _index < (NSInteger)rules.count) { if (complete) rules[_index] = [stored copy]; else return; }
    else if (complete && rules.count < kMSBDCSMaxRules) { [rules addObject:[stored copy]]; _index = (NSInteger)rules.count - 1; }
    else return;
    MSCSSaveRules(rules);
}
- (NSString *)msActionKindKey {
    switch (MSBDCSActionKind([_rule[@"action"] UTF8String])) {
        case kMSBDCSActApp: return @"app";
        case kMSBDCSActURL: return @"url";
        case kMSBDCSActWindow: return @"window";
        case kMSBDCSActHome: return @"home";
        default: return @"";
    }
}
- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        [self msLoadRule];
        NSMutableArray *s = [NSMutableArray array];
        PSSpecifier *g = [PSSpecifier groupSpecifierWithName:nil];
        [g setProperty:_recording ? @"Press the keys of your shortcut, with Command, Option, Control or Globe. Esc stops." : (_message ?: @"Tap Shortcut, then press the keys.") forKey:@"footerText"];
        [s addObject:g];
        // (a title-value row, its keys at its right; a tap starts the recording: -tableView:didSelectRowAtIndexPath: below)
        PSSpecifier *k = [PSSpecifier preferenceSpecifierNamed:@"Shortcut" target:self set:nil get:@selector(msShortcutValue:) detail:nil cell:kCSCellTitleValue edit:nil];
        [k setProperty:@YES forKey:@"enabled"];
        [k setIdentifier:@"CS_SHORTCUT"];
        [s addObject:k];
        // What it does: four choices, the chosen one checked; then what it acts on.
        PSSpecifier *ag = [PSSpecifier groupSpecifierWithName:@"Action"];
        [s addObject:ag];
        NSString *kind = [_rule[@"msPendingKind"] isKindOfClass:[NSString class]] ? _rule[@"msPendingKind"] : [self msActionKindKey];   // (the choice shown: a new one waits for its value)
        NSArray *kinds = @[@"app", @"url", @"window", @"home"], *titles = @[@"Open App", @"Open URL", @"Arrange Window", @"Go Home"];
        for (NSUInteger i = 0; i < kinds.count; i++) {
            PSSpecifier *c = [PSSpecifier preferenceSpecifierNamed:titles[i] target:self set:nil get:nil detail:nil cell:kCSCellButton edit:nil];
            c.buttonAction = @selector(msPickKind:);
            [c setProperty:kinds[i] forKey:@"msKind"];
            [c setProperty:@YES forKey:@"msPlain"];
            [c setIdentifier:[@"CS_KIND_" stringByAppendingString:kinds[i]]];
            if ([kind isEqualToString:kinds[i]]) [c setProperty:@YES forKey:@"msChecked"];
            [s addObject:c];
        }
        if ([kind isEqualToString:@"app"]) {
            [s addObject:[PSSpecifier groupSpecifierWithName:nil]];
            dlopen("/var/jb/Library/Frameworks/AltList.framework/AltList", RTLD_NOW);   // (its picker's class; Settings has not loaded it here)
            Class picker = NSClassFromString(@"ATLApplicationListSelectionController");
            // (AltList's picker reads and writes through this row's getter and setter: the bundle ID. Its value shown is the app's name: the cell, below)
            PSSpecifier *a = [PSSpecifier preferenceSpecifierNamed:@"App" target:self set:@selector(msSetApp:specifier:) get:@selector(msApp:) detail:picker cell:kCSCellLinkList edit:nil];
            [a setProperty:@[@{ @"sectionType": @"Visible" }] forKey:@"sections"];   // (AltList: the apps on the Home Screen)
            [a setProperty:@YES forKey:@"useSearchBar"];
            [a setProperty:@YES forKey:@"hideSearchBarWhileScrolling"];
            [a setIdentifier:@"CS_APP"];
            [s addObject:a];
        } else if ([kind isEqualToString:@"url"]) {
            PSSpecifier *ug = [PSSpecifier groupSpecifierWithName:nil];
            [ug setProperty:@"For example https://www.apple.com, or another app's link." forKey:@"footerText"];
            [s addObject:ug];
            // (a title-value row; a tap asks for the URL in an alert, -msAskURL. Settings' text cell kept its text until the page went: Return did
            //  not end the editing, M1 15.6.1, so nothing was saved while the page was open)
            PSSpecifier *u = [PSSpecifier preferenceSpecifierNamed:@"URL" target:self set:nil get:@selector(msURL:) detail:nil cell:kCSCellTitleValue edit:nil];
            [u setProperty:@YES forKey:@"enabled"];
            [u setIdentifier:@"CS_URL"];
            [s addObject:u];
        } else if ([kind isEqualToString:@"window"]) {
            [s addObject:[PSSpecifier groupSpecifierWithName:nil]];
            PSSpecifier *l = [PSSpecifier preferenceSpecifierNamed:@"Layout" target:self set:@selector(msSetLayout:specifier:) get:@selector(msLayout:) detail:NSClassFromString(@"PSListItemsController") cell:kCSCellLinkList edit:nil];
            NSMutableArray *vals = [NSMutableArray array], *tits = [NSMutableArray array];
            for (int i = 0; i < kMSBDCSLayoutCount; i++) { [vals addObject:@(kMSBDCSLayouts[i])]; [tits addObject:@(kMSBDCSLayoutTitles[i])]; }
            // (Settings' own values and titles: its choice page builds its rows from them and the row shows the title. Set as plain properties
            //  the page crashed in -[PSListItemsController prepareSpecifiersMetadata] and the row showed "left": M1 15.6.1, k02)
            [l setValues:vals titles:tits shortTitles:tits];
            [l setIdentifier:@"CS_LAYOUT"];
            [s addObject:l];
        }
        if (_index >= 0) {
            [s addObject:[PSSpecifier groupSpecifierWithName:nil]];
            PSSpecifier *d = [PSSpecifier preferenceSpecifierNamed:@"Delete Shortcut" target:self set:nil get:nil detail:nil cell:kCSCellButton edit:nil];
            d.buttonAction = @selector(msDelete:);
            [d setProperty:@YES forKey:@"msDestructive"];
            [d setIdentifier:@"CS_DELETE"];
            [s addObject:d];
        }
        _specifiers = s;
    }
    return _specifiers;
}
- (PSSpecifier *)msSpecifierAt:(NSIndexPath *)ip {
    NSInteger i = [self indexForIndexPath:ip];
    return i >= 0 && i < (NSInteger)_specifiers.count ? [self specifierAtIndex:i] : nil;
}
// The rows' looks: the action rows as plain rows with the chosen one checked, the App row's value the app's name, Delete in red.
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [super tableView:tv cellForRowAtIndexPath:ip];
    PSSpecifier *sp = [self msSpecifierAt:ip];
    if ([[sp propertyForKey:@"msPlain"] boolValue]) {
        c.textLabel.textColor = [UIColor labelColor];
        c.accessoryType = [[sp propertyForKey:@"msChecked"] boolValue] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    } else if ([[sp propertyForKey:@"msDestructive"] boolValue]) {
        c.textLabel.textColor = [UIColor systemRedColor];
    } else if ([[sp identifier] isEqualToString:@"CS_APP"]) {
        const char *v = MSBDCSActionValue([_rule[@"action"] UTF8String]);
        c.detailTextLabel.text = MSBDCSActionKind([_rule[@"action"] UTF8String]) == kMSBDCSActApp && v ? MSCSAppName(@(v)) : @"Choose";
    }
    return c;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    NSString *ident = [[self msSpecifierAt:ip] identifier];
    if ([ident isEqualToString:@"CS_SHORTCUT"]) {
        [tv deselectRowAtIndexPath:ip animated:YES];
        [self msRecord:nil];
        return;
    }
    if ([ident isEqualToString:@"CS_URL"]) {
        [tv deselectRowAtIndexPath:ip animated:YES];
        [self msStopRecording];
        [self msAskURL];
        return;
    }
    [super tableView:tv didSelectRowAtIndexPath:ip];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    [self msLoadRule];
    self.title = _index >= 0 ? @"Edit Shortcut" : @"New Shortcut";
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];   // (back from AltList's picker or the layouts: the choice made)
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self msStopRecording];
}
- (id)msShortcutValue:(PSSpecifier *)s { return _recording ? @"Type Shortcut…" : MSCSRuleShortcut(_rule); }
- (id)msApp:(PSSpecifier *)s {   // (the bundle ID: AltList checks that app in its list)
    const char *v = MSBDCSActionValue([_rule[@"action"] UTF8String]);
    return MSBDCSActionKind([_rule[@"action"] UTF8String]) == kMSBDCSActApp && v ? @(v) : nil;
}
- (void)msSetApp:(id)value specifier:(PSSpecifier *)s {   // (AltList's choice)
    if (![value isKindOfClass:[NSString class]] || ![value length]) return;
    _rule[@"action"] = [@"app:" stringByAppendingString:value];
    [_rule removeObjectForKey:@"msPendingKind"];
    [self msSave];
}
- (id)msURL:(PSSpecifier *)s {
    const char *v = MSBDCSActionValue([_rule[@"action"] UTF8String]);
    return MSBDCSActionKind([_rule[@"action"] UTF8String]) == kMSBDCSActURL && v ? @(v) : @"Enter";
}
- (void)msAskURL {
    const char *v = MSBDCSActionValue([_rule[@"action"] UTF8String]);
    NSString *now = MSBDCSActionKind([_rule[@"action"] UTF8String]) == kMSBDCSActURL && v ? @(v) : @"";
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"URL" message:@"The page or link this shortcut opens." preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) {
        f.text = now;
        f.placeholder = @"https://www.apple.com";
        f.keyboardType = UIKeyboardTypeURL;
        f.autocapitalizationType = UITextAutocapitalizationTypeNone;
        f.autocorrectionType = UITextAutocorrectionTypeNo;
        f.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    __weak typeof(self) weakSelf = self;
    __weak UIAlertController *wa = a;
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UIAlertAction *save = [UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [weakSelf msSetURL:wa.textFields.firstObject.text specifier:nil];
        [weakSelf reloadSpecifiers];
    }];
    [a addAction:save];
    a.preferredAction = save;   // (Return saves)
    [self presentViewController:a animated:YES completion:nil];
}
- (void)msSetURL:(id)value specifier:(PSSpecifier *)s {
    NSString *u = [value isKindOfClass:[NSString class]] ? [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : @"";
    if (u.length && ![u containsString:@":"]) u = [@"https://" stringByAppendingString:u];   // (apple.com typed: the web page)
    if (!u.length || ![NSURL URLWithString:u]) return;
    _rule[@"action"] = [@"url:" stringByAppendingString:u];
    [_rule removeObjectForKey:@"msPendingKind"];
    [self msSave];
}
- (id)msLayout:(PSSpecifier *)s {
    const char *v = MSBDCSActionValue([_rule[@"action"] UTF8String]);
    return MSBDCSActionKind([_rule[@"action"] UTF8String]) == kMSBDCSActWindow && v ? @(v) : nil;
}
- (void)msSetLayout:(id)value specifier:(PSSpecifier *)s {
    if (![value isKindOfClass:[NSString class]] || !MSBDCSLayoutTitle([value UTF8String])) return;
    _rule[@"action"] = [@"window:" stringByAppendingString:value];
    [_rule removeObjectForKey:@"msPendingKind"];
    [self msSave];
}
- (void)msPickKind:(PSSpecifier *)s {
    NSString *k = [s propertyForKey:@"msKind"];
    if ([k isEqualToString:[self msActionKindKey]]) { [_rule removeObjectForKey:@"msPendingKind"]; [self reloadSpecifiers]; return; }
    if ([k isEqualToString:@"home"]) { _rule[@"action"] = @"system:home"; [_rule removeObjectForKey:@"msPendingKind"]; [self msSave]; }
    else { _rule[@"msPendingKind"] = k; }   // (its value next: an app, a URL, a layout -- until it is given, a saved rule keeps doing what it did)
    [self reloadSpecifiers];
}
- (void)msDelete:(PSSpecifier *)s {
    NSMutableArray *rules = [MSCSRules() mutableCopy];
    if (_index >= 0 && _index < (NSInteger)rules.count) { [rules removeObjectAtIndex:(NSUInteger)_index]; MSCSSaveRules(rules); }
    [self.navigationController popViewControllerAnimated:YES];
}
// ---- recording: the page takes the keyboard's presses; SpringBoard's shortcuts wait meanwhile (kMSBDCSRecordingNote) ----
- (BOOL)canBecomeFirstResponder { return YES; }
- (void)msRecord:(PSSpecifier *)s {
    if (_recording) { [self msStopRecording]; [self reloadSpecifiers]; return; }
    _recording = YES;
    _message = nil;
    MSCSSetRecording(YES);
    [self becomeFirstResponder];
    [self reloadSpecifiers];
}
- (void)msStopRecording {
    if (!_recording) return;
    _recording = NO;
    MSCSSetRecording(NO);
    [self resignFirstResponder];
}
- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    if (!_recording) { [super pressesBegan:presses withEvent:event]; return; }
    for (UIPress *p in presses) {
        UIKey *k = p.key;
        if (!k) continue;
        long usage = (long)k.keyCode;
        unsigned long long mods = MSBDCSMods((unsigned long long)k.modifierFlags);
        NSString *chars = k.charactersIgnoringModifiers ?: @"";
        int why = MSBDCSCheck(usage, chars.UTF8String, mods);
        if (why == kMSBDCSNoKey) continue;   // (a modifier on its own: wait for the key)
        if (why == kMSBDCSEscape) { _message = nil; [self msStopRecording]; [self reloadSpecifiers]; return; }
        if (why == kMSBDCSOK) {
            NSArray *rules = MSCSRules();
            for (NSUInteger i = 0; i < rules.count; i++) {
                if ((NSInteger)i == _index) continue;
                if (MSBDCSSame([rules[i][@"keyCode"] longValue], [rules[i][@"modifiers"] unsignedLongLongValue], usage, mods)) { why = kMSBDCSTaken; break; }
            }
        }
        NSString *keys = MSBDCSShortcutText(usage, chars, mods);
        switch (why) {
            case kMSBDCSNeedsModifier: _message = [NSString stringWithFormat:@"%@ types text. Add Command, Option, Control or Globe.", keys]; break;
            case kMSBDCSWindowTiling: _message = [NSString stringWithFormat:@"%@ is a Window Tiling Shortcut. Choose other keys.", keys]; break;
            case kMSBDCSMacSwitcher: _message = [NSString stringWithFormat:@"%@ switches desktops in the Mac Switcher. Choose other keys.", keys]; break;
            case kMSBDCSTaken: _message = [NSString stringWithFormat:@"%@ is already one of your shortcuts.", keys]; break;
            default: {
                _message = nil;
                _rule[@"keyCode"] = @(usage);
                _rule[@"modifiers"] = @(mods);
                _rule[@"key"] = chars.length == 1 ? chars.lowercaseString : @"";
                [self msSave];
                break;
            }
        }
        [self msStopRecording];
        [self reloadSpecifiers];
        return;
    }
}
@end

// ======================================================================================================================================================
// The list: the switch, each shortcut (what it does, its keys), Add Shortcut, and with KeyPilot installed its import.
@interface MSCSListController : PSListController
@end
@implementation MSCSListController {
    NSString *_importNote;
}
- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        BOOL kp = MSKeyPilotIsInstalled();
        NSMutableArray *s = [NSMutableArray array];
        PSSpecifier *g = [PSSpecifier groupSpecifierWithName:nil];
        NSString *foot = @"Your own keyboard shortcuts open an app or a URL, arrange the front window, or go Home. Custom Shortcuts is based on KeyPilot by wanghuangjie.";
        if (kp) foot = [foot stringByAppendingString:@" While KeyPilot is installed, its own shortcuts work and these wait, so each key does one thing."];
        [g setProperty:foot forKey:@"footerText"];
        [s addObject:g];
        PSSpecifier *sw = [PSSpecifier preferenceSpecifierNamed:@"Custom Shortcuts" target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:kCSCellSwitch edit:nil];
        [sw setProperty:@kMSBDCSEnabled forKey:@"key"];
        [sw setProperty:@kMSBDCSDomain forKey:@"defaults"];
        [sw setProperty:@NO forKey:@"default"];
        [sw setProperty:@kMSBDCSChanged forKey:@"PostNotification"];
        [sw setIdentifier:@"CS_SWITCH"];
        [s addObject:sw];
        NSArray *rules = MSCSRules();
        PSSpecifier *rg = [PSSpecifier groupSpecifierWithName:@"Shortcuts"];
        if (!rules.count) [rg setProperty:@"No shortcuts yet." forKey:@"footerText"];
        [s addObject:rg];
        for (NSUInteger i = 0; i < rules.count; i++) {
            PSSpecifier *r = [PSSpecifier preferenceSpecifierNamed:MSCSActionTitle([rules[i][@"action"] isKindOfClass:[NSString class]] ? rules[i][@"action"] : @"")
                                                            target:self set:nil get:@selector(msRuleKeys:) detail:[MSCSEditController class] cell:kCSCellLinkList edit:nil];
            [r setProperty:@(i) forKey:@"msIndex"];
            [r setIdentifier:[NSString stringWithFormat:@"CS_RULE_%lu", (unsigned long)i]];
            [s addObject:r];
        }
        if (rules.count < kMSBDCSMaxRules) {
            PSSpecifier *add = [PSSpecifier preferenceSpecifierNamed:@"Add Shortcut" target:self set:nil get:nil detail:[MSCSEditController class] cell:kCSCellLinkList edit:nil];
            [add setProperty:@(-1) forKey:@"msIndex"];
            [add setIdentifier:@"CS_ADD"];
            [s addObject:add];
        }
        if (kp) {
            NSUInteger n = MSCSKeyPilotRules().count;
            PSSpecifier *ig = [PSSpecifier groupSpecifierWithName:@"KeyPilot"];
            [ig setProperty:_importNote ?: [NSString stringWithFormat:@"KeyPilot has %lu shortcut%@. Importing copies them here; KeyPilot keeps its own. Shell commands are not imported.", (unsigned long)n, n == 1 ? @"" : @"s"] forKey:@"footerText"];
            [s addObject:ig];
            PSSpecifier *im = [PSSpecifier preferenceSpecifierNamed:@"Import KeyPilot's Shortcuts" target:self set:nil get:nil detail:nil cell:kCSCellButton edit:nil];
            im.buttonAction = @selector(msImport:);
            [im setIdentifier:@"CS_IMPORT"];
            if (!n) [im setProperty:@NO forKey:@"enabled"];
            [s addObject:im];
        }
        _specifiers = s;
    }
    return _specifiers;
}
- (id)msRuleKeys:(PSSpecifier *)s {
    NSArray *rules = MSCSRules();
    NSUInteger i = [[s propertyForKey:@"msIndex"] unsignedIntegerValue];
    return i < rules.count ? MSCSRuleShortcut(rules[i]) : @"";
}
- (void)msImport:(PSSpecifier *)s {
    NSUInteger shell = 0, other = 0, before = MSCSRules().count;
    NSArray *merged = MSBDCSImport(MSCSKeyPilotRules(), MSCSRules(), &shell, &other);
    NSUInteger added = merged.count - before;
    if (added) MSCSSaveRules(merged);
    NSMutableString *n = [NSMutableString stringWithFormat:@"Imported %lu shortcut%@.", (unsigned long)added, added == 1 ? @"" : @"s"];
    if (shell) [n appendFormat:@" %lu shell command%@ left out.", (unsigned long)shell, shell == 1 ? @"" : @"s"];
    if (other) [n appendFormat:@" %lu left out: already here, not a key this tweak allows, or no action it runs.", (unsigned long)other];
    _importNote = n;
    [self reloadSpecifiers];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Custom Shortcuts";
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];   // (back from a shortcut's page: its words and keys)
}
@end

// The Keyboard page's row to the list (KeyboardSettings.x): On or Off at its right.
@interface MSCSRowTarget : NSObject
@end
@implementation MSCSRowTarget
- (id)msCSSummary:(PSSpecifier *)s { return MSCSSwitchOn() ? @"On" : @"Off"; }
@end
PSSpecifier *MSCustomShortcutsRowSpecifier(void) {
    static MSCSRowTarget *target;
    if (!target) target = [MSCSRowTarget new];
    PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:@"Custom Shortcuts" target:target set:nil get:@selector(msCSSummary:) detail:[MSCSListController class] cell:kCSCellLinkList edit:nil];
    [row setIdentifier:@"MAC_CUSTOM_SHORTCUTS"];
    return row;
}
