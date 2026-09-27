// DockMagnificationSettings — a "Dock" row in Settings' own main list, right above Accessibility, so it
// looks like a built-in setting instead of hiding in the Tweaks folder.
//
// Loaded only into the Settings app. The usual PreferenceLoader entry would be moved into the Tweaks folder by
// Shuffle (it rebuilds the whole main list), so the row is added here instead, AFTER the list has been built:
// whenever the main list appears or reloads, insert our row in front of Accessibility unless it is already there.
// The page itself is the DockMagnificationPrefs bundle; it is loaded here so its class exists when the row is tapped.
//
// The list's own row identifiers (found by dumping it on the device): ... HOME_SCREEN_DOCK, ACCESSIBILITY, Wallpaper ...

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#import "../../common/LineSwitch.h"
#import "../../common/MacDockActive.h"
#pragma clang diagnostic pop
#import "../../common/NativeEmbed.h"
#import "../../common/OtherTweaks.h"

#define kRowID       @"DOCK_MAGNIFICATION"
#define kAnchorID    @"ACCESSIBILITY"
#define kStatusBarRowID @"MAC_STATUS_BAR"
#define kBundlePath  @"/var/jb/Library/PreferenceBundles/DockMagnificationPrefs.bundle"
#define kPSLinkListCell 2
#define kPSLinkCell  1

@interface PSSpecifier : NSObject
+ (instancetype)preferenceSpecifierNamed:(NSString *)name target:(id)target set:(SEL)set get:(SEL)get detail:(Class)detail cell:(long long)cell edit:(Class)edit;
+ (instancetype)groupSpecifierWithID:(NSString *)identifier;
- (id)propertyForKey:(NSString *)key;
- (void)setProperty:(id)value forKey:(NSString *)key;
@property (nonatomic, retain) NSString *identifier;
@property (nonatomic, retain) NSString *name;
@end

@interface PSListController : UIViewController
- (NSArray *)specifiers;
- (void)reloadSpecifierID:(NSString *)identifier;
- (void)insertSpecifier:(PSSpecifier *)specifier atIndex:(NSInteger)index animated:(BOOL)animated;
- (void)removeSpecifier:(PSSpecifier *)specifier animated:(BOOL)animated;
@end

static NSBundle *PrefsBundle(void) {
    static NSBundle *bundle = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        bundle = [NSBundle bundleWithPath:kBundlePath];
        [bundle load];
    });
    return bundle;
}

// Where our rows go: right below General, in General's own block -- General, Status Bar, Dock, Control Center. Found by the rows' identifiers
// (ControlCenter, General), never by a fixed index, since other tweaks (Shuffle, PreferenceLoader) change the list. The Dock row goes right after the
// Status Bar row when that is already there (both rows insert themselves, in whichever order); without Control Center and General, before Accessibility.
// No known row found (an iPadOS whose main list we have not seen: iPadOS 17 tester, 2026-09-26, got no rows at all, so not even Enable Anyway):
// the rows go near the top instead -- the start of the list's second block, below the Apple account -- so they always show, on any version.
static NSInteger TopIndex(NSArray *specs) {
    SEL cellType = NSSelectorFromString(@"cellType");
    for (NSUInteger i = 1; i < specs.count; i++)
        if ([specs[i] respondsToSelector:cellType] && ((long long (*)(id, SEL))objc_msgSend)(specs[i], cellType) == 0) return (NSInteger)i + 1;   // (0: PSGroupCell)
    return specs.count ? 1 : 0;
}
static NSInteger AnchorIndex(NSArray *specs, NSString *before, NSString *after) {
    NSInteger cc = NSNotFound, general = NSNotFound, accessibility = NSNotFound, own = NSNotFound;
    for (NSUInteger i = 0; i < specs.count; i++) {
        NSString *ident = [specs[i] identifier];
        if (![ident isKindOfClass:[NSString class]]) continue;
        if (before && [ident isEqualToString:before]) own = (NSInteger)i;
        if (after && [ident isEqualToString:after]) own = (NSInteger)i + 1;
        if (cc == NSNotFound && [ident caseInsensitiveCompare:@"ControlCenter"] == NSOrderedSame) cc = (NSInteger)i;
        if (general == NSNotFound && [ident caseInsensitiveCompare:@"General"] == NSOrderedSame) general = (NSInteger)i + 1;
        if (accessibility == NSNotFound && [ident caseInsensitiveCompare:kAnchorID] == NSOrderedSame) accessibility = (NSInteger)i;
    }
    if (own != NSNotFound) return own;
    if (cc != NSNotFound) return cc;
    if (general != NSNotFound) return general;
    return accessibility;
}


// Like Bluetooth's "On", the row shows whether its line (MacDock in Choicy / iCleaner Pro, the switch at the top of its page) is on -- redrawn when
// the switch or Choicy changes it (2026-09-25).
@interface DMDockRowValue : NSObject
@end
@implementation DMDockRowValue
- (id)msbdLineValue:(id)specifier { return MSBDLineRuns(@"MacDock") ? @"On" : @"Off"; }
@end
static DMDockRowValue *gRowValue;
static __weak PSListController *gRowList;
static void RefreshRowValue(void) {
    PSListController *l = gRowList;
    SEL r = NSSelectorFromString(@"reloadSpecifierID:");
    if (!l || ![l respondsToSelector:r]) return;
    for (PSSpecifier *sp in [l specifiers]) if ([[sp identifier] isEqualToString:kRowID]) { ((void (*)(id, SEL, id))objc_msgSend)(l, r, kRowID); break; }
}
static void WatchRowValue(PSListController *list) {
    gRowList = list;
    static int t1 = 0, t2 = 0, t3 = 0;
    if (t1) return;
    void (^h)(int) = ^(int t) {
        RefreshRowValue();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ RefreshRowValue(); });   // (iCleaner Pro: the helper renames a moment later)
    };
    notify_register_dispatch("com.opa334.choicyprefs/ReloadPrefs", &t1, dispatch_get_main_queue(), h);
    notify_register_dispatch("com.besiktasliseba.lines.apply", &t2, dispatch_get_main_queue(), h);
    notify_register_dispatch(MSBD_UNTESTED_CHANGED, &t3, dispatch_get_main_queue(), h);   // ("Enable Anyway", "Turn Back On")
}

static void InsertRow(PSListController *list) {
    NSArray *specs = [list specifiers];
    WatchRowValue(list);
    for (NSUInteger i = 0; i < specs.count; i++) if ([[specs[i] identifier] isEqualToString:kRowID]) return;   // already there
    NSInteger anchor = AnchorIndex(specs, nil, kStatusBarRowID);
    BOOL newOS = [NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 17;   // (15/16: exactly as before)
    if (anchor == NSNotFound && newOS) anchor = TopIndex(specs);   // (only ever the main list: this runs from PSUIPrefsListController alone)
    Class detail = PrefsBundle() ? NSClassFromString(@"DMRootListController") : Nil;   // the class only exists once the bundle is loaded
    if (anchor == NSNotFound || !PrefsBundle() || !detail) return;         // not the main list, or the page is missing

    if (!gRowValue) gRowValue = [DMDockRowValue new];
    PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:@"Dock" target:gRowValue set:NULL get:@selector(msbdLineValue:)
                                                      detail:detail cell:kPSLinkListCell edit:nil];
    row.identifier = kRowID;
    [row setProperty:kRowID forKey:@"id"];
    [row setProperty:@YES forKey:@"hasSelectionStyle"];
    UIImage *icon = [UIImage imageNamed:@"icon" inBundle:PrefsBundle() compatibleWithTraitCollection:nil];
    if (icon) [row setProperty:icon forKey:@"iconImage"];
    [list insertSpecifier:row atIndex:anchor animated:NO];
    if (newOS) {   // (the same page listed with the other tweaks by the postinst on 17+: hidden while our own row is there -- found by its id, or by our
        // bundle as it was listed before it had one; never another tweak's entry of the same name)
        for (PSSpecifier *sp in [[list specifiers] copy]) {
            if ([[sp identifier] isEqualToString:kRowID]) continue;
            BOOL ours = [[sp identifier] isEqualToString:@"MSBD_PL_DockMagnificationPrefs"];
            if (!ours && [[sp name] isEqualToString:@"Dock"]) { id b = [sp propertyForKey:@"bundle"] ?: [sp propertyForKey:@"lazy-bundle"]; ours = [b isKindOfClass:[NSString class]] && [(NSString *)b containsString:@"DockMagnificationPrefs"]; }
            if (ours) [list removeSpecifier:sp animated:NO];
        }
    }
}

// ===== Home Screen & Dock, while MacDock is active (2026-09-25) ===================================================================================
// Apple's page keeps its Home Screen options; its two Dock switches ("Show App Library in Dock", "Show Suggested and Recent Apps in Dock") move to
// our Dock page (Apple's own App Library switch, live, and our Number of Recent Apps, which keeps Apple's recents switch in step), and the page and
// its sidebar row are called "Home Screen" (iPadOS 15: "Home Screen & Dock"; iPadOS 16's "Home Screen & Multitasking" keeps its name). MacDock off:
// Apple's page exactly as it is.
static NSArray *DMHomeScreenHidden(UIViewController *list) {
    if (![NSStringFromClass([list class]) isEqualToString:@"DBSHomeScreenPadListController"] || !MSBDMacDockActive()) return nil;
    return @[@"SHOW_APP_LIBRARY", @"ALLOW_RECENTS", @"MULTITASKING_DOCK"];   // (the rows first, then their group)
}
static void DMRenameHomeScreenRow(PSListController *list) {
    if (!MSBDMacDockActive()) return;
    for (PSSpecifier *sp in [list specifiers]) {
        if (![[sp identifier] isEqualToString:@"HOME_SCREEN_DOCK"]) continue;
        NSString *name = [sp valueForKey:@"name"];
        if (![name isKindOfClass:[NSString class]] || ![name hasSuffix:@" & Dock"]) return;   // (iPadOS 16's name has no Dock in it)
        [sp setValue:[name substringToIndex:name.length - 7] forKey:@"name"];
        SEL r = NSSelectorFromString(@"reloadSpecifier:");
        if ([list respondsToSelector:r]) ((void (*)(id, SEL, id))objc_msgSend)(list, r, sp);
        return;
    }
}
%hook PSListController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    NSArray *h = DMHomeScreenHidden((UIViewController *)self);
    if (h.count) {
        MSNEHideRows((UIViewController *)self, h);
        NSString *t = self.title;
        if ([t hasSuffix:@" & Dock"]) self.title = [t substringToIndex:t.length - 7];
    }
}
- (void)reloadSpecifiers {
    %orig;
    NSArray *h = DMHomeScreenHidden((UIViewController *)self);
    if (h.count) MSNEHideRows((UIViewController *)self, h);
}
%end

static void DMRowURLLog(NSString *line) {
#if DEBUG
    FILE *f = fopen("/tmp/msbd-settings.log", "a");
    if (f) { fprintf(f, "[dockrow] %s\n", line.UTF8String); fclose(f); }
#else
    (void)line;
#endif
}
%hook PSUIPrefsListController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    InsertRow((PSListController *)self);
    DMRenameHomeScreenRow((PSListController *)self);
}
// A link into our page (prefs:root=DOCK_MAGNIFICATION[&path=...], e.g. "Downloads From..." in the Dock's Downloads panel): when Settings is started
// by the link itself, the link looks for our row before the list has first appeared, so before the row is in it -- and landed on General. The
// row is put in the moment it is asked for.
- (id)specifierForID:(NSString *)identifier {
    static BOOL inserting = NO;
    id r = %orig;
    if (!r && !inserting && [identifier isEqualToString:kRowID]) {   // (asked for our row before it was put in: put it in now)
        inserting = YES;
        InsertRow((PSListController *)self);
        inserting = NO;
        r = %orig;
        DMRowURLLog([NSString stringWithFormat:@"specifierForID: %@ was missing -> %@", identifier, r ? @"put in" : @"still missing"]);
    }
    return r;
}
- (void)reloadSpecifiers {
    %orig;
    InsertRow((PSListController *)self);
    DMRenameHomeScreenRow((PSListController *)self);
}
%end

// ===== Our Home Screen switches on Apple's Home Screen page (2026-09-25) ==========================================================================
// Apple's page (Home Screen & Dock on iPadOS 15, called "Home Screen" while MacDock is active; Home Screen & Multitasking on iPadOS 16) gets one
// group of our switches, right after Apple's own Home Screen section (Use Large App Icons), before Newly Downloaded Apps -- whether MacDock is
// active or not. Each row is there only while the part that does the work runs:
//   Swipe Up Does Not Open App Library, Swipe Down Opens App Library   the Dock part (MacDock line, SpringBoard)       applied at once
//   Show Page Dots, Show App Names                                     MacPageDots / MacIconLabels (MacStatusBar line)  after a respring
// The stored keys are the ones the parts read (unchanged): page dots and app names store "hidden" (key enabled), so their rows show the opposite.
// The rows are put into Apple's list at the moment the page hands out a new list (its -specifiers), before any table sees it, found by the rows'
// identifiers, never by a fixed index; a list that is not mutable, or has them already, is left alone. They read and write through their own small
// target object, so nothing of Apple's page controller is called.
#define kHSGroupID @"MSBD_HOME_SCREEN_GROUP"
#define kPSGroupCell 0
#define kPSSwitchCell 6

@interface DMHomeScreenRows : NSObject
@end
@implementation DMHomeScreenRows
static BOOL DMHSStored(PSSpecifier *sp) {
    NSString *domain = [sp propertyForKey:@"defaults"], *key = [sp propertyForKey:@"key"];
    if (![domain isKindOfClass:[NSString class]] || ![key isKindOfClass:[NSString class]]) return NO;
    BOOL value = [[sp propertyForKey:@"default"] boolValue];
    CFPreferencesSynchronize((__bridge CFStringRef)domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPropertyListRef v = CFPreferencesCopyValue((__bridge CFStringRef)key, (__bridge CFStringRef)domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (v) {   // (a 0/1 number too, as an earlier Settings build stored it and the parts accept it: PageDots.x, IconLabels.x)
        if (CFGetTypeID(v) == CFBooleanGetTypeID()) value = CFBooleanGetValue(v);
        else if (CFGetTypeID(v) == CFNumberGetTypeID()) { int n = 0; CFNumberGetValue((CFNumberRef)v, kCFNumberIntType, &n); value = n != 0; }
        CFRelease(v);
    }
    return value;
}
- (id)msbdHSValue:(PSSpecifier *)sp {
    BOOL stored = DMHSStored(sp);
    return @([[sp propertyForKey:@"msbInvert"] boolValue] ? !stored : stored);
}
- (void)msbdHSSet:(id)value specifier:(PSSpecifier *)sp {
    NSString *domain = [sp propertyForKey:@"defaults"], *key = [sp propertyForKey:@"key"], *note = [sp propertyForKey:@"PostNotification"];
    if (![domain isKindOfClass:[NSString class]] || ![key isKindOfClass:[NSString class]] || ![value respondsToSelector:@selector(boolValue)]) return;
    BOOL stored = [[sp propertyForKey:@"msbInvert"] boolValue] ? ![value boolValue] : [value boolValue];
    MSBDNoteSwitch(domain, key, [[sp propertyForKey:@"msbInvert"] boolValue] ? nil : [sp valueForKey:@"name"], DMHSStored(sp), stored);   // (crash guard: LineSwitch.h; an inverted row's title would say the opposite)
    CFPreferencesSetValue((__bridge CFStringRef)key, stored ? kCFBooleanTrue : kCFBooleanFalse, (__bridge CFStringRef)domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize((__bridge CFStringRef)domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if ([note isKindOfClass:[NSString class]]) notify_post(note.UTF8String);
}
@end
static DMHomeScreenRows *gHSTarget;

static PSSpecifier *DMHSSwitch(NSString *label, NSString *ident, NSString *domain, NSString *key, BOOL def, BOOL invert, NSString *note) {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:label target:gHSTarget set:@selector(msbdHSSet:specifier:) get:@selector(msbdHSValue:) detail:Nil cell:kPSSwitchCell edit:Nil];
    s.identifier = ident;
    [s setProperty:ident forKey:@"id"];
    [s setProperty:domain forKey:@"defaults"];
    [s setProperty:key forKey:@"key"];
    [s setProperty:@(def) forKey:@"default"];
    if (invert) [s setProperty:@YES forKey:@"msbInvert"];
    [s setProperty:note forKey:@"PostNotification"];
    return s;
}
static NSArray *DMHSSpecifiers(void) {
    BOOL dock = MSBDMacDockActive(), bar = MSBDMacStatusBarActive();
    if (!dock && !bar) return nil;
    Class specClass = NSClassFromString(@"PSSpecifier");
    if (!specClass || ![specClass respondsToSelector:@selector(groupSpecifierWithID:)]) return nil;
    if (!gHSTarget) gHSTarget = [DMHomeScreenRows new];
    NSMutableArray *out = [NSMutableArray array];
    PSSpecifier *g = [specClass groupSpecifierWithID:kHSGroupID];
    if (!g) return nil;
    NSMutableString *f = [NSMutableString string];
    if (dock) [f appendString:@"Swipe down opens the App Library while the status bar shows its Spotlight button, and Spotlight otherwise."];   // (Dock.x)
    if (bar) {   // (another tweak already hiding them: ours steps aside, OtherTweaks.h, so the switch would do nothing -- say who does it)
        [f appendString:f.length ? @" Page dots and app names change after a respring." : @"Page dots and app names change after a respring."];
        NSString *dots = MSBDOtherTweakDoing(kMSBDDupPageDots, NO), *names = MSBDOtherTweakDoing(kMSBDDupIconLabels, NO);
        if (dots) [f appendFormat:@" %@ is hiding the page dots.", dots];
        if (names) [f appendFormat:@" %@ is hiding the app names.", names];
    }
    if (f.length) [g setProperty:f forKey:@"footerText"];
    [out addObject:g];
    if (dock) {
        [out addObject:DMHSSwitch(@"Swipe Up Does Not Open App Library", @"MSBD_BLOCK_SWIPE_UP", @"com.besiktasliseba.dockmagnification", @"blockSwipeUpLibrary", YES, NO, @"com.besiktasliseba.dockmagnification/prefsChanged")];
        [out addObject:DMHSSwitch(@"Swipe Down Opens App Library", @"MSBD_SWIPE_DOWN_LIBRARY", @"com.besiktasliseba.macspotlightreplace", @"enabled", YES, NO, @"com.besiktasliseba.dockmagnification/prefsChanged")];
    }
    if (bar) {
        [out addObject:DMHSSwitch(@"Show Page Dots", @"MSBD_SHOW_PAGE_DOTS", @"com.besiktasliseba.macpagedots", @"enabled", NO, YES, @"com.besiktasliseba.macpagedots/prefsChanged")];
        [out addObject:DMHSSwitch(@"Show App Names", @"MSBD_SHOW_APP_NAMES", @"com.besiktasliseba.maciconlabels", @"enabled", NO, YES, @"com.besiktasliseba.maciconlabels/prefsChanged")];
    }
    return out;
}
static long long DMHSCellType(id sp) {
    SEL c = NSSelectorFromString(@"cellType");
    return [sp respondsToSelector:c] ? ((long long (*)(id, SEL))objc_msgSend)(sp, c) : -1;
}
// Where the group goes: in front of Newly Downloaded Apps; without it, in front of the group after Apple's Home Screen section; else at the end.
static NSUInteger DMHSIndex(NSArray *specs) {
    NSUInteger layout = NSNotFound;
    for (NSUInteger i = 0; i < specs.count; i++) {
        id ident = [specs[i] respondsToSelector:@selector(identifier)] ? [specs[i] identifier] : nil;
        if (![ident isKindOfClass:[NSString class]]) continue;
        if ([ident isEqualToString:@"APP_DOWNLOADS_GO_TO"]) return i;
        if ([ident isEqualToString:@"LARGE_ICON_LAYOUT_GROUP"]) layout = i;
    }
    if (layout != NSNotFound) for (NSUInteger i = layout + 1; i < specs.count; i++) if (DMHSCellType(specs[i]) == kPSGroupCell) return i;
    return specs.count;
}

%group HomeScreenRows
%hook DBSHomeScreenPadListController
- (NSMutableArray *)specifiers {
    NSMutableArray *specs = %orig;
    if (![specs isKindOfClass:[NSMutableArray class]]) return specs;
    static const void *kHSDoneKey = &kHSDoneKey;   // (a marker on the list itself: each new list gets the rows once)
    if (objc_getAssociatedObject(specs, kHSDoneKey)) return specs;
    objc_setAssociatedObject(specs, kHSDoneKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        for (id sp in specs) if ([[sp identifier] isEqual:kHSGroupID]) return specs;   // already there
        NSArray *rows = DMHSSpecifiers();
        if (rows.count > 1) [specs insertObjects:rows atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(DMHSIndex(specs), rows.count)]];
    } @catch (NSException *e) {}
    return specs;
}
%end
%end

// Apple's page class may come with a framework loaded later: the hook goes in as soon as the class exists (never inside the dyld callback itself).
static void DMHSTryInit(void) {
    static BOOL done; if (done) return;
    Class c = NSClassFromString(@"DBSHomeScreenPadListController");
    if (!c || ![c instancesRespondToSelector:@selector(specifiers)]) return;
    done = YES; %init(HomeScreenRows);
}
static void DMHSImageAdded(const struct mach_header *mh, intptr_t slide) {
    static BOOL queued; if (queued || !NSClassFromString(@"DBSHomeScreenPadListController")) return;
    queued = YES; dispatch_async(dispatch_get_main_queue(), ^{ DMHSTryInit(); });
}
%ctor {
    %init;
    DMHSTryInit();
    _dyld_register_func_for_add_image(DMHSImageAdded);
}
