#import <unistd.h>
#import <signal.h>
#import <errno.h>
// Keyboard (MacStatusBar&Dock, 2026-09-25): a "Keyboard" row in the Settings sidebar, shown only while a hardware keyboard is attached (like the
// Pointer row with a pointer), opening a small stock-looking page with the switches of the keyboard features that used to be separate tweaks:
// Top-Left Key as Escape (GraveEscape), Tab mutes (TabMute), Globe volume keys (VolumeGlobe) and the brightness keys (BrightnessKey). Each keeps its own
// preference domain and its own "prefsChanged" notification, so every switch applies at once, with no respring. All are off for a new install;
// Window Tiling Shortcuts and Custom Shortcuts are on for one (1.8.7, KT 11 Nov; an update keeps what it had: sshtoggled's defaults v5).
// Where two keyboard features claim the same keys, the footers say which has them (1.8.7: common/KeyboardChords.h, the one table).
// The page, top to bottom (KT 12 Nov): your own shortcuts -- KeyPilot's row first while it is installed, then Custom Shortcuts --, Window Tiling
// Shortcuts, the five Mac key switches, then Apple's Hardware Keyboard rows.
#import <UIKit/UIKit.h>
#import "../common/MainListRows.h"   // (the sidebar read through it: never the row Settings fills in on its own queue, 1.7.9)
#import <notify.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import "../common/NativeEmbed.h"
#import "../common/InputDevices.h"   // (MSBDKeyboardAttached: read the same way by the Ethernet row's rule, EthernetFix.x -- 1.7.5)
#import "../common/ChoicePage.h"     // (KeyPilot's row, 1.8.3: GET or OPEN, as the choice pages' third-party rows)
#import "../common/ModifierTap.h"    // (Window Tiling Keys' switch: its key, domain and notification)
#import "../common/KeyboardChords.h" // (1.8.7: every keyboard feature's chords, and who has the ones two of them claim)
#import <objc/message.h>

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
enum { kCellLinkList = 2, kCellTitleValue = 4, kCellSwitch = 6, kCellStaticText = 7 };

// Whether a hardware keyboard is attached right now: the same flag UIKit uses to choose between the on-screen keyboard and the shortcut bar.
BOOL MSKeyboardAttached(void) { return MSBDKeyboardAttached(); }   // (common/InputDevices.h, shared with the Ethernet row's rule; debug flags /tmp/msb-fakekb, /tmp/msb-nokb)
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

static PSSpecifier *MSKeySwitchDefault(id target, NSString *label, NSString *domain, NSString *key, BOOL on) {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:label target:target set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:kCellSwitch edit:nil];
    [s setProperty:key forKey:@"key"];
    [s setProperty:domain forKey:@"defaults"];
    [s setProperty:@(on) forKey:@"default"];
    [s setProperty:[domain stringByAppendingString:@"/prefsChanged"] forKey:@"PostNotification"];
    return s;
}
static PSSpecifier *MSKeySwitch(id target, NSString *label, NSString *domain, NSString *key) { return MSKeySwitchDefault(target, label, domain, key, NO); }   // (off unless switched on)
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
static BOOL MSKeyOnDefault(NSString *domain, NSString *key, BOOL def) {   // (never set: def)
    CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
    CFPropertyListRef v = CFPreferencesCopyValue((__bridge CFStringRef)key, (__bridge CFStringRef)domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    BOOL on = v ? (CFGetTypeID(v) == CFBooleanGetTypeID() && CFBooleanGetValue(v)) : def;
    if (v) CFRelease(v);
    return on;
}
static BOOL MSKeyOn(NSString *domain, NSString *key) { return MSKeyOnDefault(domain, key, NO); }
NSDictionary *MSModifierMapping(void);   // (below: Apple's Modifier Keys choices for the attached keyboard, source usage -> destination usage)
static void MSKeysSetFooter(PSSpecifier *g, NSArray *native, id linkTarget);

// ---- Keys two features claim (1.8.7, KT 11 Nov): which has them, said in the footers (common/KeyboardChords.h) ----
// Your own shortcut wins over a built-in one with the same keys (the built-in one is off for those keys); a tap (volume, backlight) and a shortcut
// that starts with it both work, the tap then only when pressed and let go alone. The footers say it where it happens now.
void MSCSYoursNow(MSBDKCYoursSet *y);   // (CustomShortcuts.x: your own shortcuts now -- Custom Shortcuts' taken, KeyPilot's while installed)
static BOOL MSKCWindowKeysOn(void) { return MSKeyOnDefault(@kMSBDWindowKeysDomain, @kMSBDWindowKeysKey, YES); }   // (never set: on, 1.8.7)
static BOOL MSKCMacSwitcherOn(void) { return MSKeyOn(@kMSBDWindowKeysDomain, @"macSwitcher"); }
// The key left of 1 on the attached keyboard, as Top-Left Key as Escape reads it (its layout state, set by SpringBoard): 0 on a JIS keyboard.
static long MSKCTopLeftUsage(void) {
    int t = 0; uint64_t v = 0;
    if (notify_register_check("com.besiktasliseba.graveescapetweak.layout", &t) != NOTIFY_STATUS_OK) return kMSBDKCTopLeftANSI;
    BOOL ok = notify_get_state(t, &v) == NOTIFY_STATUS_OK;
    notify_cancel(t);
    return ok && v == 2 ? kMSBDKCTopLeftISO : ok && v == 3 ? 0 : kMSBDKCTopLeftANSI;
}
// Whether Window Tiling Shortcuts can act now, as the volume and backlight taps read it: SpringBoard's offered state (the switch on and one of our
// window engines running, or one of our own windows in front: statusbar/WindowKeys.h DMWinKeysWanted, common/ModifierTap.h). The taps wait for
// their release only then (review 1.8.7: the footer said so whenever the switch was on, with no engine too). A state left by a SpringBoard that
// has ended (its pid in the state's top half) is not.
static BOOL MSKCWindowKeysOffered(void) {
    int t = 0; uint64_t st = 0;
    if (notify_register_check(kMSBDWindowKeysOfferedNote, &t) != NOTIFY_STATUS_OK) return NO;
    BOOL ok = notify_get_state(t, &st) == NOTIFY_STATUS_OK;
    notify_cancel(t);
    pid_t pid = (pid_t)(st >> 32);
    return ok && (st & 1ULL) && pid > 0 && (kill(pid, 0) == 0 || errno == EPERM);
}
// "A", "A and B", "A, B and C"; more than four: the first four and how many more.
static NSString *MSKCList(NSArray<NSString *> *items) {
    NSUInteger n = items.count;
    if (!n) return @"";
    if (n == 1) return items[0];
    if (n <= 4) return [NSString stringWithFormat:@"%@ and %@", [[items subarrayWithRange:NSMakeRange(0, n - 1)] componentsJoinedByString:@", "], items[n - 1]];
    return [NSString stringWithFormat:@"%@ and %lu more", [[items subarrayWithRange:NSMakeRange(0, 4)] componentsJoinedByString:@", "], (unsigned long)(n - 4)];
}
static NSString *MSKCYoursText(const MSBDKCYoursSet *y, unsigned i) {
    return MSBDCSShortcutText(y->usage[i], @(y->key[i]), y->mods[i]);
}
// Window Tiling's row as a Mac menu shows it (its key on a US layout).
static NSString *MSKCWinRowText(int row) {
    if (row < 0 || row >= (int)kMSBDWinKeyRowCount) return @"";
    static const long usages[kMSBDWinKeyCount] = { kMSBDCSHIDLeft, kMSBDCSHIDRight, kMSBDCSHIDUp, kMSBDCSHIDDown, 0x09, 0x06, 0x15 };
    static NSString *const keys[kMSBDWinKeyCount] = { @"", @"", @"", @"", @"f", @"c", @"r" };
    int k = kMSBDWinKeyRows[row].key;
    return MSBDCSShortcutText(usages[k], keys[k], kMSBDWinKeyRows[row].mods);
}
static NSString *MSKCTapKeys(BOOL volume, BOOL backlight) { return volume && backlight ? @"volume and backlight" : volume ? @"volume" : @"backlight"; }
// The footers' sentences about keys two features claim, for each group: 0 the Mac keys, 1 Window Tiling Shortcuts, 2 Custom Shortcuts.
static NSString *MSKCFooterLines(int group) {
    MSBDKCYoursSet *y = (MSBDKCYoursSet *)calloc(1, sizeof(MSBDKCYoursSet));
    if (!y) return @"";
    MSCSYoursNow(y);
    NSMutableArray *out = [NSMutableArray array];
    BOOL volume = MSKeyOn(@"com.besiktasliseba.volumeglobetweak", @"enabled"), backlight = MSKeyOn(@"com.besiktasliseba.brightnesskeytweak", @"backlightKeysEnabled");
    BOOL tiling = MSKCWindowKeysOn();
    if (group == 0) {
        unsigned taps = MSBDKCYoursTaps(y);
        BOOL v = volume && (taps & (1u << kMSBDKCVolume)), b = backlight && (taps & (1u << kMSBDKCBacklight));
        if (v || b) [out addObject:[NSString stringWithFormat:@"Some of your own shortcuts start with the %@ keys, so those keys act only when pressed and let go alone.", MSKCTapKeys(v, b)]];
        long tl = MSKCTopLeftUsage();
        if (tl && MSKeyOn(@"com.besiktasliseba.graveescapetweak", @"enabled")) {
            NSMutableArray *mine = [NSMutableArray array];
            for (unsigned i = 0; i < y->n; i++) {
                int t = MSBDKCTopLeftIndex(y->mods[i]);
                if (y->usage[i] == tl && t >= 0 && MSBDKCYoursRuleStatic(y, i)) [mine addObject:MSKCYoursText(y, i)];   // (as the state: KeyboardChords.h)
            }
            if (mine.count) [out addObject:[NSString stringWithFormat:@"The key left of 1 stays itself in your own shortcut%@ %@.", mine.count == 1 ? @"" : @"s", MSKCList(mine)]];
        }
        uint64_t st = MSBDKCYoursState(y);
        if ((st & kMSBDKCYoursTab) && MSKeyOn(@"com.besiktasliseba.tabmutetweak", @"enabled")) [out addObject:@"Tab is one of your own shortcuts, so it does not mute."];
        if ((st & (kMSBDKCYoursScreenUp | kMSBDKCYoursScreenDown)) && MSKeyOn(@"com.besiktasliseba.brightnesskeytweak", @"screenKeysEnabled"))
            [out addObject:@"Shift + = or - is one of your own shortcuts, so it does not change the brightness."];
    } else if (group == 1 && tiling) {
        if ((volume || backlight) && MSKCWindowKeysOffered())   // (as the taps: only while its keys can act)
            [out addObject:[NSString stringWithFormat:@"Window Tiling's Globe-Control keys start with the %@ keys, so those act only when pressed and let go alone.", MSKCTapKeys(volume, backlight)]];
        NSMutableArray *rows = [NSMutableArray array];
        for (int r = 0; r < (int)kMSBDWinKeyRowCount; r++) if (MSBDKCYoursTakesWinRow(y, r)) [rows addObject:MSKCWinRowText(r)];
        if (rows.count) [out addObject:[NSString stringWithFormat:@"Your own shortcuts take %@ instead.", MSKCList(rows)]];
    } else if (group == 2) {
        [out addObject:@"A shortcut of yours wins over a built-in one with the same keys, which is then off for those keys."];
        if (MSKCMacSwitcherOn()) {
            NSMutableArray *mine = [NSMutableArray array];
            static const long arrows[3] = { kMSBDCSHIDLeft, kMSBDCSHIDRight, kMSBDCSHIDUp };
            for (int i = 0; i < 3; i++) if (MSBDKCYoursTakes(y, arrows[i], kMSBDModControl)) [mine addObject:MSBDCSShortcutText(arrows[i], @"", kMSBDModControl)];
            if (mine.count) [out addObject:[NSString stringWithFormat:@"Yours take %@ from the Mac Switcher.", MSKCList(mine)]];
        }
    }
    free(y);
    return [out componentsJoinedByString:@" "];
}
static NSString *MSKCAppend(NSString *base, NSString *more) { return more.length ? [base stringByAppendingFormat:@" %@", more] : base; }
// What a shortcut being recorded shares with a built-in one that is on, as the recorder says it (CustomShortcuts.x), or nil. Yours wins on a
// key shortcut; a tap it starts with then acts only alone.
NSString *MSKeysBuiltinNote(long usage, NSString *key, unsigned long long mods) {
    NSString *keys = MSBDCSShortcutText(usage, key, mods);
    NSMutableArray *out = [NSMutableArray array];
    int row = -1, owner = MSBDKCKeyOwner(usage, key.UTF8String, mods, MSKCTopLeftUsage(), &row);
    if (owner == kMSBDKCWindowTiling && MSKCWindowKeysOn() && row >= 0)
        [out addObject:[NSString stringWithFormat:@"%@ is also Window Tiling's %s. Your shortcut takes its place.", keys, kMSBDWinKeyRows[row].act.title]];
    else if (owner == kMSBDKCMacSwitcher && MSKCMacSwitcherOn())
        [out addObject:[NSString stringWithFormat:usage == kMSBDCSHIDUp ? @"%@ also opens the Mac Switcher. Your shortcut takes its place." : @"%@ also switches desktops in the Mac Switcher. Your shortcut takes its place.", keys]];
    else if (owner == kMSBDKCTopLeftEscape && MSKeyOn(@"com.besiktasliseba.graveescapetweak", @"enabled"))
        [out addObject:[NSString stringWithFormat:@"%@ is Escape while Top-Left Key as Escape is on. Your shortcut keeps the key as it is.", keys]];
    unsigned taps = MSBDKCTapsIn(mods);
    BOOL v = (taps & (1u << kMSBDKCVolume)) && MSKeyOn(@"com.besiktasliseba.volumeglobetweak", @"enabled");
    BOOL b = (taps & (1u << kMSBDKCBacklight)) && MSKeyOn(@"com.besiktasliseba.brightnesskeytweak", @"backlightKeysEnabled");
    if (v || b) [out addObject:[NSString stringWithFormat:@"It starts with the %@ keys, which then act only when pressed and let go alone.", MSKCTapKeys(v, b)]];
    return out.count ? [out componentsJoinedByString:@" "] : nil;
}
// What the footers say about shared keys now, on every group (the page is built again when it changes: MSKeyboardListController).
static NSString *MSKCSignature(void) {
    return [NSString stringWithFormat:@"%@|%@|%@|%d", MSKCFooterLines(0), MSKCFooterLines(1), MSKCFooterLines(2), MSKCWindowKeysOn()];
}
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

// ---- Window Tiling Keys and Custom Shortcuts (1.8.3) ----
// The KeyPilot row's cell: its name, "by wanghuangjie" under it, and an App Store-style button where the checkmark would be -- GET (its page) while it
// is not installed, OPEN (its app) once it is (common/ChoicePage.h MSBDKeyPilotRow). Settings makes the cell from the row's "cellClass": a cell class
// of ours under Apple's PSTableCell, made by name at run time (Settings has the class; this library does not link it), on our page and on Apple's.
static void MSKPLog(NSString *line) {   // (debug builds: the macsettings log, as AppleGroups18.x's)
#if DEBUG
    if (access("/tmp/macsettings-debug", F_OK) != 0) return;
    FILE *f = fopen("/tmp/macsettings.log", "a");
    if (f) { fprintf(f, "[keypilot] %s\n", line.UTF8String); fclose(f); }
#endif
}
// Its app registered with the system (LSApplicationProxy's installed: a placeholder proxy for an unknown identifier says NO).
static BOOL MSKeyPilotAppRegistered(void) {
    Class c = objc_getClass("LSApplicationProxy");
    SEL make = NSSelectorFromString(@"applicationProxyForIdentifier:");
    id proxy = [(id)c respondsToSelector:make] ? ((id (*)(id, SEL, id))objc_msgSend)((id)c, make, kMSBDKeyPilotApp) : nil;
    id installed = nil;
    @try { installed = [proxy valueForKey:@"installed"]; } @catch (NSException *e) {}
    return [installed respondsToSelector:@selector(boolValue)] && [installed boolValue];
}
#if DEBUG
// (debug, a device check of OPEN without KeyPilot: /tmp/msb-kp-testapp names an app the row stands for -- installed, and OPEN opens it as it
//  would KeyPilot's; /tmp/msb-kp-forcefallback leaves Settings' own open out, so SpringBoard's is the one. Read only, here and in SpringBoard)
static NSString *MSKPTestApp(void) {
    NSString *s = [NSString stringWithContentsOfFile:@"/tmp/msb-kp-testapp" encoding:NSUTF8StringEncoding error:nil];
    s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return s.length ? s : nil;
}
#endif
// Installed: its app registered -- OPEN opens the app, so with no app there is nothing to open: GET (review 1.8.3 P2-8; its tweak file alone, or
// iCleaner's .disabled one left after a removal, showed OPEN and opened nothing).
static BOOL MSKeyPilotInstalled(void) {
#if DEBUG
    if (MSKPTestApp()) return YES;
#endif
    return MSKeyPilotAppRegistered();
}
BOOL MSKeyPilotIsInstalled(void) { return MSKeyPilotInstalled(); }   // (CustomShortcuts.x: ours wait and its shortcuts can be imported)
// GET: its page. OPEN: its app, by bundle ID, off the main queue as the Folder menu opens an app (FolderMenu.x), the answer taken -- Settings may not
// be let open an app (review 1.8.3 F4: only SpringBoard's use was proven): then SpringBoard opens it, which can (kMSBDKeyPilotOpenNote).
static void MSKeyPilotAct(NSDictionary *row) {
    if ([row[@"app"] isKindOfClass:[NSString class]]) {
        NSString *app = row[@"app"];
        BOOL skipOwn = NO;
#if DEBUG
        if (MSKPTestApp()) app = MSKPTestApp();
        skipOwn = access("/tmp/msb-kp-forcefallback", F_OK) == 0;
#endif
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            id ws = ((id (*)(id, SEL))objc_msgSend)(objc_getClass("LSApplicationWorkspace"), NSSelectorFromString(@"defaultWorkspace"));
            SEL open = NSSelectorFromString(@"openApplicationWithBundleID:");
            BOOL ok = !skipOwn && [ws respondsToSelector:open] && ((BOOL (*)(id, SEL, id))objc_msgSend)(ws, open, app);
            if (!ok) notify_post(kMSBDKeyPilotOpenNote);
            MSKPLog([NSString stringWithFormat:@"OPEN %@: Settings opened it %d%@", app, ok, ok ? @"" : @" -- SpringBoard asked to open it"]);
        });
    } else if ([row[@"url"] isKindOfClass:[NSString class]]) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:row[@"url"]] options:@{} completionHandler:nil];
        MSKPLog([NSString stringWithFormat:@"GET: %@", row[@"url"]]);
    }
}
// (no init of ours -- an init made with the runtime under ARC would get ownership wrong --: the cell as Settings makes it, its name and our second line
//  laid out in it by -layoutSubviews, its contents by Settings' own -refreshCellContentsWithSpecifier:)
#define kMSKPSubtitleTag 0x6b70   // ("kp": our second line, "by wanghuangjie")
// (the row follows an install or a removal while Settings stays open -- KeyPilot installed from Sileo, then back here, or its page opened from GET:
//  each time Settings comes to the front again the cell reads it again, on our page and on Apple's 18 page alike; review 1.8.3 F9. The watch goes
//  with the cell: its observer is removed as the cell lets the watch go)
@interface MSKPActiveWatch : NSObject
@property (nonatomic, strong) id token;
@end
@implementation MSKPActiveWatch
- (void)dealloc { if (_token) [[NSNotificationCenter defaultCenter] removeObserver:_token]; }
@end
static const void *kMSKPWatchKey = &kMSKPWatchKey, *kMSKPShownKey = &kMSKPShownKey;
static void MSKPCellApply(UITableViewCell *cell);
static void MSKPCellRefresh(id self, SEL _cmd, id spec) {
    struct objc_super sup = { self, objc_getClass("PSTableCell") };
    ((void (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&sup, _cmd, spec);
    UITableViewCell *cell = self;
    MSKPCellApply(cell);
    if (!objc_getAssociatedObject(cell, kMSKPWatchKey)) {
        MSKPActiveWatch *w = [MSKPActiveWatch new];
        __weak UITableViewCell *weakCell = cell;
        w.token = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
            UITableViewCell *c = weakCell;
            if (c && [objc_getAssociatedObject(c, kMSKPShownKey) boolValue] != MSKeyPilotInstalled()) { MSKPLog(@"installed or removed meanwhile: the row follows"); MSKPCellApply(c); }
        }];
        objc_setAssociatedObject(cell, kMSKPWatchKey, w, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
static void MSKPCellApply(UITableViewCell *cell) {
    BOOL installed = MSKeyPilotInstalled();
    objc_setAssociatedObject(cell, kMSKPShownKey, @(installed), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSDictionary *row = MSBDKeyPilotRow(installed);
    cell.textLabel.text = row[@"title"];
    cell.textLabel.textColor = [UIColor labelColor];
    cell.userInteractionEnabled = YES;
    if ([cell respondsToSelector:NSSelectorFromString(@"setCellEnabled:")]) ((void (*)(id, SEL, BOOL))objc_msgSend)(cell, NSSelectorFromString(@"setCellEnabled:"), YES);
    UILabel *sub = (UILabel *)[cell.contentView viewWithTag:kMSKPSubtitleTag];
    if (![sub isKindOfClass:[UILabel class]]) {
        sub = [UILabel new];
        sub.tag = kMSKPSubtitleTag;
        sub.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        sub.adjustsFontForContentSizeCategory = YES;
        sub.textColor = [UIColor secondaryLabelColor];
        [cell.contentView addSubview:sub];
    }
    sub.text = row[@"subtitle"];
    cell.accessibilityValue = row[@"subtitle"];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];   // (the choice pages' GET button: MSBRootListController.m)
    [b setTitle:row[@"button"] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightBold];
    [b setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
    b.backgroundColor = [UIColor tertiarySystemFillColor];
    b.frame = CGRectMake(0, 0, 74.0, 28.0);
    b.layer.cornerRadius = 14.0;
    b.clipsToBounds = YES;
    b.accessibilityLabel = [NSString stringWithFormat:@"%@, KeyPilot", row[@"button"]];
    [b addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { MSKeyPilotAct(row); }] forControlEvents:UIControlEventTouchUpInside];
    cell.accessoryView = b;
    [cell setNeedsLayout];
}
static void MSKPCellLayout(id self, SEL _cmd) {
    struct objc_super sup = { self, objc_getClass("PSTableCell") };
    ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, _cmd);
    UITableViewCell *cell = self;
    UILabel *sub = (UILabel *)[cell.contentView viewWithTag:kMSKPSubtitleTag];
    UILabel *title = cell.textLabel;
    if (![sub isKindOfClass:[UILabel class]] || !title) return;
    // (the name and, under it, the developer, as a subtitle cell lays them out: the two lines centred together, the name's left edge for both)
    CGSize ts = [title sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)], ss = [sub sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
    CGFloat x = title.frame.origin.x, w = MAX(0.0, cell.contentView.bounds.size.width - x - 8.0), top = (cell.contentView.bounds.size.height - ts.height - ss.height - 2.0) / 2.0;
    title.frame = CGRectMake(x, top, w, ts.height);
    sub.frame = CGRectMake(x, top + ts.height + 2.0, w, ss.height);
}
static Class MSKeyPilotCellClass(void) {
    Class have = objc_getClass("MSKeyPilotCell");
    if (have) return have;
    Class base = objc_getClass("PSTableCell");
    SEL refresh = NSSelectorFromString(@"refreshCellContentsWithSpecifier:");
    Method mr = base ? class_getInstanceMethod(base, refresh) : NULL;
    if (!mr || strcmp(method_getTypeEncoding(mr) ?: "", "v24@0:8@16")) return Nil;   // (Settings' cell is not as read: the row stays a plain one, named, with no button)
    Class c = objc_allocateClassPair(base, "MSKeyPilotCell", 0);
    if (!c) return objc_getClass("MSKeyPilotCell");
    class_addMethod(c, refresh, (IMP)MSKPCellRefresh, method_getTypeEncoding(mr));
    class_addMethod(c, @selector(layoutSubviews), (IMP)MSKPCellLayout, "v16@0:8");
    objc_registerClassPair(c);
    return c;
}
PSSpecifier *MSCustomShortcutsRowSpecifier(void);   // (CustomShortcuts.x: the row to the Custom Shortcuts page)
// KeyPilot's own row (OPEN): shown only while it is installed (ours wait then: CustomShortcuts.x).
static PSSpecifier *MSKeyPilotRowSpecifier(id target) {
    // (a title-value row: a static text row is drawn disabled -- its name grey -- and takes no touch, so its button did nothing: iPad 2, 16.7.7)
    PSSpecifier *kp = [PSSpecifier preferenceSpecifierNamed:@"KeyPilot" target:target set:nil get:nil detail:nil cell:kCellTitleValue edit:nil];
    [kp setProperty:@YES forKey:@"enabled"];
    [kp setIdentifier:@"MAC_KEYPILOT"];
    Class cell = MSKeyPilotCellClass();
    if (cell) [kp setProperty:cell forKey:@"cellClass"];
    [kp setProperty:@58.0 forKey:@"height"];   // (two lines: its name and its developer)
    return kp;
}
// Keys of your own first: KeyPilot's own row while it is installed, the more complete of the two, then Custom Shortcuts (1.8.5, based on KeyPilot);
// below them Window Tiling Keys (the Mac's own Globe-Control shortcuts: statusbar/WindowKeysRule.h). (KT 12 Nov; until then these came after the
// Mac keys and Apple's rows, Window Tiling first, KeyPilot last.)
NSArray *MSKeysShortcutSpecifiers(id target) {
    NSMutableArray *s = [NSMutableArray array];
    BOOL kpInstalled = MSKeyPilotInstalled();
    PSSpecifier *cg = MSKeyGroup(nil, MSKCAppend(kpInstalled ? @"Make your own keyboard shortcuts for apps, URLs, window layouts and Home. While KeyPilot is installed, its shortcuts work and Custom Shortcuts waits."
                                                             : @"Make your own keyboard shortcuts for apps, URLs, window layouts and Home.", MSKCFooterLines(2)));
    [cg setIdentifier:@"MAC_CUSTOM_SHORTCUTS_GROUP"];
    [s addObject:cg];
    if (kpInstalled) [s addObject:MSKeyPilotRowSpecifier(target)];
    [s addObject:MSCustomShortcutsRowSpecifier()];
    PSSpecifier *g = MSKeyGroup(nil, MSKCAppend(@"Tile the front window as on a Mac: Globe-Control and an arrow key for half the screen, F to fill it, C to center it, R for its size before. Add Shift to arrange it with the window behind it, or Option-Shift for three windows.", MSKCFooterLines(1)));
    [g setIdentifier:@"MAC_WINDOW_KEYS_GROUP"];
    [s addObject:g];
    PSSpecifier *keys = MSKeySwitchDefault(target, @"Window Tiling Shortcuts", @kMSBDWindowKeysDomain, @kMSBDWindowKeysKey, YES);   // (on unless switched off: 1.8.7)
    [keys setIdentifier:@"MAC_WINDOW_KEYS"];
    [s addObject:keys];
    return s;
}
@implementation MSKeyboardListController {
    NSMutableArray *_msNativePages;   // Apple's Hardware Keyboard page (never shown), whose rows are on this page
    NSString *_msShared;              // what the footers said about keys two features claim (MSKCSignature)
    BOOL _msSharedPending;
}
- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        // Apple's own Hardware Keyboard settings, live (see common/NativeEmbed.h): layouts, Auto-Capitalization, "." Shortcut, Keyboard
        // Brightness, Modifier Keys, Keyboard Type. They start with their own group.
        _msNativePages = [NSMutableArray array];
        NSArray *hw = MSNESpecifiers(self, @"TIHardwareKeyboardController", @[@"/System/Library/PreferenceBundles/KeyboardSettings.bundle"], @"Hardware Keyboard", _msNativePages, nil);
        // (KT 12 Nov: your own shortcuts -- KeyPilot first -- and Window Tiling at the top, then the Mac keys, Apple's rows at the page's end)
        NSMutableArray *s = [NSMutableArray arrayWithArray:MSKeysShortcutSpecifiers(self)];
        [s addObjectsFromArray:MSKeysGroupSpecifiers(self, nil, hw, self)];
        if (hw.count) [s addObjectsFromArray:hw];
        _specifiers = s;
    }
    return _specifiers;
}
- (void)msOpenModifierKeys { MSKeysOpenModifierKeysOn(self); }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Keyboard";
    // (1.8.7: a switch on this page that changes which feature has some keys -- Window Tiling Shortcuts on, the volume keys on -- says so in the
    //  footers at once: looked at once the switch has finished moving, 0.4 s, and the page built again only when what they say changed)
    __weak typeof(self) weakSelf = self;
    for (NSString *n in @[@kMSBDWindowKeysChanged, @"com.besiktasliseba.volumeglobetweak/prefsChanged", @"com.besiktasliseba.brightnesskeytweak/prefsChanged",
                          @"com.besiktasliseba.graveescapetweak/prefsChanged", @"com.besiktasliseba.tabmutetweak/prefsChanged", @kMSBDCSChanged,
                          @kMSBDWindowKeysOfferedNote]) {   // (SpringBoard's offered state: Window Tiling's footer follows it)
        int t = 0;
        notify_register_dispatch(n.UTF8String, &t, dispatch_get_main_queue(), ^(int token) {
            typeof(self) me = weakSelf;
            if (!me) { notify_cancel(token); return; }
            [me msSharedMaybeChanged];
        });
    }
}
- (void)msSharedMaybeChanged {
    if (_msSharedPending) return;
    _msSharedPending = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        typeof(self) me = weakSelf;
        if (!me) return;
        me->_msSharedPending = NO;
        if (!me.viewIfLoaded.window) return;
        NSString *now = MSKCSignature();
        if ([now isEqualToString:me->_msShared]) return;
        me->_msShared = now;
        [me reloadSpecifiers];
    });
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _msShared = MSKCSignature();
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
    text = MSKCAppend(text, MSKCFooterLines(0));   // (keys these share with your own shortcuts: 1.8.7)
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
    // (a keyboard attached or detached before this list was watched: the row follows now, once -- as the Pointer row, PointerSettings.x)
    BOOL shown = MSBDMLIndexOf(MSBDMLIdentifiers(sidebar, [sidebar specifiers]), kKeyboardRowID, NO) != NSNotFound;
    if (sidebar && shown != MSKeyboardAttached()) dispatch_async(dispatch_get_main_queue(), ^{ PSListController *l = gSidebar; if (l) MSReloadSidebarKeepingScroll(l); });
    static int token = 0;
    if (token) return;
    notify_register_dispatch(MSBD_KEYBOARD_CHANGED, &token, dispatch_get_main_queue(), ^(int t) {
        PSListController *l = gSidebar;
        if (!l) return;
        BOOL shown = MSBDMLIndexOf(MSBDMLIdentifiers(l, [l specifiers]), kKeyboardRowID, NO) != NSNotFound;
        if (shown != MSKeyboardAttached()) MSReloadSidebarKeepingScroll(l);
    });
}
