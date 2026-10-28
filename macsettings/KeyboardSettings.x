#import <unistd.h>
// Keyboard (MacStatusBar&Dock, 2026-09-25): a "Keyboard" row in the Settings sidebar, shown only while a hardware keyboard is attached (like the
// Pointer row with a pointer), opening a small stock-looking page with the switches of the keyboard features that used to be separate tweaks:
// Top-Left Key as Escape (GraveEscape), Tab mutes (TabMute), Globe volume keys (VolumeGlobe) and the brightness keys (BrightnessKey). Each keeps its own
// preference domain and its own "prefsChanged" notification, so every switch applies at once, with no respring. All are off for a new install.
#import <UIKit/UIKit.h>
#import <notify.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import "../common/NativeEmbed.h"

@interface PSSpecifier : NSObject
+ (instancetype)preferenceSpecifierNamed:(NSString *)name target:(id)target set:(SEL)set get:(SEL)get detail:(Class)detail cell:(long long)cell edit:(Class)edit;
+ (instancetype)groupSpecifierWithName:(NSString *)name;
- (NSString *)identifier;
- (void)setIdentifier:(NSString *)identifier;
- (void)setProperty:(id)value forKey:(NSString *)key;
- (NSString *)name;
- (long long)cellType;
@end
@interface PSListController : UIViewController <UITableViewDelegate> { NSMutableArray *_specifiers; }
- (NSMutableArray *)specifiers;
- (void)reloadSpecifiers;
- (NSIndexPath *)indexPathForSpecifier:(PSSpecifier *)specifier;
@end

#define kKeyboardRowID @"MAC_KEYBOARD"
enum { kCellLinkList = 2, kCellSwitch = 6 };

// Whether a hardware keyboard is attached right now: the same flag UIKit uses to choose between the on-screen keyboard and the shortcut bar.
BOOL MSKeyboardAttached(void) {
#if DEBUG
    if (access("/tmp/msb-fakekb", F_OK) == 0) return YES;   // (debug: test the Keyboard page without a hardware keyboard)
    if (access("/tmp/msb-nokb", F_OK) == 0) return NO;      // (debug: as if no hardware keyboard were attached -- the rows that follow one)
#endif
    static BOOL (*attached)(void) = NULL; static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *gs = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_LAZY);
        if (gs) attached = (BOOL (*)(void))dlsym(gs, "GSEventIsHardwareKeyboardAttached");
    });
    return attached ? attached() : NO;
}
static UIImage *MSKeyboardIcon(void) {   // a 29 pt rounded square with the keyboard glyph, like the other Settings rows
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(29, 29)];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[UIColor systemGrayColor] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 29, 29) cornerRadius:6.5] fill];
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold];
        UIImage *glyph = [[UIImage systemImageNamed:@"keyboard" withConfiguration:cfg] imageWithTintColor:[UIColor whiteColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
        if (glyph) [glyph drawInRect:CGRectMake((29 - glyph.size.width) / 2.0, (29 - glyph.size.height) / 2.0, glyph.size.width, glyph.size.height)];
    }];
}

static PSSpecifier *MSKeySwitch(id target, NSString *label, NSString *domain, NSString *key) {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:label target:target set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:kCellSwitch edit:nil];
    [s setProperty:key forKey:@"key"];
    [s setProperty:domain forKey:@"defaults"];
    [s setProperty:@NO forKey:@"default"];
    [s setProperty:[domain stringByAppendingString:@"/prefsChanged"] forKey:@"PostNotification"];
    return s;
}
static PSSpecifier *MSKeyGroup(NSString *title, NSString *footer) {
    PSSpecifier *g = [PSSpecifier groupSpecifierWithName:title];
    if (footer) [g setProperty:footer forKey:@"footerText"];
    return g;
}

@interface MSKeyboardListController : PSListController
@end
// Requested (2026-09-25): the keys' conditions are shown only when one is NOT met while that key is switched on, as one short sentence after the group's
// footer, tappable to Apple's Modifier Keys page (on this same page now). Found from each tweak's own code:
//  - Globe volume (VolumeGlobe.x): needs the Globe modifier flag, i.e. the Globe key set to "Globe" in Modifier Keys, and the Option/Control keys
//    themselves (HID usages 226/224, so not remapped to something else);
//  - backlight keys (BrightnessKey.x): Shift + Option/Control (not remapped), and a keyboard with a backlight (Apple's page then shows its own
//    "Keyboard Brightness" slider -- the same test Apple uses);
//  - Top-Left Key as Escape and Tab mute have no condition (any keyboard with those keys).
static BOOL MSKeyOn(NSString *domain, NSString *key) {
    CFPropertyListRef v = CFPreferencesCopyValue((__bridge CFStringRef)key, (__bridge CFStringRef)domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    BOOL on = v && CFGetTypeID(v) == CFBooleanGetTypeID() && CFBooleanGetValue(v);
    if (v) CFRelease(v);
    return on;
}
NSDictionary *MSModifierMapping(void);   // (below: Apple's Modifier Keys choices for the attached keyboard, source usage -> destination usage)
static void MSKeysSetFooter(PSSpecifier *g, NSArray *native, id linkTarget);
void MSKeysOpenModifierKeysOn(PSListController *page);
// Our keys' group and its five switches (target: whatever reads and writes the switches' preferences -- our page, or on iPadOS 18 a helper on
// Apple's Hardware Keyboard page, AppleGroups18.x). title: the group's header (none on our page). native: Apple's Hardware Keyboard rows, for the
// footer's hint. linkTarget: answers -msOpenModifierKeys (the hint's link).
NSArray *MSKeysGroupSpecifiers(id target, NSString *title, NSArray *native, id linkTarget) {
    NSMutableArray *s = [NSMutableArray array];
    PSSpecifier *g = MSKeyGroup(title, nil);
    [g setIdentifier:@"MAC_KEYS_GROUP"];
    [s addObject:g];
    [s addObject:MSKeySwitch(target, @"Top-Left Key as Escape", @"com.besiktasliseba.graveescapetweak", @"enabled")];   // (KT, 25 Oct: named for the key it maps, the top-left one on every layout; the setting key stays "enabled")
    [s addObject:MSKeySwitch(target, @"Tab Key Toggles Mute", @"com.besiktasliseba.tabmutetweak", @"enabled")];
    [s addObject:MSKeySwitch(target, @"Globe + Option/Control for Volume", @"com.besiktasliseba.volumeglobetweak", @"enabled")];
    [s addObject:MSKeySwitch(target, @"Shift + =/- for Screen Brightness", @"com.besiktasliseba.brightnesskeytweak", @"screenKeysEnabled")];
    [s addObject:MSKeySwitch(target, @"Shift + Option/Control for Backlight", @"com.besiktasliseba.brightnesskeytweak", @"backlightKeysEnabled")];
    MSKeysSetFooter(g, native, linkTarget);
    return s;
}
@implementation MSKeyboardListController {
    NSMutableArray *_msNativePages;   // Apple's Hardware Keyboard page (never shown), whose rows are on this page
}
- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        // Apple's own Hardware Keyboard settings, live (see common/NativeEmbed.h): layouts, Auto-Capitalization, "." Shortcut, Keyboard
        // Brightness, Modifier Keys, Keyboard Type. They start with their own group.
        _msNativePages = [NSMutableArray array];
        NSArray *hw = MSNESpecifiers(self, @"TIHardwareKeyboardController", @[@"/System/Library/PreferenceBundles/KeyboardSettings.bundle"], @"Hardware Keyboard", _msNativePages, nil);
        NSMutableArray *s = [NSMutableArray arrayWithArray:MSKeysGroupSpecifiers(self, nil, hw, self)];
        if (hw.count) [s addObjectsFromArray:hw];
        _specifiers = s;
    }
    return _specifiers;
}
- (void)msOpenModifierKeys { MSKeysOpenModifierKeysOn(self); }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Keyboard";
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];   // back from Modifier Keys or a layout page: the footer's hint and Apple's rows are read again
}
@end
// The group's footer: what the keys are for, plus (only when needed) the one condition that is not met.
static void MSKeysSetFooter(PSSpecifier *g, NSArray *native, id linkTarget) {
    NSString *base = @"For keyboards without a function row, like the original Magic Keyboard for iPad. The key at the top left, next to 1, becomes Escape; the others add volume and brightness keys.";
    NSDictionary *map = MSModifierMapping();
    NSNumber *(^dest)(long long) = ^NSNumber *(long long src) { return map[@(src)]; };
    // HID usages (page << 32 | usage, as Apple's Modifier Keys page stores them): Globe (consumer page 0x0C, usage 0x29D), left Control and
    // left Option (keyboard page 7, 0xE0 / 0xE2)
    long long kGlobe = 0xC0000029DLL, kControl = 0x7000000E0LL, kOption = 0x7000000E2LL;
    BOOL volume = MSKeyOn(@"com.besiktasliseba.volumeglobetweak", @"enabled"), backlight = MSKeyOn(@"com.besiktasliseba.brightnesskeytweak", @"backlightKeysEnabled");
    BOOL globeOK = !dest(kGlobe) || [dest(kGlobe) longLongValue] == kGlobe;
    BOOL optCtrlOK = (!dest(kOption) || [dest(kOption) longLongValue] == kOption) && (!dest(kControl) || [dest(kControl) longLongValue] == kControl);
    BOOL hasBacklight = NO;
    for (PSSpecifier *sp in native) if ([[sp identifier] isEqualToString:@"Keyboard Brightness"]) hasBacklight = YES;
    NSString *hint = nil; BOOL modifierHint = NO;
    if (volume && !globeOK) { hint = @"Volume keys need the Globe key set to Globe in Modifier Keys."; modifierHint = YES; }
    else if ((volume || backlight) && !optCtrlOK) { hint = @"Volume and backlight keys need Option and Control unchanged in Modifier Keys."; modifierHint = YES; }
    else if (backlight && native.count && !hasBacklight) hint = @"Backlight keys need a keyboard with a backlight.";
    NSString *text = base;
    // The screen brightness keys reach whichever app has the keyboard, except a package manager or TrollStore, which never load our part.
    if (MSKeyOn(@"com.besiktasliseba.brightnesskeytweak", @"screenKeysEnabled")) text = [text stringByAppendingString:@" Shift + =/- does not change the brightness while Sileo, Zebra, Filza or TrollStore is in front."];
    if (hint) text = [text stringByAppendingFormat:@" %@", hint];
    [g setProperty:text forKey:@"footerText"];
    if (modifierHint && linkTarget) {   // "Modifier Keys" in the hint opens Apple's Modifier Keys page
        NSRange r = [text rangeOfString:@"Modifier Keys" options:NSBackwardsSearch];
        [g setProperty:@"PSFooterHyperlinkView" forKey:@"footerCellClass"];
        [g setProperty:text forKey:@"headerFooterHyperlinkButtonTitle"];
        [g setProperty:NSStringFromRange(r) forKey:@"footerHyperlinkRange"];
        [g setProperty:[NSValue valueWithNonretainedObject:linkTarget] forKey:@"footerHyperlinkTarget"];
        [g setProperty:NSStringFromSelector(@selector(msOpenModifierKeys)) forKey:@"footerHyperlinkAction"];
    }
}
// Opens the "Modifier Keys" row of a page that shows Apple's Hardware Keyboard rows (ours, or Apple's own page on iPadOS 18), as a tap does.
void MSKeysOpenModifierKeysOn(PSListController *page) {
    for (PSSpecifier *sp in [page specifiers]) {
        if (![[sp name] isEqualToString:@"Modifier Keys"] || [sp cellType] != kCellLinkList) continue;
        NSIndexPath *ip = [page indexPathForSpecifier:sp];
        UITableView *t = nil; @try { t = [page valueForKey:@"table"]; } @catch (NSException *e) {}
        if (ip && [t isKindOfClass:[UITableView class]] && [page respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) [page tableView:t didSelectRowAtIndexPath:ip];
        return;
    }
}

// Apple's Modifier Keys choices, as its page writes them: com.apple.keyboard.preferences, { "<product>-<vendor>": [ {HIDKeyboardModifierMappingSrc,
// HIDKeyboardModifierMappingDst}, ... ] }, usages as (page << 32 | usage); no entry = the key does what it says. All keyboards' choices are merged (a
// hint is only a hint). The key is BackBoardServices' BKSHIDServicesModifierKeysRemappingPreferenceKey -- "ModifierKeysRemapping" on 17.5 --; the
// one before it, BKSHIDServicesOldModifierKeysRemappingPreferenceKey ("com.apple.keyboard.modifierKeysRemapping", the one found in September),
// is moved into it by backboardd (17.5, 1.6.0: a mapping written under the old key was under the new one a moment later). Only the old key was
// read, so on 17 the footer's Modifier Keys hint and its link never came. Both are read, by Apple's own names where it exports them; the current
// one wins for a keyboard in both.
static NSString *MSBKSPrefKey(const char *symbol, NSString *fallback) {
    static void *bks; static dispatch_once_t once;
    dispatch_once(&once, ^{ bks = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_LAZY); });
    CFStringRef *p = bks ? (CFStringRef *)dlsym(bks, symbol) : NULL;
    return (p && *p && CFGetTypeID(*p) == CFStringGetTypeID()) ? (__bridge NSString *)*p : fallback;
}
NSDictionary *MSModifierMapping(void) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    CFPreferencesAppSynchronize(CFSTR("com.apple.keyboard.preferences"));
    NSMutableDictionary *all = [NSMutableDictionary dictionary];
    for (NSString *key in @[MSBKSPrefKey("BKSHIDServicesOldModifierKeysRemappingPreferenceKey", @"com.apple.keyboard.modifierKeysRemapping"),
                            MSBKSPrefKey("BKSHIDServicesModifierKeysRemappingPreferenceKey", @"ModifierKeysRemapping")]) {   // (the current one last: it wins)
        NSDictionary *d = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, CFSTR("com.apple.keyboard.preferences"));
        if ([d isKindOfClass:[NSDictionary class]]) [all addEntriesFromDictionary:d];
    }
    for (id kb in all) {
        NSArray *list = all[kb];
        if (![list isKindOfClass:[NSArray class]]) continue;
        for (NSDictionary *m in list) {
            if (![m isKindOfClass:[NSDictionary class]]) continue;
            NSNumber *src = m[@"HIDKeyboardModifierMappingSrc"], *dst = m[@"HIDKeyboardModifierMappingDst"];
            if ([src isKindOfClass:[NSNumber class]] && [dst isKindOfClass:[NSNumber class]]) out[@([src longLongValue])] = @([dst longLongValue]);
        }
    }
    return out;
}

// The sidebar row, inserted by MacSettings.x's list hook right after the Pointer row.
PSSpecifier *MSKeyboardRowSpecifier(id target) {
    PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:@"Keyboard" target:target set:nil get:nil detail:[MSKeyboardListController class] cell:kCellLinkList edit:nil];
    [row setIdentifier:kKeyboardRowID];
    [row setProperty:MSKeyboardIcon() forKey:@"iconImage"];
    return row;
}
// Live: attaching or detaching a keyboard adds or removes the row in the open sidebar (GraphicsServices posts this Darwin notification).
void MSReloadSidebarKeepingScroll(PSListController *l);   // (PointerSettings.x)
void MSKeyboardWatchSidebar(PSListController *sidebar) {
    static __weak PSListController *gSidebar;
    gSidebar = sidebar;
    static int token = 0;
    if (token) return;
    notify_register_dispatch("GSEventHardwareKeyboardAvailabilityChangedNotification", &token, dispatch_get_main_queue(), ^(int t) {
        PSListController *l = gSidebar;
        if (!l) return;
        BOOL shown = NO;
        for (PSSpecifier *sp in [l specifiers]) if ([[sp identifier] isEqualToString:kKeyboardRowID]) { shown = YES; break; }
        if (shown != MSKeyboardAttached()) MSReloadSidebarKeepingScroll(l);
    });
}
