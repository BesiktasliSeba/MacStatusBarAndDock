#import <unistd.h>
// Pointer (M1 pipeline C6, 2026-09-24): a "Pointer" row in the Settings sidebar, shown only while a trackpad or mouse is attached (like iPadOS's own
// trackpad settings), showing the Pointer Style and opening the one page for the pointer: Pointer Style (iPadOS = the stock round pointer, Mac = the
// Mac pointer drawn by MacPointer in pointeruid), Hide in Virtual Mac (Mac only) and Block Pointer Pull-Down, then Apple's own Pointer Control and
// Trackpad & Mouse settings, live (common/NativeEmbed.h). Our settings are stored in Mac Status Bar's own preferences (com.besiktasliseba.macstatusbar)
// and apply live: SpringBoard hands them to pointeruid.
// Whether a pointer device is attached comes from SpringBoard too (Darwin notification state com.besiktasliseba.macpointer.device, see Mac Status Bar's
// MacPointer bridge), because the Settings app has no clean way of its own to ask.
#import <UIKit/UIKit.h>
#import <notify.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "../common/NativeEmbed.h"

@interface PSSpecifier : NSObject
+ (instancetype)preferenceSpecifierNamed:(NSString *)name target:(id)target set:(SEL)set get:(SEL)get detail:(Class)detail cell:(long long)cell edit:(Class)edit;
+ (instancetype)groupSpecifierWithName:(NSString *)name;
- (NSString *)identifier;
- (void)setIdentifier:(NSString *)identifier;
- (void)setProperty:(id)value forKey:(NSString *)key;
- (void)setValues:(NSArray *)values titles:(NSArray *)titles shortTitles:(NSArray *)shortTitles;
@end
@interface PSListController : UIViewController { NSMutableArray *_specifiers; }
- (NSMutableArray *)specifiers;
- (void)reloadSpecifiers;
- (id)readPreferenceValue:(PSSpecifier *)specifier;
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
@end

#define MP_DOMAIN @"com.besiktasliseba.macstatusbar"
#define MP_NOTIFY @"com.besiktasliseba.macstatusbar/prefsChanged"
#define kPointerRowID @"MAC_POINTER"
enum { kCellGroup = 0, kCellLinkList = 2, kCellSwitch = 6, kCellSlider = 5 };

BOOL MSPointerDeviceAttached(void) {
#if DEBUG
    if (access("/tmp/msb-fakeptr", F_OK) == 0) return YES;   // (debug: test the Pointer page without a trackpad or mouse)
#endif
    static int token = 0;
    if (!token) notify_register_check("com.besiktasliseba.macpointer.device", &token);
    uint64_t v = 0; notify_get_state(token, &v);
    return v == 1;
}
// Pointer Style: "ipados" or "mac" (the default). Older versions stored "arrow" for Mac: it is read as Mac and rewritten as "mac" once, so the choice
// carries over (SpringBoard's bridge treats every value but "ipados" as the Mac pointer, old or new).
static NSString *MSPointerStyle(void) {
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("pointerStyle"), (__bridge CFStringRef)MP_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSString *s = (v && CFGetTypeID(v) == CFStringGetTypeID()) ? [(__bridge NSString *)v copy] : nil;
    if (v) CFRelease(v);
    if (s && ![s isEqualToString:@"ipados"] && ![s isEqualToString:@"mac"]) {
        CFPreferencesSetValue(CFSTR("pointerStyle"), CFSTR("mac"), (__bridge CFStringRef)MP_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesSynchronize((__bridge CFStringRef)MP_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    }
    return [s isEqualToString:@"ipados"] ? @"ipados" : @"mac";
}
// A 29 pt rounded square with the pointer glyph, like the icons of the other Settings rows.
static UIImage *MSPointerIcon(void) {
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(29, 29)];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[UIColor systemBlueColor] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 29, 29) cornerRadius:6.5] fill];
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
        UIImage *glyph = [[UIImage systemImageNamed:@"cursorarrow" withConfiguration:cfg] imageWithTintColor:[UIColor whiteColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
        if (glyph) [glyph drawInRect:CGRectMake((29 - glyph.size.width) / 2.0, (29 - glyph.size.height) / 2.0, glyph.size.width, glyph.size.height)];
    }];
}

@interface MSPointerListController : PSListController
@end
@implementation MSPointerListController {
    NSMutableArray *_msNativePages;   // Apple's Pointer Control and Trackpad pages (never shown), whose rows are on this page
}
- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *s = [NSMutableArray array];
        PSSpecifier *g = [PSSpecifier groupSpecifierWithName:nil];
        [s addObject:g];
        PSSpecifier *style = [PSSpecifier preferenceSpecifierNamed:@"Pointer Style" target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:)
                                                            detail:NSClassFromString(@"PSListItemsController") cell:kCellLinkList edit:nil];
        [style setProperty:@"pointerStyle" forKey:@"key"];
        [style setProperty:MP_DOMAIN forKey:@"defaults"];
        [style setProperty:@"mac" forKey:@"default"];
        [style setProperty:MP_NOTIFY forKey:@"PostNotification"];
        [style setValues:@[@"ipados", @"mac"] titles:@[@"iPadOS", @"Mac"] shortTitles:@[@"iPadOS", @"Mac"]];
        [s addObject:style];
        if ([MSPointerStyle() isEqualToString:@"mac"]) {   // (the Mac pointer's size is Apple's Pointer Size below: MacPointer follows it)
            PSSpecifier *gv = [PSSpecifier groupSpecifierWithName:nil];
            [gv setProperty:@"Virtual Mac draws its own pointer." forKey:@"footerText"];
            [s addObject:gv];
            PSSpecifier *vm = [PSSpecifier preferenceSpecifierNamed:@"Hide in Virtual Mac" target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:kCellSwitch edit:nil];
            [vm setProperty:@"macPointerHideInVirtualMac" forKey:@"key"];
            [vm setProperty:MP_DOMAIN forKey:@"defaults"];
            [vm setProperty:@YES forKey:@"default"];
            [vm setProperty:MP_NOTIFY forKey:@"PostNotification"];
            [s addObject:vm];
            // (off by default: the Mac pointer starts as the classic black-and-white arrow, whatever Pointer Control is set to)
            PSSpecifier *ga = [PSSpecifier groupSpecifierWithName:nil];
            [ga setProperty:@"Color, Border Width and Increase Contrast in Pointer Control below also change the Mac pointer. Off: the classic Mac pointer." forKey:@"footerText"];
            [s addObject:ga];
            PSSpecifier *ax = [PSSpecifier preferenceSpecifierNamed:@"Use Pointer Control Style" target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:kCellSwitch edit:nil];
            [ax setProperty:@"macPointerUseAXStyle" forKey:@"key"];
            [ax setProperty:MP_DOMAIN forKey:@"defaults"];
            [ax setProperty:@NO forKey:@"default"];
            [ax setProperty:MP_NOTIFY forKey:@"PostNotification"];
            [s addObject:ax];
        }
        PSSpecifier *gp = [PSSpecifier groupSpecifierWithName:nil];
        [gp setProperty:@"Stops the pointer at the top edge from pulling down the Lock Screen." forKey:@"footerText"];
        [s addObject:gp];
        PSSpecifier *pull = [PSSpecifier preferenceSpecifierNamed:@"Block Pointer Pull-Down" target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:kCellSwitch edit:nil];
        [pull setProperty:@"noTopEdgePull" forKey:@"key"];
        [pull setProperty:MP_DOMAIN forKey:@"defaults"];
        [pull setProperty:@YES forKey:@"default"];
        [pull setProperty:MP_NOTIFY forKey:@"PostNotification"];
        [s addObject:pull];
        // Apple's own pointer settings, live (see common/NativeEmbed.h): Accessibility > Pointer Control, then General > Trackpad & Mouse. Each
        // starts with its own group, so they follow as Apple shows them.
        _msNativePages = [NSMutableArray array];
        NSArray *ax = MSNESpecifiers(self, @"AXPointerControlController", @[@"/System/Library/PreferenceBundles/AccessibilitySettings.bundle"], @"Pointer Control", _msNativePages, nil);
        if (ax.count) [s addObjectsFromArray:ax];
        NSArray *tp = MSNESpecifiers(self, @"PSGMousePointerViewController", @[], @"Trackpad & Mouse", _msNativePages, nil);
        if (tp.count) [s addObjectsFromArray:tp];
        _specifiers = s;
    }
    return _specifiers;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Pointer";
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];   // back from Pointer Style (show or hide the Mac options) or from one of Apple's sub-pages (Color, Double-Tap to Drag)
}
@end

// The sidebar row, inserted by MacSettings.x's list hook right after the Home Bar row. Like Bluetooth's "On", it shows the Pointer Style.
@interface MSPointerRowValue : NSObject
@end
@implementation MSPointerRowValue
- (id)msPointerStyleValue:(id)specifier { return [MSPointerStyle() isEqualToString:@"ipados"] ? @"iPadOS" : @"Mac"; }
@end
static MSPointerRowValue *gMSPointerRowValue;
PSSpecifier *MSPointerRowSpecifier(id target) {
    if (!gMSPointerRowValue) gMSPointerRowValue = [MSPointerRowValue new];
    PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:@"Pointer" target:gMSPointerRowValue set:nil get:@selector(msPointerStyleValue:) detail:[MSPointerListController class] cell:kCellLinkList edit:nil];
    [row setIdentifier:kPointerRowID];
    [row setProperty:MSPointerIcon() forKey:@"iconImage"];
    return row;
}
// Live: attaching or detaching a trackpad/mouse adds or removes the row in the open sidebar.
static __weak PSListController *gMSSidebar;
// (reloading the list made the sidebar jump several rows down when the Pointer row went away with its page open -- seen on the iPad 2; the
// scroll position is kept as it was)
void MSReloadSidebarKeepingScroll(PSListController *l) {   // (also used by the Keyboard row)
    UITableView *t = nil; @try { t = [l valueForKey:@"table"]; } @catch (NSException *e) {}
    if (![t isKindOfClass:[UITableView class]]) { [l reloadSpecifiers]; return; }
    CGPoint off = t.contentOffset;
    [l reloadSpecifiers];
    [t layoutIfNeeded];
    CGFloat maxY = MAX(-t.adjustedContentInset.top, t.contentSize.height + t.adjustedContentInset.bottom - t.bounds.size.height);
    off.y = MIN(MAX(off.y, -t.adjustedContentInset.top), maxY);
    [t setContentOffset:off animated:NO];
    dispatch_async(dispatch_get_main_queue(), ^{ if (fabs(t.contentOffset.y - off.y) > 0.5) [t setContentOffset:off animated:NO]; });   // (a selection restore that scrolls a moment later)
}
void MSPointerWatchSidebar(PSListController *sidebar) {
    gMSSidebar = sidebar;
    static int token = 0;
    if (token) return;
    notify_register_dispatch("com.besiktasliseba.macpointer.device.changed", &token, dispatch_get_main_queue(), ^(int t) {
        PSListController *l = gMSSidebar;
        BOOL shown = NO;
        for (PSSpecifier *sp in [l specifiers]) if ([[sp identifier] isEqualToString:kPointerRowID]) { shown = YES; break; }
        if (l && shown != MSPointerDeviceAttached()) MSReloadSidebarKeepingScroll(l);
    });
    // (the same for the Home Bar row: SpringBoard finds out whether this device has a home bar at all, see HomeBar.x)
    // (the row shows the Pointer Style: redrawn when the style changes, from the Pointer page or anywhere else)
    static int styleToken = 0;
    notify_register_dispatch("com.besiktasliseba.macstatusbar/prefsChanged", &styleToken, dispatch_get_main_queue(), ^(int t) {
        PSListController *l = gMSSidebar;
        SEL r = NSSelectorFromString(@"reloadSpecifierID:");
        if (!l || ![l respondsToSelector:r]) return;
        for (PSSpecifier *sp in [l specifiers]) if ([[sp identifier] isEqualToString:kPointerRowID]) { ((void (*)(id, SEL, id))objc_msgSend)(l, r, kPointerRowID); break; }
    });
    static int pillToken = 0;
    notify_register_dispatch("com.besiktasliseba.machomebar.pill.changed", &pillToken, dispatch_get_main_queue(), ^(int t) {
        PSListController *l = gMSSidebar;
        if (l) MSReloadSidebarKeepingScroll(l);
    });
}
